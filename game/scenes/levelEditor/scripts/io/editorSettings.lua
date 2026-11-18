-- Persistent editor preferences (theme, dock sizes, snap steps, grid, camera, key bindings):
-- defaults, a merge that keeps only known keys of the right type, and the text form.
-- Pure Lua; the file itself is written by the scene.
local LuaText = require('./luaText')
local TouchLayout = require('../ui.support.touchLayout')

local Settings = {}

Settings.FILE = 'editor/settings.lua'

function Settings.defaults()
    return {
        theme = 'dark',
        layout = { left = 250, right = 320, bottom = 190 },
        snap = { enabled = true, move = 0.5, rotate = 15, scale = 0.1 },
        grid = { cell = 1, major = 10, count = 60, visible = true },
        camera = { flySpeed = 10, sensitivity = 0.15, fov = 70 },
        bindings = {},
        touch = { mode = 'auto', lookSpeed = 1, controls = TouchLayout.defaults() },
    }
end

local function merge(defaults, data)
    local result = {}
    for key, default in pairs(defaults) do
        local value = type(data) == 'table' and data[key] or nil
        if type(default) == 'table' and key ~= 'bindings' then
            result[key] = merge(default, value)
        elseif key == 'bindings' then
            result[key] = type(value) == 'table' and value or {}
        elseif type(value) == type(default) and value == value then
            result[key] = value
        else
            result[key] = default
        end
    end
    return result
end

-- A complete settings table: unknown keys are dropped, wrong types fall back to the defaults.
function Settings.merge(data)
    return merge(Settings.defaults(), data)
end

function Settings.serialize(settings)
    return LuaText.serialize(settings)
end

function Settings.parse(text)
    local data = text and LuaText.parse(text, 'settings.lua')
    return Settings.merge(data)
end

return Settings
