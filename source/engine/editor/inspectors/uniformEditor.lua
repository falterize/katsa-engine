local ipairs = require('../../math.array').ipairs
local unpack = require('../../math.array').unpack
local EnvironmentShaders = require('../../graphics.shaders.environmentShaders')

-- Inspector popup for the `uniforms` of a Shader3D / Shader2D node. It lists the uniforms the
-- shader file declares and lets the hints decide the widget:
--   hint_range(min, max[, step])   numbers are checked against the range (ints are whole)
--   source_color                   vec3 / vec4 channels are 0..1 and a swatch shows the colour
--   hint_enum("A", "B")            an int chosen by name or index
--   bool                           true / false
--   hint_screen_texture, hint_depth_texture, samplers: fed by the engine or from code, not listed
-- Values left alone stay at the file's default; an edit writes the entry into `uniforms`.
local UniformEditor = {}

local ROW = 40
local components = { vec2 = 2, vec3 = 3, vec4 = 4 }

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
    return not info.sampler
        and not info.array
        and not hints.hint_screen_texture
        and not hints.hint_depth_texture
        and (info.type == 'float' or info.type == 'int' or info.type == 'bool' or components[info.type])
end

local function current(node, info)
    local value = node.uniforms[info.name]
    if value == nil then
        value = info.default
    end
    if type(value) == 'table' then
        local copy = {}
        for i, item in ipairs(value) do
            copy[i] = item
        end
        return copy
    end
    return value
end

-- Checks a number against the uniform's hints; returns the stored number or nil and a message.
local function number(text, info, channel)
    local value = tonumber(text)
    if not value or value ~= value or math.abs(value) == math.huge then
        return nil, 'Enter a finite number'
    end
    if info.type == 'int' then
        if value ~= math.floor(value) then
            return nil, 'Enter a whole number'
        end
    end
    local range = info.hints.hint_range
    if channel and info.hints.source_color then
        range = { 0, 1 }
    end
    if range and (value < range[1] or value > range[2]) then
        return nil, ('%s must be within %g..%g'):format(info.name, range[1], range[2])
    end
    return value
end

local function label(info, channel)
    local text = info.name
    if channel then
        text = text .. ' ' .. ({ 'r', 'g', 'b', 'a' })[channel]
    end
    local range = info.hints.hint_range
    if range then
        text = ('%s [%g..%g]'):format(text, range[1], range[2])
    end
    return text
end

function UniformEditor.open(popup)
    local node = popup.target
    local info = parsed(node)
    local row = 0
    for _, uniform in ipairs(info and info.uniforms or {}) do
        if editable(uniform) then
            local name, kind = uniform.name, uniform.type
            local function write(value)
                node.uniforms[name] = value
            end
            if components[kind] then
                local value = current(node, uniform) or {}
                local swatch
                if uniform.hints.source_color then
                    swatch = popup.ui:container({
                        position = { 0, 6, 0, row * ROW },
                        size = { 1, -12, 0, 24 },
                        backgroundColor = { value[1] or 0, value[2] or 0, value[3] or 0 },
                    }, popup.body)
                    row = row + 1
                end
                for channel = 1, components[kind] do
                    local index = channel
                    popup:input(label(uniform, channel), tostring(value[channel] or 0), row * ROW, function(text)
                        local number_, message = number(text, uniform, index)
                        if not number_ then
                            return false, message
                        end
                        value[index] = number_
                        write({ unpack(value) })
                        if swatch then
                            swatch.backgroundColor = { value[1] or 0, value[2] or 0, value[3] or 0 }
                        end
                        return true
                    end)
                    row = row + 1
                end
            elseif kind == 'bool' then
                popup:input(name, tostring(current(node, uniform) == true), row * ROW, function(text)
                    if text ~= 'true' and text ~= 'false' then
                        return false, 'Enter true or false'
                    end
                    write(text == 'true')
                    return true
                end)
                row = row + 1
            else
                local options = uniform.hints.hint_enum
                local text = tostring(current(node, uniform) or 0)
                popup:input(options and (name .. ' ' .. table.concat(options, '/')) or label(uniform), text, row * ROW, function(entry)
                    if options then
                        for index, option in ipairs(options) do
                            if entry == option then
                                write(index - 1)
                                return true
                            end
                        end
                    end
                    local value, message = number(entry, uniform)
                    if not value then
                        return false, message
                    end
                    if options and (value < 0 or value >= #options) then
                        return false, ('%s must be 0..%d or a name'):format(name, #options - 1)
                    end
                    write(value)
                    return true
                end)
                row = row + 1
            end
        end
    end
    popup.body.length = math.max(row, 1) * ROW
end

return UniformEditor
