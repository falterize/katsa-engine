local T = {}
T.__index = T

function T.new(manager)
    return setmetatable({ manager = manager, count = 0 }, T)
end

function T:update() end

function T:check(ok, message)
    assert(ok, message)
    self.count = self.count + 1
    print('PASS v76 ' .. message)
end

function T:draw()
    if self.done then
        return
    end
    self.done = true
    love.window.setMode(640, 360, { vsync = 0, depth = 24, stencil = 8 })
    local scene = self.manager:switch(require('source.game.runtime.game').new, 'combined')
    local r, w, c = scene.renderer, scene.world, scene.camera
    local settings = w.environment.shadows
    settings.enabled, settings.visibleFacesOnly, settings.sourceFadeSeconds = true, false, 0
    w.environment.gizmos.enabled = false
    local light = w.lights[1]
    for _, l in ipairs(w.lights) do
        l.castShadow = l == light
    end
    local cube = w.byName['Cube10.2']

    local function draw()
        r.shadows.nextUpdate = -1
        r:draw(w, c, 2, true)
    end

    local function exact(message)
        local a = r.canvas:newImageData()
        r:invalidate()
        r.shadows.nextUpdate = 0
        r:draw(w, c, 2, true)
        local b = r.canvas:newImageData()
        self:check(a:getString() == b:getString(), message)
        a:release()
        b:release()
    end
    for _ = 1, 5 do
        draw()
    end
    self:check(r.stats.frameReused, 'Settled static shadows reuse the final frame')
    r.shadows.samplingDisabled = true
    draw()
    self:check(not r.stats.frameReused, 'Shadow sampling probe invalidates the cached frame')
    r.shadows.samplingDisabled = false
    draw()
    cube.rotation[2] = 37
    draw()
    self:check(
        not r.stats.frameReused and r.stats.shadowFaces > 0,
        'Caster motion refreshes shadows before allowing reuse'
    )
    for _, batch in pairs(r.shadows.faceBatches) do
        for _, group in ipairs(batch.groups) do
            if group.count > 0 then
                self:check(#group.data[1] == 16, 'Depth instances store only their transform')
            end
        end
    end
    self:check(r.shadows.batchMatrixRows <= 6, 'One cube changes at most one row per Point face')
    exact('Incremental Point buffers match a complete rebuild')
    draw()
    local scans, original = 0, r.shadows.cache.scan
    r.shadows.cache.scan = function(...)
        scans = scans + 1
        return original(...)
    end
    c.rotation[2] = c.rotation[2] + 8
    draw()
    self:check(
        not r.stats.frameReused and scans == 0,
        'Camera motion renders a new image without scanning static casters'
    )
    local position = light.position[1]
    light.position[1] = position + 5
    draw()
    self:check(
        scans == 0 and r.stats.shadowFaces > 0,
        'Light motion updates depth without rescanning unchanged caster state'
    )
    exact('Moving light buffers match a complete rebuild')
    r.shadows.cache.scan = original
    cube.shadowLayers = 0
    draw()
    exact('Shadow layer changes remove the caster immediately')
    cube.shadowLayers = 1
    draw()
    cube.visible = false
    draw()
    exact('Hiding a caster removes its shadow')
    cube.visible = true
    draw()
    local surface = cube.children[1]
    surface.alphaMode = 'Blend'
    surface.transparency = 0.5
    draw()
    exact('Opacity and material membership changes match full rebuilding')
    surface.alphaMode, surface.transparency = 'Opaque', 0
    for _, mode in ipairs({ 'Standard', 'Realistic' }) do
        settings.mode = mode
        for _, samples in ipairs({ 1, 4, 9 }) do
            settings.filterSamples = samples
            draw()
            local a = r.canvas:newImageData()
            r.forceGeneralShader = true
            draw()
            local b = r.canvas:newImageData()
            self:check(
                a:getString() == b:getString(),
                mode .. ' filter ' .. samples .. ' matches general shader'
            )
            a:release()
            b:release()
            r.forceGeneralShader = false
        end
    end
    local baseline = os.getenv('KATSA_BASELINE')
    if baseline then
        local f = assert(io.open(baseline .. '/assets/shaders/engine/shadowSampling.glsl', 'rb'))
        local oldSampling = f:read('*a')
        f:close()
        local currentSampling =
            assert(love.filesystem.read('assets/shaders/engine/shadowSampling.glsl'))
        local source =
            require('source.engine.graphics.shaderSource').read('assets/shaders/engine/world.glsl')
        local first, last = assert(source:find(currentSampling, 1, true))
        local oldShader =
            love.graphics.newShader(source:sub(1, first - 1) .. oldSampling .. source:sub(last + 1))
        local currentShader = r.shader
        for _, mode in ipairs({ 'Standard', 'Realistic' }) do
            settings.mode = mode
            for _, samples in ipairs({ 1, 4, 9 }) do
                settings.filterSamples = samples
                draw()
                local a = r.canvas:newImageData()
                r.forceGeneralShader, r.shader = true, oldShader
                draw()
                local b = r.canvas:newImageData()
                self:check(
                    a:getString() == b:getString(),
                    'Original v75 shader: ' .. mode .. ' filter ' .. samples
                )
                a:release()
                b:release()
                r.forceGeneralShader, r.shader = false, currentShader
            end
        end
        oldShader:release()
    end
    light.castShadow = false
    w.environment.sun.enabled = true
    draw()
    c.position[1] = c.position[1] + 15
    draw()
    self:check(r.stats.shadowFaces == 3, 'Camera translation rebuilds Sun cascades')
    exact('Sun tile buffers match a complete rebuild')
    local owners = r.shadows.faceOwners
    light:destroy()
    draw()
    for _, owner in pairs(owners) do
        self:check(not owner.destroyed, 'Destroyed light releases tile buffers')
    end
    self:check(#self.manager.journal.entries == 0, 'No runtime errors in dynamic shadow paths')
    print('PASSED ' .. self.count .. ' focused v76 checks')
    love.event.quit()
end

return T
