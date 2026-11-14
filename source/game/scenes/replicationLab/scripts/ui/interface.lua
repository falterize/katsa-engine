local Hud = require('./panels.hud')
local Chat = require('./panels.chat')

-- Screen UI of the lab: the engine-menu button, the round HUD and the chat.
local Interface = {}

-- state: content state (scene, session, input). Returns the pieces the content updates.
function Interface.create(state)
    local scene, ui = state.scene, state.scene.ui
    state.hud = Hud.create(ui, state.session)
    state.chat = Chat.create(ui, {
        send = function(text)
            state.session:sendChat(text)
        end,
        typing = function(typing)
            -- While the box is open the character stands still and the cursor is free.
            scene.input.captureWanted = not typing
            scene.input:reset()
        end,
    })
    if scene.settings.presentation.menuButton ~= false then
        scene.input.menuButton = ui:button({
            _viewportAuthored = true,
            name = 'EngineMenuToggle',
            position = { 1, -16, 1, -16 },
            size = { 0, 150, 0, 48 },
            anchorPoint = { 1, 1 },
            text = 'Engine menu',
            textScaled = true,
            maxTextSize = 18,
            zIndex = 100100,
            backgroundColor = { 0.08, 0.16, 0.25 },
        }, ui.content)
        scene.input.menuButton:connect('press', function()
            scene.input:toggleMenu()
        end)
    end
end

return Interface
