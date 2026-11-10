local T = {}
T.__index = T

function T.new(manager)
    return setmetatable({ manager = manager, count = 0 }, T)
end

function T:check(ok, message)
    assert(ok, message)
    self.count = self.count + 1
    print('PASS v74 ' .. message)
end

function T:update() end

function T:draw()
    if self.done then
        return
    end
    self.done = true
    local menu = self.manager:switch(require('source.game.runtime.menu').new)
    for _, size in ipairs({ { 896, 414 }, { 414, 896 }, { 640, 360 } }) do
        katsa.window.setMode(size[1], size[2], { vsync = 0, stencil = 8, depth = 24 })
        menu:resize(unpack(size))
        local chooser = menu.categoryChooser
        chooser.visible = true
        menu.ui:scrollBy(chooser, 10000)
        menu.ui:layout()
        local last = chooser.children[#chooser.children]
        local x, y = last._x + last._width / 2, last._y + last._height / 2
        local ui = menu.ui
        self:check(
            y <= ui.height and chooser._y + chooser._height <= ui.height,
            'Category viewport and last row fit ' .. size[1] .. 'x' .. size[2]
        )
        self:check(
            ui:hit(x * ui.scale + ui.offsetX, y * ui.scale + ui.offsetY) == last,
            'Last category remains tappable after rotation'
        )
        last:press()
        self:check(menu.category == 'Legacy', 'Last category selects the matching scene')
    end
    katsa.window.setMode(640, 360, { vsync = 0, depth = 24, stencil = 8 })
    local s = self.manager:switch(require('source.game.runtime.game').new, 'combined')
    local r, w, c = s.renderer, s.world, s.camera
    w.environment.shadows.enabled = false
    w.environment.gizmos.enabled = false
    local time = 0

    local function draw()
        time = time + 1 / 60
        r:draw(w, c, time, true)
    end
    for i = 1, 30 do
        draw()
    end
    self:check(r.stats.frameReused, 'Static scene still reuses its complete canvas')
    c.rotation[2] = 1
    draw()
    self:check(
        not r.stats.frameReused and r.stats.updatedMeshes == 0,
        'Moving camera redraws without preparing unchanged meshes'
    )
    local cube = w.byName['Cube10.2']
    cube.rotation[2] = 30
    draw()
    self:check(r.stats.updatedMeshes == 1, 'One edited cube prepares exactly one mesh')
    local image = r.canvas:newImageData()
    r:invalidate()
    draw()
    local fresh = r.canvas:newImageData()
    self:check(
        image:getString() == fresh:getString(),
        'Incremental and full preparation match every pixel'
    )
    image:release()
    fresh:release()
    for i = 1, 20 do
        draw()
    end
    s.stressMotion.cubeButton:press()
    local y = cube.position[2]
    s.stressMotion:update(0.1)
    draw()
    self:check(
        cube.position[2] ~= y and not r.stats.frameReused and r.stats.updatedMeshes == 1,
        'Cube toggle animates and invalidates only its mesh'
    )
    s.stressMotion.cubeButton:press()
    s.stressMotion.lightButton:press()
    local x = w.lights[1].position[1]
    s.stressMotion:update(0.1)
    draw()
    self:check(
        w.lights[1].position[1] ~= x and not r.stats.frameReused and r.stats.updatedMeshes == 0,
        'Light toggle animates without rebuilding static meshes'
    )
    s.stressMotion.lightButton:press()
    for i = 1, 40 do
        draw()
    end
    self:check(
        r.stats.frameReused and #w.objects == 401 and #w.lights == 64,
        'Stopping motion returns to reuse and preserves counts'
    )
    local surface = cube.children[1]
    surface.color[1] = 0.25
    draw()
    self:check(r.stats.updatedMeshes == 1, 'In-place material edits refresh their mesh')
    s.objectEffect.enabled = true
    draw()
    self:check(
        cube._preparedMesh and not r.stats.frameReused,
        'Custom shader keeps the full rendering path'
    )
    s.objectEffect.enabled = false
    draw()
    self:check(r.stats.updatedMeshes == 401, 'Leaving a dynamic path refreshes mesh snapshots')
    local off = w:create(
        'Mesh3D',
        { name = 'DeferredOffscreen', position = { 10000, 0, 0 }, size = { 10, 10, 10 } }
    )
    w:create('SurfaceAppearance3D', { colorMap = 'stone' }, off)
    draw()
    self:check(
        off._appearancePending and not off._surfaceAppearance,
        'Offscreen material work waits until visible'
    )
    off.position = { 0, 20, 0 }
    draw()
    self:check(
        not off._appearancePending and off._surfaceAppearance,
        'Returning mesh resolves its appearance immediately'
    )
    local target = s.ui:scroll({ position = { 0, 0, 0, 0 }, size = { 0, 30, 0, 30 } }, s.ui.content)
    local nested = s.ui:scroll({ position = { 0, 0, 0, 100 }, size = { 0, 30, 0, 30 } }, target)
    local drawn = 0
    nested.drawSelf = function()
        drawn = drawn + 1
    end
    s.ui:draw()
    self:check(drawn == 0, 'Empty clipped UI subtrees issue no draw work')
    local projections = c._cameraProjectionState
    c:update(640, 360)
    self:check(c._cameraProjectionState == projections, 'Unchanged camera reuses projection state')
    local old = c.projection[1]
    c.focalLength = c.focalLength + 1
    c:update(640, 360)
    self:check(c.projection[1] ~= old, 'Projection edits update immediately')
    print('PASSED ' .. self.count .. ' focused v74 checks')
    katsa.event.quit()
end

return T
