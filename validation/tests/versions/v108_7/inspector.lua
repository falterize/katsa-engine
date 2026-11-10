-- Inspector field policy: a key listed twice shows the property twice (fog density did).
local Policy = require('source.engine.editor.inspectors.propertyPolicy')

local Module = {}

function Module.run(self)
    local seen, duplicate = {}, nil
    for _, key in ipairs(Policy.fields) do
        if seen[key] then
            duplicate = key
        end
        seen[key] = true
    end
    -- Fog.ambient is a number although Environment.ambient is a colour: a number never opens the
    -- colour editor (it crashed there).
    local world = require('source.engine.world.world').new(self.manager.resources:scope())
    local fog = world.environment.fog
    fog._settingsKind, fog.volumetric = 'Fog', true
    local ambient, color
    for _, row in ipairs(require('source.engine.editor.inspectors.properties').list(fog)) do
        if row.key == 'ambient' then ambient = row end
        if row.key == 'color' then color = row end
    end
    self:check(ambient and ambient.colorMaximum == nil, 'a numeric ambient row opens no colour editor')
    self:check(color and color.colorMaximum ~= nil, 'a colour row still opens the colour editor')
    self:check(duplicate == nil, 'the inspector field list has no repeated key ' .. tostring(duplicate or ''))
end

return Module
