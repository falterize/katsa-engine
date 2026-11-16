-- Classes omit the properties they never read: no default, no inspector row.
local Resources = require('source.engine.core.resources')
local World3D = require('source.engine.world.world')
local Nodes = require('source.engine.nodes')
local Policy = require('source.engine.nodes.core.classPolicy')
local Properties = require('source.engine.editor.inspectors.properties')

local Module = {}

local expected = {
    Bone3D = { 'transparency' },
    AudioListener = { 'transparency', 'scale', 'inheritScale' },
    AudioSource = { 'transparency', 'scale', 'inheritScale' },
    StorageFolder = { 'replicated' },
    Root = { 'visible', 'replicated' },
}

function Module.run(self)
    for name, keys in pairs(expected) do
        local omitted = Policy.omitted(Nodes.classes[name])
        for _, key in ipairs(keys) do
            self:check(omitted[key], name .. ' omits ' .. key)
        end
    end
    local resources = Resources.new(require('validation.tests.fixtures.manifest'))
    local world = World3D.new(resources, require('game.data.settings').create())
    local bone = world:create('Bone3D', {})
    for _, row in ipairs(Properties.list(bone)) do
        self:check(row.key ~= 'transparency', 'Bone3D shows no transparency row')
    end
    self:check(bone.transparency == nil, 'Bone3D has no transparency value')
    -- The 3D constraint reads `enabled` every step, like Constraint2D, so both list it.
    self:check(
        Nodes.classes.Constraint3D.propertySchema.enabled ~= nil
            and Nodes.classes.Constraint2D.propertySchema.enabled ~= nil,
        'Constraint2D and Constraint3D both list enabled'
    )
    world:release()
end

return Module
