-- Descriptions the Inspector shows for properties. They are editor text only, so they live here
-- by category instead of in the node classes. Lookup order for a property of `target`:
--   1. the entry of its class, then its base classes (or of its settings kind);
--   2. the `hint` a custom node (plugin, scene) wrote into its own property descriptor;
--   3. the text shared by every class that has the property (`common.keys`).
local Common = require('./common')

local Hints = {}

-- Entries by class name (or settings kind) from every category file.
local sections = {
    require('./core'),
    require('./render'),
    require('./physics'),
    require('./animation'),
    require('./effects'),
    require('./ui'),
}
local byClass, bySettings = {}, require('./settings')
for _, section in ipairs(sections) do
    for class, entries in pairs(section) do
        assert(not byClass[class], 'Hints of ' .. class .. ' are listed twice')
        byClass[class] = entries
    end
end

-- `authored` is the hint of the property descriptor, when the node class carries one.
function Hints.get(target, key, authored)
    local kind = target._settingsKind or target._inputKind
    local entries = kind and bySettings[kind]
    if entries and entries[key] then
        return entries[key]
    end
    local class = target._class
    while class do
        entries = byClass[class.name]
        if entries and entries[key] then
            return entries[key]
        end
        class = class.base
    end
    return authored or Common.keys[key]
end

return Hints
