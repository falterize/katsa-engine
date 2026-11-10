-- Node attributes (Get/SetAttribute) and the inspector rows that edit them; classes omit the
-- spatial properties they never read.
local Plugins = require('source.engine.plugins')
local Properties = require('source.engine.editor.inspectors.properties')
local Schema = require('source.engine.editor.inspectors.schema')
local World = require('source.engine.world.world')
local fields = require('source.engine.editor.inspectors.propertyPolicy').fields

local Tests = {}

local function row(list, key)
    for _, item in ipairs(list) do
        if item.key == key then
            return item
        end
    end
end

function Tests.run(tester)
    local world = World.new(tester.manager.resources:scope())
    Plugins.activate(world, { 'pathfinding', 'ik' })
    local a = world:create('Node3D', { name = 'A' })
    local b = world:create('Node3D', { name = 'B' })

    a:setAttribute('health', 80)
    a:setAttribute('label', 'boss')
    a:setAttribute('alive', true)
    a:setAttribute('spawn', { 1, 2, 3 })
    a:setAttribute('target', b)
    local seen, named = {}, 0
    a:connect('AttributeChanged', function(name, value)
        seen[#seen + 1] = name .. '=' .. tostring(value)
    end)
    a:onAttributeChanged('health', function()
        named = named + 1
    end)
    a:setAttribute('health', 70)
    a:setAttribute('label', 'minion')
    tester:check(
        a:getAttribute('health') == 70 and a:getAttribute('target') == b and a:getAttribute('missing', 5) == 5,
        'attributes hold numbers, strings, vectors and node references'
    )
    tester:check(#seen == 2 and named == 1, 'AttributeChanged fires for every change and per attribute name')
    a:setAttribute('label', nil)
    tester:check(a:getAttribute('label') == nil and a:getAttributes().alive == true, 'setting nil removes an attribute')
    local copy = a:clone({ name = 'Copy' })
    tester:check(
        copy:getAttribute('health') == 70 and copy:getAttribute('target') == b and copy:getAttribute('spawn') ~= a:getAttribute('spawn'),
        'a clone copies attributes (tables copied, node references shared)'
    )
    b:destroy()
    tester:check(a:getAttribute('target') == nil, 'a reference to a destroyed node reads as nil')

    local c = world:create('Node3D', { name = 'C' })
    local d = world:create('Node3D', { name = 'D' })
    c:setAttribute('speed', 4)
    c:setAttribute('flag', false)
    c:setAttribute('home', { 0, 1, 2 })
    c:setAttributeReference('friend', nil)
    local rows = Properties.list(c)
    tester:check(
        row(rows, 'speed').kind == 'number' and row(rows, 'flag').kind == 'boolean' and row(rows, 'home').kind == 'vector'
            and row(rows, 'friend').kind == 'node' and row(rows, 'add attribute') ~= nil,
        'the inspector lists attributes with their types and an add row'
    )
    local scene = tester.manager.scene or {}
    tester:check(Properties.set(scene, c, row(rows, 'speed'), '9') and c:getAttribute('speed') == 9, 'a number attribute is edited in the inspector')
    tester:check(Properties.set(scene, c, row(rows, 'home'), '5', 2) and c:getAttribute('home')[2] == 5, 'a vector attribute is edited per component')
    tester:check(Properties.set(scene, c, row(rows, 'friend'), d) and c:getAttribute('friend') == d, 'a node attribute takes a node reference')
    local add = row(rows, 'add attribute')
    Properties.set(scene, c, add, 'level = 3')
    Properties.set(scene, c, add, 'title = hello world')
    Properties.set(scene, c, add, 'size3 = 1, 2, 3')
    Properties.set(scene, c, add, 'owner: node')
    Properties.set(scene, c, add, 'flag =')
    tester:check(
        c:getAttribute('level') == 3 and c:getAttribute('title') == 'hello world' and c:getAttribute('size3')[3] == 3
            and c:isAttributeReference('owner') and c:getAttribute('flag') == nil,
        'the add row creates typed attributes, node slots and removes with an empty value'
    )
    tester:check(Schema.signature(c) ~= Schema.signature(world:create('Node3D', {})), 'attribute changes alter the inspector signature')

    local keys = function(node)
        return ' ' .. table.concat(Schema.keys(node, fields), ' ') .. ' '
    end
    local map = world:create('NavMap3D', {})
    local light = world:create('PointLight3D', {})
    local agent = world:create('NavAgent3D', {})
    tester:check(
        not keys(map):find(' rotation ') and not keys(map):find(' transparency ') and keys(map):find(' position '),
        'NavMap3D omits rotation and transparency but keeps its position'
    )
    tester:check(
        not keys(light):find(' scale ') and light.scale == nil and keys(light):find(' position '),
        'lights omit scale and transparency entirely'
    )
    tester:check(not keys(agent):find(' position ') and agent.position == nil, 'NavAgent3D is a technical node without any transform')
    tester:check(not keys(agent):find(' visible ') and agent.visible == nil, 'NavAgent3D has no visible property')
end

return Tests
