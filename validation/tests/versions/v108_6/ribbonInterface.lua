-- The ribbonLab control panel changes ribbon properties through its buttons.
local Interface = require('source.game.scenes.ribbonLab.scripts.ui.interface')

local Module = {}

function Module.run(self)
    local buttons = {}
    local ui = {}
    function ui:button(props)
        buttons[#buttons + 1] = props
        return props
    end
    function ui:container(props)
        props.ui = ui
        props.onDestroy = function() end
        return props
    end
    ui.content = {}
    local state = {
        scene = { ui = ui, input = { reset = function() end } },
        single = { width = 0.9, lifetime = 1.4, maxLength = 0, clear = function(node) node.cleared = true end },
        dual = { faceCamera = false, clear = function(node) node.cleared = true end },
        beam = { textureMode = 'Wrap', lightEmission = 1 },
        shade = { castShadow = true, receiveShadow = true, lightInfluence = 1 },
    }
    Interface.create(state)
    local function press(text)
        for _, button in ipairs(buttons) do
            if button.text:find(text, 1, true) then
                button:press()
                return button
            end
        end
        error('missing button ' .. text)
    end
    press('Trail width')
    self:check(state.single.width == 0.4, 'a cycle button moves a trail to its next width')
    press('Beam texture')
    self:check(state.beam.textureMode == 'Stretch', 'the beam texture mode cycles')
    local shadow = press('Cast shadow')
    self:check(state.shade.castShadow == false and shadow.text == 'Cast shadow: off', 'a boolean button toggles and relabels')
    press('Clear trails')
    self:check(state.single.cleared and state.dual.cleared, 'the clear button resets both trails')
end

return Module
