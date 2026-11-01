local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs

-- Catalog routes into real runnable labs; samples are selected by exact class.
local Catalog = {}
local routes = {
    Shader2D = 'shaderLab',
    Shader3D = 'shaderLab',
    Ramp = 'animationLab',
    SurfaceAppearance3D = 'modelLab',
    Animator = 'modelLab',
    AnimationTrack = 'modelLab',
    Bone3D = 'modelLab',
    ParticleEmitter3D = 'particles',
    Body3D = 'physics',
    Collider3D = 'physics',
    DirectionalLight3D = 'shadows',
    BillboardUI = 'surfaceGallery',
    SurfaceUI = 'surfaceGallery',
    Decal3D = 'surfaceGallery',
    ClickDetector3D = 'surfaceGallery',
    Mesh3D = 'nodes',
    Attachment3D = 'nodes',
    Camera3D = 'nightPlayer',
    PointLight3D = 'nodes',
    SpotLight3D = 'nightPlayer',
    Node = 'nodes',
    Node3D = 'nodes',
    Folder = 'nodes',
    World3D = 'viewports',
    World2D = 'viewports',
    ViewportFrame = 'viewports',
    Environment = 'viewports',
    BouncePad = 'nightPlayer',
    SceneButton = 'nightPlayer',
    OrbitNode = 'nodes',
}
local descriptions = {
    SurfaceAppearance3D = 'Toggle normal, roughness, metalness and emission maps on the imported '
        .. 'cube.',
    Animator = 'Blend procedural states, toggle bone debug, inspect tracks and their masks.',
    AnimationTrack = 'Tune speed, loop, weight, Order and FadeIn/FadeOut; edit BoneMask in '
        .. 'Workspace.',
    Bone3D = 'Inspect bind pose, apply local offsets and parent an Attachment3D.',
    Body3D = 'Switch body mode, friction, restitution or isTrigger. Use the Physics controls.',
    Collider3D = 'Resize/change its shape in Workspace; watch the body and enable collider debug.',
    Camera3D = 'Switch first/third person. Drag to look; tune follow and layer-group properties.',
    ClickDetector3D = 'Close Workspace and tap the orange cube; camera dragging cancels a click.',
    DirectionalLight3D = 'Use Rotation; multiple sources share maxActiveLights. Priority selects '
        .. 'directional winners.',
    Node = 'Emit a sample event; rename/reparent and inspect its lifecycle in Workspace.',
    Ramp = 'Edit points, alpha and Offset; the gallery also demonstrates a stroke gradient.',
    UIStroke = 'Change Thickness or Enabled. Transparent text keeps only an exterior outline.',
    UICorner = 'Change Radius; test clipping and rounded pointer hit areas.',
    Decal3D = 'Switch Decal / Texture / Tiles and edit the mode-specific properties.',
    BillboardUI = 'Toggle debugEnabled; edit local/world/extents offsets, tilt and AnchorPoint.',
    SurfaceUI = 'Tap the surface buttons and inspect the selected face/canvas settings.',
}

function Catalog.names()
    local result, seen = {}, {}
    for name, class in pairs(require('source.engine.nodes').classes) do
        if name == class.name and not class.editorOnly then
            result[#result + 1] = name
            seen[name] = true
        end
    end
    for _, name in ipairs({ 'BouncePad', 'SceneButton', 'OrbitNode' }) do
        if not seen[name] then
            result[#result + 1] = name
        end
    end
    table.sort(result)
    return result
end

function Catalog.zone(name)
    if name:find('Constraint') then
        return 'animationPhysicsLab'
    end
    if name:match('^Sound') then
        return 'audioNodes'
    end
    return routes[name] or 'uiGallery'
end

local function exact(root, name)
    if root.className == name then
        return root
    end
    for _, node in ipairs(root:getDescendants()) do
        if node.className == name then
            return node
        end
    end
end

function Catalog.prepare(scene, name)
    if scene.nodeSampleControls then
        scene.nodeSampleControls:destroy()
    end
    local node = scene.demo and scene.demo.root and exact(scene.demo.root, name)
        or exact(scene.world.root, name)
        or exact(scene.ui, name)
    if not node then
        if name == 'Constraint3D' then
            local source = scene.demo.constraints[1]
            node = scene.world:create('Constraint3D', {
                name = 'BaseConstraint',
                attachment0 = source.attachment0,
                attachment1 = source.attachment1,
            }, scene.world.root)
            node.kind = 'Spherical'
        elseif name == 'Node' or name == 'Node3D' then
            node = scene.world:create(name, { name = 'Catalog' .. name })
        elseif name == 'SoundEffect' then
            node = scene.world:create(
                name,
                { name = 'BaseSoundEffect', enabled = false, effectType = 'reverb' },
                scene.demo.sound
            )
        elseif name == 'UINode' then
            node = scene.ui:create(
                name,
                { name = 'BaseUINode', position = { 0, 16, 0, 140 }, size = { 0, 200, 0, 60 } },
                scene.ui.content
            )
            scene.ui:text({ size = { 1, 0, 1, 0 }, text = 'Base UI node / child content' }, node)
        else
            error('Catalog sample missing for ' .. name)
        end
    end
    scene.nodeSample = node
    local root = scene.ui:scroll({
        position = { 0, 12, 1, -96 },
        size = { 0, math.min(480, scene.ui.width - 24), 0, 84 },
        anchorPoint = { 0, 0 },
        length = 120,
        backgroundColor = { 0.035, 0.065, 0.105 },
        name = 'Node sample controls',
    }, scene.ui.content)
    scene.nodeSampleControls = root
    local label = scene.ui:text({
        position = { 0, 8, 0, 4 },
        size = { 1, -16, 0, 50 },
        text = name
            .. ': '
            .. (
                descriptions[name]
                or (
                    name:match('^Sound')
                        and 'Use Audio controls to play/stop and enable effects. Edit the live sample.'
                    or 'Edit the selected live node. Close Workspace to interact with its scene.'
                )
            ),
        textScaled = true,
        maxTextSize = 13,
    }, root)
    scene.ui:button({
        position = { 0, 8, 0, 58 },
        size = { 0.5, -12, 0, 38 },
        text = 'Select sample',
        fontSize = 14,
        onPress = function()
            if node.destroyed then
                label.text = 'Sample was destroyed; reopen this lab to recreate it'
                return
            end
            scene.workspace:toggle(true)
            scene.workspace:select(node)
        end,
    }, root)
    scene.ui:button({
        position = { 0.5, 4, 0, 58 },
        size = { 0.5, -12, 0, 38 },
        text = 'Node catalog',
        fontSize = 14,
        onPress = function()
            scene.manager:switch(require('source.game.runtime.nodeCatalog').new)
        end,
    }, root)
    if name == 'Node' then
        local count = 0
        node:connect('sample', function()
            count = count + 1
            label.text = 'Node sample event count: ' .. count
        end)
        scene.ui:button({
            position = { 0, 8, 0, 102 },
            size = { 1, -16, 0, 38 },
            text = 'Emit event',
            onPress = function()
                node:emit('sample')
            end,
        }, root)
        root.length = 148
    end
    scene.workspace:toggle(true)
    scene.workspace:select(node)
    return node
end

return Catalog
