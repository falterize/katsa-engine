-- One module per SoundEffect class: { name, effectType, category, defaults }.
-- Only real katsa effect types are exposed. Pitch uses Source:setPitch.
local Node = require('../../core.baseNode')

local modules = {
    'reverb',
    'echo',
    'chorus',
    'distortion',
    'filter',
    'pitch',
}

local Types = { list = {}, byName = {} }

function Types.register()
    for _, module in ipairs(modules) do
        local definition = require('source.engine.nodes.audio.effectTypes.' .. module)
        local defaults = definition.defaults
        local class = Node.define(definition.name, 'SoundEffect')
        class.category = definition.category
        function class.initialize(self)
            self.effectType = self.effectType or definition.effectType
            for key, value in pairs(defaults) do
                if self[key] == nil then
                    self[key] = value
                end
            end
        end
        Types.list[#Types.list + 1] = definition.name
        Types.byName[definition.name] = definition
    end
end

return Types
