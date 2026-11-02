local unpack = require('source.engine.math.array').unpack
local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs
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

local function collect(list, out)
    for _, node in ipairs(list) do
        if
            node:isA('UINode')
            and node.visible
            and not node._layoutCollapsed
            and (not node.ui or node.ui:layerVisible(node))
        then
            if active(node) then
                out[#out + 1] = node
            end
            collect(node.children, out)
        end
    end
end

local function canvas(ui, key, w, h, density)
    density = density or katsa.graphics.getDPIScale()
    if not ui._compositorCleanup then
        ui._compositorCleanup = true
        ui:onDestroy(function()
            for _, name in ipairs({ '_sceneCanvas', '_postSnapshot' }) do
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
local restoreScissor = require('source.engine.graphics.state').reapplyScissor

function Compositor.draw(ui, draw)
    local effects = ui._postEffects or {}
    ui._postEffects = effects
    for i = #effects, 1, -1 do
        effects[i] = nil
    end
    collect(ui.children, effects)
    local alpha = 1 - math.max(0, math.min(1, ui.transparency or 0))
    if alpha <= 0 or ui.visible == false then
        return
    end
    if #effects == 0 and alpha == 1 or ui._compositing then
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
    g.draw(scene)
    g.flushBatch()
    g.pop()
    restoreScissor()
end

local function shader(ui, node)
    if node._shaderPath ~= node.shaderPath then
        if node._postShader then
            ui.resources:releaseOwned(node._postShader)
        end
        local source = assert(
            katsa.filesystem.read(ui.resources:canonical(node.shaderPath)),
            'Missing Shader2D: ' .. node.shaderPath
        )
        source = source:gsub('vec4%s+effect%s*%(', 'vec4 userEffect(', 1)
        source = source
            .. [[
#ifdef PIXEL
uniform float shaderAmount;
vec4 effect(vec4 color, Image image, vec2 uv, vec2 screen) {
    return mix(color * Texel(image,uv), userEffect(color,image,uv,screen), shaderAmount);
}
#endif
]]
        node._postShader = ui.resources:own(katsa.graphics.newShader(source))
        node._shaderPath = node.shaderPath
        node:onDestroy(function()
            if node._postShader then
                ui.resources:releaseOwned(node._postShader)
                node._postShader = nil
            end
        end)
    end
    local s = node._postShader
    if s:hasUniform('shaderAmount') then
        s:send('shaderAmount', 1 - node.shaderTransparency)
    end
    if s:hasUniform('time') then
        s:send('time', ui.time)
    end
    if s:hasUniform('materialTime') then
        s:send('materialTime', ui.time)
    end
    for key, value in pairs(node.uniforms) do
        if s:hasUniform(key) then
            s:send(key, value)
        end
    end
    return s
end

function Compositor.apply(ui, node)
    if not ui._sceneColor or not active(node) then
        return
    end
    local g = katsa.graphics
    local scene = ui._sceneColor
    local w, h = scene:getDimensions()
    local x, y = g.transformPoint(node._x, node._y)
    local x2, y2 = g.transformPoint(node._x + node._width, node._y + node._height)
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
        and layerWorld.shaderLayers:affects3D(node.shaderLayer)
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
    -- Built-in region uniforms describe this actual canvas/draw, including resize and nesting.
    if effect:hasUniform('resolution') then
        effect:send('resolution', { w, h })
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
            masks[#masks + 1] = upper
        end
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
    for _, region in ipairs(regions) do
        g.setScissor()
        if cx then
            g.setScissor(cx, cy, cw, ch)
        end
        g.intersectScissor(unpack(region))
        g.draw(snapshot, node._effectQuad, x, y)
    end
    g.flushBatch()
    g.pop()
    g.setScissor()
    if cx then
        g.setScissor(cx, cy, cw, ch)
    end
end

return Compositor
