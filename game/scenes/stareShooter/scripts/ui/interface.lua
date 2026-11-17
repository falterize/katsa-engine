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

-- The LOD demo's control: one slider for the maximum distance (all switch points follow it).
function Interface.lodPanel(state, ui)
    local Theme = require('source.engine.ui.theme')
    local demo = state.lod
    local panel = ui:container({
        _viewportAuthored = true,
        name = 'LodControls',
        position = { 1, -12, 0, 12 },
        anchorPoint = { 1, 0 },
        size = { 0, 300, 0, 96 },
        backgroundColor = Theme.panel,
    }, ui.content)
    ui:create('UICorner', { radius = { 0, Theme.corner } }, panel)
    local title = ui:create('Label', {
        position = { 0, 10, 0, 6 },
        size = { 1, -20, 0, 24 },
        fontSize = 16,
    }, panel)
    local function show()
        title.text = ('Max distance: %d m'):format(demo.reach + 0.5)
    end
    local slider = ui:slider({
        position = { 0, 4, 0, 32 },
        size = { 1, -8, 0, 28 },
        min = demo.minReach,
        max = demo.maxReach,
        value = demo.reach,
    }, panel)
    slider:connect('changed', function(value)
        demo:setReach(value)
        show()
    end)
    ui:create('Label', {
        position = { 0, 10, 0, 62 },
        size = { 1, -20, 0, 28 },
        fontSize = 12,
        text = 'Green, yellow, orange, purple billboard, then hidden. Low value = see it close.',
    }, panel)
    show()
    require('source.engine.ui.widgets.collapsible').adopt(state.scene, 'Level of detail', panel)
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
    -- Off by default; F7 or the Workspace switches it on. Its own layer keeps it independent of the
    -- retro filter, so both can run together.
    if not scene.world.shaderLayers.priorities.Datamosh then
        scene.world.shaderLayers:add('Datamosh')
    end
    state.datamosh = ui:create('Shader2D', {
        _viewportAuthored = true,
        name = 'Datamosh',
        size = { 1, 0, 1, 0 },
        shaderPath = 'scene://shaders/datamosh.glsl',
        shaderLayer = 'Datamosh',
        enabled = scene.settings.datamosh.enabled,
        backgroundTransparency = 1,
        zIndex = 1,
        animated = true,
        uniforms = {},
    }, ui.content)
    -- The character's outline: the shader sees only the layer group Outlined (viewLayers).
    if not scene.world.shaderLayers.priorities.Outline then
        scene.world.shaderLayers:add('Outline')
    end
    state.outline = ui:create('Shader2D', {
        _viewportAuthored = true,
        name = 'CharacterOutline',
        size = { 1, 0, 1, 0 },
        shaderPath = 'scene://shaders/outline.glsl',
        shaderLayer = 'Outline',
        viewLayers = 'Outlined',
        enabled = scene.settings.outline.enabled,
        backgroundTransparency = 1,
        zIndex = 1,
        uniforms = {},
    }, ui.content)
    Interface.lodPanel(state, ui)
    if scene.settings.presentation.menuButton ~= false then
        scene.input.menuButton = cornerButton(ui, 'EngineMenuToggle', 'Engine menu', 16, function()
            scene.input:toggleMenu()
        end)
        local ragdoll = cornerButton(ui, 'RagdollToggle', 'Ragdoll (R)', 72, function()
            state.ragdoll:toggle()
        end)
        require('source.engine.ui.widgets.collapsible').adopt(scene, 'Ragdoll', { ragdoll })
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
