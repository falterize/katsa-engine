local Matrix = require('./matrix')

-- Shader layers of the world: the same matrix as the interaction groups plus a priority.
local Editor = { key = 'shaderLayers' }

function Editor.new()
    return {
        key = Editor.key,
        title = 'Shader layers',
        state = {},
        status = '',
        draw = Editor.draw,
    }
end

local function isDefault(name)
    return name == 'Default2D' or name == 'Default3D'
end

function Editor.draw(ig, scene, _, dialog)
    local r = scene.world.shaderLayers
    dialog.state.selected = dialog.state.selected or 'Default3D'
    Matrix.draw(ig, dialog, dialog.state, {
        names = r.names,
        limit = 30,
        interacts = function(a, b)
            return r:interacts(a, b)
        end,
        set = function(a, b, value)
            r:setInteracts(a, b, value)
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
            return not isDefault(name)
        end,
        canToggle = function(a, b)
            return a ~= b
        end,
        priority = function(name)
            return r:priority(name)
        end,
        setPriority = function(name, value)
            r:setPriority(name, value)
        end,
    })
end

return Editor
