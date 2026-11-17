local Dialog = require('./dialog')
local Matrix = require('./matrix')

-- Interaction groups: render layers, 3D collision groups and 2D collision groups. Each is a
-- symmetric matrix of "interacts with" flags.
local Editor = { key = 'groups' }

local MODES = { 'Layers', 'Collisions 3D', 'Collisions 2D' }

function Editor.new()
    return {
        key = Editor.key,
        title = 'Interaction groups',
        mode = 1,
        states = { {}, {}, {} },
        status = '',
        draw = Editor.draw,
    }
end

local function physics2D(scene, host)
    local selected = host.selection
    local plane = selected and selected.isA and selected:isA('World2D') and selected
        or selected and selected._plane
        or scene.root:find('World3D/World2D')
    return plane and plane.physics2D
end

local function registry(scene, host, mode)
    if mode == 1 then
        return scene.world.layerGroups
    elseif mode == 2 then
        return scene.physics and scene.physics.collisionGroups
    end
    local physics = physics2D(scene, host)
    return physics and physics.collisionGroups
end

function Editor.draw(ig, scene, host, dialog)
    for index, name in ipairs(MODES) do
        if index > 1 then
            ig.sameLine()
        end
        local available = registry(scene, host, index) ~= nil
        if ig.radio(name, dialog.mode == index) and available then
            dialog.mode = index
        end
    end
    local r = registry(scene, host, dialog.mode)
    if not r then
        ig.textDisabled('This registry does not exist in the scene.')
        return
    end
    ig.separator()
    Matrix.draw(ig, dialog, dialog.states[dialog.mode], {
        names = r.names,
        limit = 30,
        interacts = function(a, b)
            return r:interacts(a, b)
        end,
        set = function(a, b, value)
            r:set(a, b, value)
        end,
        add = function(name)
            r:add(name)
        end,
        rename = function(from, to)
            r:rename(from, to)
        end,
        remove = function(name)
            r:remove(name)
        end,
        canRemove = function(name)
            return name ~= 'Default'
        end,
        canToggle = function()
            return true
        end,
    })
end

return Editor
