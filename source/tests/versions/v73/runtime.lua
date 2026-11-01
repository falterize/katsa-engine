local T = {}
T.__index = T

function T.new(manager)
    love.window.setMode(640, 360, { vsync = 0, depth = 24, stencil = 8 })
    love.errorhandler = function(err)
        print('FAILED v73 ' .. tostring(err))
        return function()
            return 1
        end
    end
    return setmetatable({ manager = manager, count = 0 }, T)
end

function T:check(ok, label)
    assert(ok, label)
    self.count = self.count + 1
    print('PASS v73 ' .. label)
end

function T:update()
    if self.done then
        return
    end
    self.done = true
    local s = assert(self.manager:switch(require('source.game.runtime.game').new, 'combined'))
    local r, w, c = s.renderer, s.world, s.camera
    local clock = 0

    local function draw()
        clock = clock + 1 / 60
        r:draw(w, c, clock, true)
    end

    local function settle()
        for i = 1, 50 do
            draw()
        end
    end

    local function fresh(label)
        draw()
        self:check(not r.stats.frameReused, label)
    end
    settle()
    self:check(r.stats.frameReused, 'Idle stress scene reuses complete 3D canvas')
    self:check(
        r.stats.objects == 395 and r.lights.count == 32,
        'Reuse retains geometry and all selected lights'
    )
    local first = r.canvas:newImageData()
    r:invalidate()
    fresh('Explicit renderer invalidation redraws')
    local second = r.canvas:newImageData()
    local maximum = 0
    for y = 0, first:getHeight() - 1 do
        for x = 0, first:getWidth() - 1 do
            local a, b, c = first:getPixel(x, y)
            local d, e, f = second:getPixel(x, y)
            maximum = math.max(maximum, math.abs(a - d), math.abs(b - e), math.abs(c - f))
        end
    end
    first:release()
    second:release()
    self:check(maximum == 0, 'Reused and freshly rendered pixels are identical')
    settle()
    c.rotation[2] = c.rotation[2] + 1
    fresh('Camera rotation invalidates frame')
    settle()
    c.position[1] = c.position[1] + 1
    fresh('Camera movement invalidates frame')
    local mesh = w.objects[2]
    local surface = mesh.children[1]
    settle()
    mesh.position[1] = mesh.position[1] + 5
    fresh('In-place object position invalidates frame')
    settle()
    mesh.size[1] = mesh.size[1] + 1
    fresh('In-place mesh size invalidates frame')
    settle()
    surface.color[1] = 0.3
    fresh('In-place material color invalidates frame')
    settle()
    surface.roughness = 0.8
    fresh('Material roughness invalidates frame')
    settle()
    surface.normalMap = 'stone'
    fresh('Adding a material map invalidates frame')
    settle()
    surface.normalMap = ''
    fresh('Removing a material map invalidates frame')
    settle()
    local parent = w:create('Node3D', { position = { 3, 0, 0 } })
    mesh.parent = parent
    fresh('Reparenting invalidates frame')
    settle()
    parent.rotation[2] = 10
    fresh('Ancestor rotation invalidates descendants')
    settle()
    parent.transparency = 0.5
    fresh('Ancestor transparency invalidates descendants')
    settle()
    parent.visible = false
    fresh('Ancestor visibility invalidates descendants')
    settle()
    parent.visible = true
    fresh('Showing a parent invalidates frame')
    settle()
    w.lights[1].position[1] = w.lights[1].position[1] + 3
    fresh('Moving a light invalidates frame')
    settle()
    w.lights[1].color[1] = 123
    fresh('In-place light color invalidates frame')
    settle()
    w.environment.fog.density = 0.002
    fresh('Fog settings invalidate frame')
    settle()
    w.environment.sky.yaw = 12
    fresh('Sky settings invalidate frame')
    settle()
    w.environment.ambient[1] = 85
    fresh('Ambient settings invalidate frame')
    settle()
    w:invalidateRender()
    fresh('World invalidation refreshes native resource edits')
    settle()
    r.targetWidth = 600
    r.targetHeight = 320
    fresh('Render target resize invalidates frame')
    settle()
    w.environment.render.lightLoop = 'Masked'
    fresh('Light loop switches invalidate frame')
    settle()
    w.environment.render.frameCache = false
    draw()
    draw()
    self:check(not r.stats.frameReused, 'Disabling cache retains continuous rendering')
    w.environment.render.frameCache = true
    settle()
    local added = w:create('Mesh3D', { name = 'AddedCacheTestMesh', position = { 0, 20, 50 } })
    fresh('Adding a mesh invalidates frame')
    settle()
    added:destroy()
    fresh('Removing a mesh invalidates frame')
    settle()
    s.objectEffect.enabled = true
    draw()
    draw()
    self:check(not r.stats.frameReused, 'Animated custom shaders never freeze')
    s.objectEffect.enabled = false
    settle()
    w.lights[1].rainbow = true
    draw()
    draw()
    self:check(not r.stats.frameReused, 'Rainbow light time animation never freezes')
    w.lights[1].rainbow = false
    settle()
    local e = w:create('ParticleEmitter3D', { rate = 1, maxParticles = 4 })
    draw()
    draw()
    self:check(not r.stats.frameReused, 'Particle births never freeze')
    e:destroy()
    settle()
    self.manager:focus(true)
    fresh('Focus restoration invalidates cached canvases')
    -- Local shadow projections/depth are independent of the main camera.
    w.environment.shadows.enabled = true
    w.environment.sun.enabled = false
    w.environment.shadows.visibleFacesOnly = false
    w.environment.shadows.softLightLimit = 1
    w.environment.shadows.updateHz = 60
    w.environment.shadows.sourceFadeSeconds = 0
    for i, l in ipairs(w.lights) do
        l.castShadow = i == 1
    end
    settle()
    self:check(
        #r.shadows.assignments == 1 and r.shadows.assignments[1].valid,
        'Local shadow reuse test has a published resident map'
    )
    self:check(r.shadows.updatedFaces == 0, 'Unchanged local shadow maps stop rebuilding')
    local scans = 0
    local old = r.shadows.cache.scan
    r.shadows.cache.scan = function(...)
        scans = scans + 1
        return old(...)
    end
    r.shadows.nextUpdate = love.timer.getTime() - 1 / 60
    c.rotation[2] = c.rotation[2] + 2
    draw()
    self:check(r.shadows.updatedFaces == 0, 'Camera rotation retains valid local depth maps')
    self:check(scans == 0, 'Camera-only movement skips complete caster scanning')
    r.shadows.nextUpdate = love.timer.getTime() - 1 / 60
    mesh.position[1] = mesh.position[1] + 10
    draw()
    self:check(scans > 0, 'Moving a caster resumes shadow dependency scanning')
    self:check(r.shadows.updatedFaces > 0, 'Moving a nearby caster rebuilds affected depth maps')
    r.shadows.cache.scan = old
    w.environment.sun.enabled = true
    w.lights[1].castShadow = false
    r.shadows.nextUpdate = 0
    draw()
    self:check(r.shadows.sunValid, 'Sun cascades are published')
    c.position[1] = c.position[1] + 100
    r.shadows.nextUpdate = love.timer.getTime() - 1 / 60
    draw()
    self:check(r.shadows.updatedSun, 'Camera translation updates dependent sun cascades')
    self:check(#self.manager.journal.entries == 0, 'Cached and live paths report no runtime errors')
    print('PASSED ' .. self.count .. ' focused v73 checks')
    love.event.quit()
end

function T:draw() end
return T
