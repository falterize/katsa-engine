-- The Inspector's uniform editor follows the shader's hints: ranges, colour channels, enums.
local Resources = require('source.engine.core.resources')
local World3D = require('source.engine.world.world')
local UniformEditor = require('source.engine.editor.inspectors.uniformEditor')
local Programs = require('source.engine.graphics.shaders.programs')

local Module = {}

-- A popup stand-in that records its rows: label -> { text, apply }.
local function fakePopup(node)
    local popup = { target = node, rows = {}, body = {} }
    popup.ui = {
        container = function(_, props)
            popup.swatch = props
            return props
        end,
    }
    function popup:input(label, text, _, apply)
        self.rows[label] = { text = text, apply = apply }
    end
    return popup
end

function Module.run(self)
    local resources = Resources.new(require('source.game.data.manifest'))
    local world = World3D.new(resources)
    local node = world:create('Shader3D', {
        name = 'Edited',
        shaderPath = 'validation/tests/fixtures/shaders/displace.glsl',
    })
    local popup = fakePopup(node)
    UniformEditor.open(popup)
    local amplitude = popup.rows['amplitude [0..2]']
    self:check(
        amplitude and amplitude.text == '0.25' and popup.swatch ~= nil,
        'The uniform editor lists the declared uniforms with their defaults and a colour swatch'
    )
    local ok, message = amplitude.apply('3')
    self:check(not ok and message:find('0..2', 1, true), 'A value outside hint_range is rejected')
    self:check(amplitude.apply('1.5') and node.uniforms.amplitude == 1.5, 'A value inside the range is stored')
    local red = popup.rows['glow r']
    self:check(not red.apply('2'), 'Colour channels stay within 0..1')
    self:check(
        red.apply('0.5') and node.uniforms.glow[1] == 0.5 and node.uniforms.glow[3] == 0.25,
        'Editing one colour channel keeps the others from the default'
    )

    local enum = Programs.parseText(
        'shader_type spatial;\nuniform int mode : hint_enum("Soft", "Hard") = 0;\nvoid fragment() {}',
        'enum.glsl',
        'spatial'
    )
    self:check(
        enum.uniforms[1].hints.hint_enum[1] == 'Soft' and enum.uniforms[1].hints.hint_enum[2] == 'Hard',
        'hint_enum keeps its option names'
    )
end

return Module
