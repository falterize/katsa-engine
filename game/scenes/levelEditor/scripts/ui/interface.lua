-- Editor HUD (stage a): a help line and a status bar. The Workspace tree, the Properties panel
-- and the toolbar arrive in later stages; labels never take clicks so the viewport stays live.
local Interface = {}

function Interface.create(state)
    local ui = state.scene.root:find('World3D/World2D')
    ui:create('Label', {
        name = 'Help',
        position = { 0, 12, 0, 10 },
        size = { 0, 760, 0, 40 },
        fontSize = 14,
        interactable = false,
        text = 'RMB + WASD/QE fly, wheel speed, LMB select (Ctrl adds), F focus, Home frame all, G grid, Q W E R tools, X space',
    }, ui.content)
    state.status = ui:create('Label', {
        name = 'Status',
        position = { 0, 12, 1, -30 },
        size = { 0, 900, 0, 22 },
        fontSize = 14,
        interactable = false,
    }, ui.content)
end

return Interface
