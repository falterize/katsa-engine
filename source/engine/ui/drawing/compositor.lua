local unpack = require('../../math.array').unpack
local ipairs = require('../../math.array').ipairs
local pairs = require('../../math.array').pairs
local Programs = require('../../graphics.shaders.programs')
local Tags = require('../../graphics.shaders.tags')
local Samplers = require('../../graphics.shaders.samplers')
local SceneTextures = require('../../graphics.pipeline.sceneTextures')
local Velocity = require('../../graphics.pipeline.velocity')
local LayerPass = require('../../graphics.pipeline.layerPass')
local EffectHistory = require('./effectHistory')
-- Screen-space post effects operate on a snapshot, never read their draw target.
local Compositor = {}

local function active(node)
    local world = node._sceneWorld
    if world and world.debug and world.debug.wireframe then
        return false
    end
    return node:isA('Shader2D')
        and node.enabled ~= false
        and node.shaderPath ~= ''
        and node.shaderTransparency < 1
end

-- Collects the visible effects of the frame. A tagged Shader2D lands in `tagged` (and in `out`, for
-- the layer masks); any other UI node that carries a `#shader-` tag lands in `targets`.
local function collect(list, out, tagged, targets)
    for _, node in ipairs(list) do
        if
            node:isA('UINode')
            and node.visible ~= false
            and not node._layoutCollapsed
            and (not node.ui or node.ui:layerVisible(node))
        then
            local carriesTag = rawget(node, '_tags') and Tags.has(node)
            if active(node) then
                out[#out + 1] = node
                if carriesTag then
                    tagged[#tagged + 1] = node
                end
            end
            if carriesTag and not node:isA('Shader2D') then
                targets[#targets + 1] = node
            end
            collect(node.children, out, tagged, targets)
        end
    end
end

local function canvas(ui, key, w, h, density)
    density = density or katsa.graphics.getDPIScale()
    if not ui._compositorCleanup then
        ui._compositorCleanup = true
        ui:onDestroy(function()
            for _, name in ipairs({ '_sceneCanvas', '_postSnapshot', '_adjustShader' }) do
                if ui[name] then
                    ui.resources:releaseOwned(ui[name])
                    ui[name] = nil
                end
            end
        end)
    end
    local old = ui[key]
    if not old or old:getWidth() ~= w or old:getHeight() ~= h or old:getDPIScale() ~= density then
        if old then
            ui.resources:releaseOwned(old)
        end
        old = ui.resources:own(katsa.graphics.newCanvas(w, h, { dpiscale = density }))
        ui[key] = old
    end
    return old
end

local function reset()
    local g = katsa.graphics
    g.origin()
    g.setScissor()
    g.setStencilTest()
    g.setDepthMode()
    g.setShader()
    g.setMeshCullMode('none')
    g.setColor(1, 1, 1, 1)
    g.setBlendMode('alpha', 'premultiplied')
end
local restoreScissor = require('../../graphics.state').reapplyScissor

-- The plane's Adjustments (World2D Environment), or nil while they are off.
local function adjustments(ui)
    local values = ui.environment and ui.environment.adjustments
    return values and values.enabled == true and values or nil
end

local function adjustShader(ui, values)
    if not ui._adjustShader then
        ui._adjustShader = ui.resources:own(
            (Programs.compile('assets/shaders/engine/post/adjust2D.glsl'))
        )
    end
    ui._adjustShader:send('adjust', { values.brightness, values.contrast, values.saturation })
    return ui._adjustShader
end

function Compositor.draw(ui, draw)
    local effects = ui._postEffects or {}
    ui._postEffects = effects
    for i = #effects, 1, -1 do
        effects[i] = nil
    end
    local tagged = ui._taggedEffects or {}
    local targets = ui._taggedTargets or {}
    ui._taggedEffects, ui._taggedTargets = tagged, targets
    for i = #tagged, 1, -1 do
        tagged[i] = nil
    end
    for i = #targets, 1, -1 do
        targets[i] = nil
    end
    collect(ui.children, effects, tagged, targets)
    local layerWorld = ui._sceneWorld or ui.owner and ui.owner._world
    if #tagged > 1 and layerWorld then
        -- Tagged effects sharing a tag stack by shader layer priority, then zIndex.
        table.sort(tagged, function(a, b)
            local pa = layerWorld.shaderLayers:priority(a.shaderLayer)
            local pb = layerWorld.shaderLayers:priority(b.shaderLayer)
            if pa ~= pb then
                return pa < pb
            end
            return (a.zIndex or 0) < (b.zIndex or 0)
        end)
    end
    local alpha = 1 - math.max(0, math.min(1, ui.transparency or 0))
    if alpha <= 0 or ui.visible == false then
        return
    end
    local adjust = adjustments(ui)
    if #effects == 0 and alpha == 1 and not adjust or ui._compositing then
        return draw(ui)
    end
    local g = katsa.graphics
    local target = g.getCanvas()
    local w, h = g.getDimensions()
    if target then
        w, h = target:getDimensions()
    end
    local scene =
        canvas(ui, '_sceneCanvas', w, h, target and target:getDPIScale() or g.getDPIScale())
    g.push('all')
    g.setCanvas({ scene, stencil = true })
    reset()
    g.clear(0, 0, 0, 0, 0)
    -- The scene canvas holds interface pixels only. The 3D render underneath (the target, or the
    -- UI background) is mixed in per effect, and only for Shader2D nodes whose shader layer interacts with Default3D.
    local background = target or ui.backgroundCanvas
    g.setBlendMode('alpha', 'alphamultiply')
    ui._compositing = true
    ui._sceneColor = scene
    ui._sceneBackground = background
    draw(ui)
    ui._compositing = false
    ui._sceneColor = nil
    ui._sceneBackground = nil
    g.flushBatch()
    g.pop()
    restoreScissor()
    g.push('all')
    reset()
    g.setColor(alpha, alpha, alpha, alpha)
    if adjust then
        g.setShader(adjustShader(ui, adjust))
    end
    g.draw(scene)
    g.flushBatch()
    g.pop()
    restoreScissor()
end

local itemTemplate = 'assets/shaders/engine/canvas/item.glsl'

local function release(ui, node)
    if node._postShader then
        ui.resources:releaseOwned(node._postShader)
        node._postShader, node._postProgram = nil, nil
    end
end

-- Compiles the node's canvas_item shader when its path changes and uploads its uniforms:
-- the engine's frame values, then the node's `uniforms` over the defaults the file declares.
local function shader(ui, node)
    if node._shaderPath ~= node.shaderPath then
        release(ui, node)
        local parsed = Programs.parse(ui.resources:canonical(node.shaderPath), 'canvas_item')
        local compiled, program = Programs.compile(itemTemplate, { shaders = { parsed } })
        for name in pairs(node.uniforms) do
            assert(
                program.uniforms['s1_' .. name],
                ('Shader2D %s sets uniform "%s" that %s does not declare'):format(
                    tostring(node.name),
                    name,
                    node.shaderPath
                )
            )
        end
        node._postShader = ui.resources:own(compiled)
        node._postProgram = program
        node._postScreenUniform, node._postDepthUniform = nil, nil
        node._postVelocityUniform, node._postHistoryUniform = nil, nil
        node._postLayerUniform, node._postLayerDepthUniform = nil, nil
        for name, meta in pairs(program.uniforms) do
            if meta.info.hints.hint_screen_texture then
                node._postScreenUniform = name
            elseif meta.info.hints.hint_depth_texture then
                node._postDepthUniform = name
            elseif meta.info.hints.hint_velocity_texture then
                node._postVelocityUniform = name
            elseif meta.info.hints.hint_history_texture then
                node._postHistoryUniform = name
            elseif meta.info.hints.hint_layer_texture then
                node._postLayerUniform = name
            elseif meta.info.hints.hint_layer_depth_texture then
                node._postLayerDepthUniform = name
            end
        end
        node._shaderPath = node.shaderPath
        node:onDestroy(function()
            release(ui, node)
        end)
    end
    local s = node._postShader
    if s:hasUniform('shaderAmount') then
        s:send('shaderAmount', 1 - node.shaderTransparency)
    end
    if s:hasUniform('time') then
        s:send('time', ui.time)
    end
    local program = node._postProgram
    for compiled, meta in pairs(program.uniforms) do
        local value = node.uniforms[meta.name]
        if value == nil then
            value = program.defaults[compiled]
        end
        if value ~= nil and s:hasUniform(compiled) then
            if meta.info.sampler then
                value = Samplers.resolve(ui.resources, value, meta.info)
            end
            if value ~= nil then
                s:send(compiled, value)
            end
        end
    end
    return s
end

-- Whether `target` is the outermost node `effect` reaches: its rectangle already holds the
-- descendants that inherit the tag, so only this node runs the effect.
function Compositor.isTagRoot(effect, target)
    return Tags.applies(effect, target)
        and not (target.parent and Tags.applies(effect, target.parent))
end

-- Appends to `out` the nodes below `region` that `effect` does not reach (their subtrees included).
local function excluded(effect, region, out)
    for _, child in ipairs(region.children) do
        if child:isA('UINode') and child.visible ~= false then
            if Tags.applies(effect, child) then
                excluded(effect, child, out)
            else
                out[#out + 1] = child
            end
        end
    end
end

-- Runs `node`'s effect over `region`'s rectangle (the node itself unless it is tagged: then the
-- effect runs over each target that carries its tag, see `Compositor.applyTagged`).
function Compositor.apply(ui, node, region)
    if not ui._sceneColor or not active(node) then
        return
    end
    region = region or node
    local g = katsa.graphics
    local scene = ui._sceneColor
    local w, h = scene:getDimensions()
    local x, y = g.transformPoint(region._x, region._y)
    local x2, y2 = g.transformPoint(region._x + region._width, region._y + region._height)
    if x2 <= x or y2 <= y then
        return
    end
    local snapshot = canvas(ui, '_postSnapshot', w, h, scene:getDPIScale())
    g.push('all')
    g.setCanvas(snapshot)
    reset()
    g.clear(0, 0, 0, 0)
    local layerWorld = ui._sceneWorld or ui.owner and ui.owner._world
    local allowed = layerWorld
        and layerWorld.shaderLayers
        and layerWorld.shaderLayers:affects3D(node.shaderLayer, layerWorld.shaderNodes)
    local background = allowed and ui._sceneBackground
    if background then
        g.draw(background, 0, 0, 0, w / background:getWidth(), h / background:getHeight())
        g.setBlendMode('alpha', 'alphamultiply')
    end
    g.draw(scene)
    g.flushBatch()
    g.pop()
    restoreScissor()
    node._effectQuad = node._effectQuad or node:own(g.newQuad(x, y, x2 - x, y2 - y, w, h))
    require('source.engine.graphics.state').restoreUIStencil(ui)
    node._effectQuad:setViewport(x, y, x2 - x, y2 - y, w, h)
    local effect = shader(ui, node)
    -- `hint_screen_texture` in a canvas_item shader: the snapshot being processed (the interface
    -- plus, when the shader layer allows it, the 3D render); address it with UV like TEXTURE.
    local screenUniform = node._postScreenUniform
    if screenUniform and effect:hasUniform(screenUniform) then
        effect:send(screenUniform, snapshot)
    end
    -- `hint_depth_texture`: the opaque depth of the 3D render under the interface, when the
    -- shader layer interacts with Default3D and a 3D render exists; otherwise "infinitely far".
    local depthUniform = node._postDepthUniform
    if depthUniform and effect:hasUniform(depthUniform) then
        local renderer = allowed and ui.backgroundRenderer
        local camera = renderer and renderer.camera
        if camera then
            effect:send(depthUniform, SceneTextures.depth(renderer))
            if effect:hasUniform('depthRange') then
                effect:send('depthRange', { camera.projection[11], camera.projection[12] })
            end
            if effect:hasUniform('orthographic') then
                effect:send('orthographic', camera.orthographic == true)
            end
        else
            effect:send(depthUniform, ui.resources:image('white'))
        end
    end
    -- `hint_velocity_texture`: per-pixel motion of the 3D render (current uv minus previous uv in rg,
    -- 1 in b where a moving mesh wrote it); zero when there is no 3D render under the effect.
    local velocityUniform = node._postVelocityUniform
    if velocityUniform and effect:hasUniform(velocityUniform) then
        local renderer = allowed and ui.backgroundRenderer
        if renderer and renderer.camera then
            effect:send(velocityUniform, Velocity.get(renderer))
        else
            effect:send(velocityUniform, Velocity.zero(ui))
        end
    end
    -- `hint_layer_texture` / `hint_layer_depth_texture`: a render of only the layer groups in
    -- `viewLayers` (see layerPass.lua); transparent black and "infinitely far" when there are none.
    local layerUniform, layerDepthUniform = node._postLayerUniform, node._postLayerDepthUniform
    if layerUniform or layerDepthUniform then
        local renderer = allowed and ui.backgroundRenderer
        local world = renderer and renderer.world
        local mask = world and renderer.camera and LayerPass.mask(world, node.viewLayers)
        local color, depth
        if mask then
            color, depth = LayerPass.get(ui, renderer, mask)
        end
        if layerUniform and effect:hasUniform(layerUniform) then
            effect:send(layerUniform, color or LayerPass.empty(ui))
        end
        if layerDepthUniform and effect:hasUniform(layerDepthUniform) then
            effect:send(layerDepthUniform, depth or ui.resources:image('white'))
        end
    end
    -- `hint_history_texture`: this effect's own result from the previous frame.
    local historyUniform = node._postHistoryUniform
    if historyUniform and effect:hasUniform(historyUniform) then
        effect:send(historyUniform, EffectHistory.get(node, snapshot))
    end
    -- Built-in region uniforms describe this actual canvas/draw, including resize and nesting.
    if effect:hasUniform('canvasSize') then
        effect:send('canvasSize', { w, h })
    end
    if effect:hasUniform('regionOrigin') then
        effect:send('regionOrigin', { x, y })
    end
    if effect:hasUniform('regionExtent') then
        effect:send('regionExtent', { x2 - x, y2 - y })
    end
    local cx, cy, cw, ch = g.getScissor()
    g.push('all')
    g.origin()
    g.setShader(effect)
    g.setColor(1, 1, 1, 1)
    g.setBlendMode('replace', 'premultiplied')
    g.intersectScissor(x, y, x2 - x, y2 - y)
    local world = ui._sceneWorld or ui.owner and ui.owner._world
    local masks = {}
    for _, upper in ipairs(ui._postEffects) do
        if upper ~= node and world.shaderLayers:suppresses(upper.shaderLayer, node.shaderLayer) then
            if rawget(upper, '_tags') and Tags.has(upper) then
                -- A tagged effect masks only where its targets are.
                for _, target in ipairs(ui._taggedTargets) do
                    if Compositor.isTagRoot(upper, target) then
                        masks[#masks + 1] = target
                    end
                end
            else
                masks[#masks + 1] = upper
            end
        end
    end
    if region ~= node then
        -- Descendants the tags leave out (`#noshader-`, depth) are cut out of the effect.
        excluded(node, region, masks)
    end
    local regions = { { x, y, x2 - x, y2 - y } }
    for _, upper in ipairs(masks) do
        regions = require('source.engine.ui.input.regions').subtract(regions, {
            upper._x * ui.scale + ui.offsetX,
            upper._y * ui.scale + ui.offsetY,
            upper._width * ui.scale,
            upper._height * ui.scale,
        })
    end
    for _, cut in ipairs(regions) do
        g.setScissor()
        if cx then
            g.setScissor(cx, cy, cw, ch)
        end
        g.intersectScissor(unpack(cut))
        g.draw(snapshot, node._effectQuad, x, y)
    end
    g.flushBatch()
    g.pop()
    if historyUniform then
        EffectHistory.store(node, scene, x, y, x2 - x, y2 - y)
    end
    g.setScissor()
    if cx then
        g.setScissor(cx, cy, cw, ch)
    end
end

-- Called after `target` and its children are drawn: every tagged effect that shares a `#shader-`
-- tag with it processes the target's rectangle, in layer priority order.
function Compositor.applyTagged(ui, target)
    local tagged = ui._taggedEffects
    if not ui._sceneColor or not tagged or target:isA('Shader2D') then
        return
    end
    for _, effect in ipairs(tagged) do
        if effect ~= target and Compositor.isTagRoot(effect, target) then
            Compositor.apply(ui, effect, target)
        end
    end
end

return Compositor
