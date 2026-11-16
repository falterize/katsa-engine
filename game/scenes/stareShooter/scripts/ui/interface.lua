local Interface = {}

-- A bottom-right button; `lift` is the distance from the bottom edge in pixels.
local function cornerButton(ui, name, text, lift, onPress)
    local button = ui:button({
        _viewportAuthored = true,
        name = name,
        position = { 1, -16, 1, -lift },
        size = { 0, 150, 0, 48 },
        anchorPoint = { 1, 1 },
        text = text,
        textScaled = true,
        maxTextSize = 18,
        zIndex = 100100,
        backgroundColor = { 0.08, 0.16, 0.25 },
    }, ui.content)
    button:connect('press', onPress)
    return button
end

function Interface.create(state)
    local scene, ui = state.scene, state.scene.root:find('World3D/World2D')
    -- A layer that interacts with Default3D, so the filter also processes the 3D render.
    if not scene.world.shaderLayers.priorities.Screen then
        scene.world.shaderLayers:add('Screen')
    end
    state.retro = ui:create('Shader2D', {
        _viewportAuthored = true,
        name = 'RetroScreen',
        size = { 1, 0, 1, 0 },
        shaderPath = 'scene://shaders/retro.glsl',
        shaderLayer = 'Screen',
        enabled = scene.settings.retro.enabled,
        backgroundTransparency = 1,
        zIndex = 1,
        uniforms = {},
    }, ui.content)
    if scene.settings.presentation.menuButton ~= false then
        scene.input.menuButton = cornerButton(ui, 'EngineMenuToggle', 'Engine menu', 16, function()
            scene.input:toggleMenu()
        end)
        cornerButton(ui, 'RagdollToggle', 'Ragdoll (R)', 72, function()
            state.ragdoll:toggle()
        end)
    end
    -- Preserve the source Sprite2D's authored 324,323 center and 0.5962963 scale.
    state.hud = ui:create('ImageRect', {
        _viewportAuthored = true,
        name = 'CharacterHUD',
        position = { 0, 324, 0, 323 },
        size = { 0, 644, 0, 644 },
        anchorPoint = { 0.5, 0.5 },
        backgroundTransparency = 1,
        image = 'scene://textures/hud.png',
        zIndex = 2,
    }, ui.content)
end

return Interface
