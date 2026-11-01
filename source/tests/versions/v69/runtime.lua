local T = {}
T.__index = T

function T.new(manager)
    return setmetatable({ manager = manager, frame = 0, count = 0 }, T)
end

function T:check(ok, text)
    assert(ok, text)
    self.count = self.count + 1
    print('PASS v69 ' .. text)
end

function T:update()
    self.frame = self.frame + 1
    if self.frame == 2 then
        self:check(
            #self.manager.journal.entries == 0,
            'Material and particle scene renders without errors'
        )
        self.manager:switch(require('source.game.runtime.menu').new)
        self:check(
            #self.manager.journal.entries == 0,
            'Scene teardown releases composition buffers'
        )
        print('PASSED ' .. self.count .. ' focused v69 checks')
        love.event.quit()
        return
    end
    if self.frame ~= 1 then
        return
    end
    local scene, err = self.manager:switch(require('source.game.runtime.game').new, 'platformer')
    assert(scene, err)
    local w, g = scene.world, love.graphics
    local mesh = w:create('Mesh3D', {
        name = 'PixelBlendTest',
        color = { 1, 1, 1 },
        position = { 20, 20, 0 },
        size = { 16, 16, 16 },
    })
    local a = w:create('SurfaceAppearance3D', { color = { 1, 0, 0 }, transparency = 0.5 }, mesh)
    local b = w:create('SurfaceAppearance3D', { color = { 0, 0, 1 }, transparency = 0.5 }, mesh)

    local function pixel()
        w:updateObject(mesh)
        local data = mesh._surfaceAppearance.colorMap:newImageData()
        local r, gg, bb, aa = data:getPixel(128, 128)
        data:release()
        return r, gg, bb, aa
    end
    g.push('all')
    g.setMeshCullMode('back')
    g.setFrontFaceWinding('cw')
    local r, gg, bb, aa = pixel()
    g.pop()
    self:check(
        math.abs(r - 0.5) < 0.01 and math.abs(bb - 0.5) < 0.01 and aa > 0.99,
        'Two half-weight appearances preserve RGBA pixels'
    )
    a.transparency = 0.75
    b.transparency = 0.25
    r, gg, bb, aa = pixel()
    self:check(
        math.abs(r - 0.25) < 0.01 and math.abs(bb - 0.75) < 0.01 and aa > 0.99,
        'Intermediate material changes update visible color and alpha'
    )
    b.transparency = 1
    a.transparency = 0.5
    r, gg, bb, aa = pixel()
    self:check(
        math.abs(r - 1) < 0.01
            and math.abs(gg - 0.5) < 0.01
            and math.abs(bb - 0.5) < 0.01
            and aa > 0.99,
        'One partial appearance blends into solid mesh color'
    )
    a.transparency = 1
    w:updateObject(mesh)
    self:check(
        not mesh._surfaceAppearance
            and not next(mesh._surfaceBlendCache.canvases)
            and not mesh._surfaceBlendCache.scratch,
        'Zero contributions release material buffers'
    )
    a.colorMap = 'missing-hidden-material.png'
    b.enabled = false
    b.transparency = 0
    b.normalMap = 'missing-disabled-normal.png'
    local resources = w.resources
    local old = resources.imageVariant
    local calls = 0
    resources.imageVariant = function(owner, path, ...)
        if path == 'missing-hidden-material.png' or path == 'missing-disabled-normal.png' then
            calls = calls + 1
        end
        return old(owner, path, ...)
    end
    w:updateObject(mesh)
    resources.imageVariant = old
    self:check(calls == 0, 'Invisible and disabled appearance maps are never loaded')
    a.colorMap = ''
    a.transparency = 0.5
    b.enabled = true
    b.normalMap = ''
    b.transparency = 0.5
    r, gg, bb, aa = pixel()
    self:check(aa > 0.99, 'Blending resumes after all appearances were hidden')
    mesh.transparency = 1
    w:updateObject(mesh)
    self:check(
        not mesh._surfaceAppearance and not next(mesh._surfaceBlendCache.canvases),
        'Hidden parent mesh does not compose its materials'
    )
    mesh.transparency = 0
    r, gg, bb, aa = pixel()
    self:check(aa > 0.99, 'Material buffers rebuild after parent mesh becomes visible')
    for _, node in ipairs({ a, b }) do
        local data = love.image.newImageData(1, 1)
        data:setPixel(
            0,
            0,
            node == a and 1 or 0,
            0,
            node == b and 1 or 0,
            node == a and 0.25 or 0.75
        )
        node.colorMap = resources:own(g.newImage(data))
        data:release()
        node.color = { 1, 1, 1 }
    end
    r, gg, bb, aa = pixel()
    self:check(
        math.abs(aa - 0.5) < 0.02,
        'Fractional texture alpha is accumulated with material weights'
    )
    a.alphaMode = 'Opaque'
    b.alphaMode = 'Opaque'
    r, gg, bb, aa = pixel()
    self:check(aa > 0.99, 'Opaque alpha mode remains opaque through material blending')
    local system = w.particles
    for _, emitter in ipairs(system.emitters) do
        emitter.rate = 0
        emitter:clear()
    end
    local e = w:create('ParticleEmitter3D', {
        name = 'OffscreenTest',
        position = { 0, 0, 200000 },
        shapeSize = { 0, 0, 0 },
        startSize = { 1, 1 },
        rate = 30,
        speed = { 10, 10 },
        lifetime = { 10, 10 },
        collisionEnabled = true,
    })
    e:emit(1)
    local p = e.particles[1]
    local age, y = p.age, p.y
    system:update(1 / 60)
    self:check(
        e._simulationPaused
            and p.age == age
            and p.y == y
            and #e.particles == 1
            and system.stats.collisionQueries == 0,
        'Offscreen Pause skips simulation, births and raycasts'
    )
    scene.renderer:draw(w, scene.camera, 0)
    self:check(system.stats.drawCalls == 0, 'Offscreen particles submit no draws')
    e.offscreenBehavior = 'Simulate'
    system:update(1 / 60)
    self:check(
        p.age > age and system.stats.collisionQueries > 0,
        'Simulate opt-in preserves continuous offscreen physics'
    )
    e.offscreenBehavior = 'Pause'
    e.rate = 0
    local camera = scene.camera
    camera:update(g.getDimensions())
    local pos = camera.worldPosition
    p.x, p.y, p.z =
        pos[1] + camera.forward[1] * 40,
        pos[2] + camera.forward[2] * 40,
        pos[3] + camera.forward[3] * 40
    p.collisionX, p.collisionY, p.collisionZ = nil, nil, nil
    local before = p.age
    system:update(1 / 60)
    self:check(
        not e._simulationPaused and p.age > before,
        'Visible world-space particles keep an offscreen emitter active'
    )
    e.layers = 2
    camera.layers = 1
    before = p.age
    system:update(1 / 60)
    self:check(
        e._simulationPaused and p.age == before and system.stats.collisionQueries == 0,
        'Camera layer exclusion skips particle work'
    )
    camera.layers = -1
    e.layers = 1
    local saved = w.root.currentCamera
    w.root.currentCamera = nil
    system:update(1 / 60)
    self:check(
        e._simulationPaused and system.stats.collisionQueries == 0,
        'Camera-free world pauses visual particle effects'
    )
    w.root.currentCamera = saved
    e:clear()
    e:emit(1)
    p = e.particles[1]
    p.x, p.y, p.z = 0, 0, 200000
    e.position = {
        pos[1] + camera.forward[1] * 40,
        pos[2] + camera.forward[2] * 40,
        pos[3] + camera.forward[3] * 40,
    }
    e.rate = 30
    system:update(1 / 60)
    self:check(
        not e._simulationPaused and system.stats.collisionQueries == 0,
        'Offscreen particles cast no rays even when their emitting source is visible'
    )
    e:clear()
    e.rate = 0
    a.transparency = 0.5
    b.transparency = 0.5
end

function T:draw() end
return T
