local unpack = require('source.engine.math.array').unpack
local Dialog = require('./dialog')
local EnvironmentShaders = require('source.engine.graphics.shaders.environmentShaders')

-- The `uniforms` of a Shader3D / Shader2D: the shader file's declared uniforms, with the hints
-- choosing the widget (hint_range -> a clamped drag, source_color -> a colour picker, hint_enum
-- -> a combo, bool -> a checkbox, sampler2D -> a texture path). Engine-fed textures are not
-- listed. A value left alone stays at the file's default; an edit writes the entry.
local Editor = { key = 'uniforms' }

local components = { vec2 = 2, vec3 = 3, vec4 = 4 }

function Editor.new(request)
    return {
        key = Editor.key,
        title = 'Uniforms / ' .. tostring(request.target.name or request.target.className),
        target = request.target,
        edits = {},
        status = '',
        draw = Editor.draw,
    }
end

local function parsed(node)
    local world = node._world or node._sceneWorld
    if not world or node.shaderPath == '' then
        return nil
    end
    EnvironmentShaders.kind(world, node)
    return node._environmentParsed
end

local function editable(info)
    local hints = info.hints
    if
        info.array
        or hints.hint_screen_texture
        or hints.hint_depth_texture
        or hints.hint_velocity_texture
        or hints.hint_history_texture
        or hints.hint_layer_texture
        or hints.hint_layer_depth_texture
    then
        return false
    end
    if info.sampler then
        return info.type == 'sampler2D'
    end
    return info.type == 'float' or info.type == 'int' or info.type == 'bool' or components[info.type]
end

local function current(node, info)
    local value = node.uniforms[info.name]
    if value == nil then
        value = info.default
    end
    if type(value) == 'table' then
        return { unpack(value) }
    end
    return value
end

local function bounds(info, color)
    local range = info.hints.hint_range
    if color then
        return 0, 1
    end
    return range and range[1] or 0, range and range[2] or 0
end

function Editor.draw(ig, _, _, dialog)
    local node = dialog.target
    if node.destroyed then
        dialog.closed = true
        return
    end
    local info = parsed(node)
    local any = false
    for _, uniform in ipairs(info and info.uniforms or {}) do
        if editable(uniform) then
            any = true
            local name, kind = uniform.name, uniform.type
            ig.pushID(name)
            if kind == 'sampler2D' then
                local value = node.uniforms[name]
                local text = dialog.edits[name]
                    or (type(value) == 'string' and value)
                    or (type(value) == 'table' and tostring(value.name or 'node'))
                    or ''
                local changed, entry = ig.inputText(name .. ' (texture path)', text)
                if changed then
                    dialog.edits[name] = entry
                end
                if ig.deactivatedAfterEdit() and dialog.edits[name] then
                    node.uniforms[name] = dialog.edits[name] ~= '' and dialog.edits[name] or nil
                    dialog.edits[name] = nil
                end
            elseif components[kind] then
                local value = current(node, uniform) or {}
                local count = components[kind]
                for channel = 1, count do
                    value[channel] = value[channel] or 0
                end
                if uniform.hints.source_color then
                    local changed, color = ig.colorEdit3(name, value)
                    if changed then
                        for channel = 1, 3 do
                            value[channel] = color[channel]
                        end
                        node.uniforms[name] = { unpack(value) }
                    end
                    if count == 4 then
                        local moved, alpha = ig.sliderFloat(name .. ' a', value[4], 0, 1)
                        if moved then
                            value[4] = alpha
                            node.uniforms[name] = { unpack(value) }
                        end
                    end
                else
                    local low, high = bounds(uniform)
                    for channel = 1, count do
                        local moved, number = ig.dragFloat(('%s %s##c%d'):format(name, ({ 'x', 'y', 'z', 'w' })[channel], channel), value[channel], 0.01, low, high, '%.4g')
                        if moved then
                            value[channel] = number
                            node.uniforms[name] = { unpack(value) }
                        end
                    end
                end
            elseif kind == 'bool' then
                local changed, picked = ig.checkbox(name, current(node, uniform) == true)
                if changed then
                    node.uniforms[name] = picked
                end
            else
                local options = uniform.hints.hint_enum
                local value = tonumber(current(node, uniform)) or 0
                if options then
                    local changed, picked = ig.combo(name, math.max(1, math.min(#options, value + 1)), options)
                    if changed then
                        node.uniforms[name] = picked - 1
                    end
                else
                    local low, high = bounds(uniform)
                    local integer = kind == 'int'
                    local moved, number = ig.dragFloat(name, value, integer and 1 or 0.01, low, high, integer and '%.0f' or '%.4g')
                    if moved then
                        node.uniforms[name] = integer and math.floor(number + 0.5) or number
                    end
                end
            end
            local range = uniform.hints.hint_range
            if range and ig.hovered() then
                ig.tooltip(('%s: %g..%g'):format(name, range[1], range[2]))
            end
            ig.popID()
        end
    end
    if not any then
        ig.textDisabled('The shader declares no editable uniforms.')
    end
    Dialog.status(ig, dialog)
end

return Editor
