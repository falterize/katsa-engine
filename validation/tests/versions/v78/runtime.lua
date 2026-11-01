local T = {}
T.__index = T

function T.new(manager)
    return setmetatable({ manager = manager, count = 0 }, T)
end

function T:update() end

function T:check(ok, label)
    assert(ok, label)
    self.count = self.count + 1
    print('PASS v78 ' .. label)
end

function T:draw()
    if self.done then
        return
    end
    self.done = true
    katsa.window.setMode(640, 360, { vsync = 0, depth = 24, stencil = 8 })
    local s = self.manager:switch(require('source.game.runtime.game').new, 'combined')
    local r, w, c = s.renderer, s.world, s.camera
    w.environment.gizmos.enabled = false
    w.environment.shadows.enabled = true
    w.environment.shadows.distance = 30
    w.environment.shadows.sourceFadeSeconds = 0
    for _, light in ipairs(w.lights) do
        light.castShadow = false
    end
    local light = w:create(
        'PointLight3D',
        { name = 'DistanceProbe', position = { 0, 80, 100 }, range = 600, brightness = 2 }
    )
    c.position, c.rotation = { 0, 10, 0 }, { -15, 0, 0 }
    r.shadows.nextUpdate = 0
    r:draw(w, c, 1, true)
    local receivers = r.shadows.receivers
    self:check(#receivers > 0, 'Distance test has actual nearby shadow receivers')
    for _, entry in ipairs(receivers) do
        if not entry.conservative then
            for axis = 1, 3 do
                self:check(
                    entry[axis] >= c.worldPosition[axis] - 30.5
                        and entry[axis + 3] <= c.worldPosition[axis] + 30.5,
                    'Receiver bounds stay inside the conservative shadow-distance cube'
                )
            end
        end
    end
    local faces = r.shadows.updatedFaces
    self:check(faces < 6, 'Large distant floor no longer requests all six Point faces')
    local image = r.canvas:newImageData()
    w.environment.shadows.visibleFacesOnly = false
    r.shadows.nextUpdate = 0
    r:draw(w, c, 1, true)
    local full = r.canvas:newImageData()
    self:check(
        image:getString() == full:getString(),
        'Distance-selected faces match complete Point rendering'
    )
    image:release()
    full:release()
    w.environment.shadows.visibleFacesOnly = true
    w.environment.shadows.normalBias = 5
    r.shadows.nextUpdate = 0
    r:draw(w, c, 1, true)
    image = r.canvas:newImageData()
    w.environment.shadows.visibleFacesOnly = false
    r.shadows.nextUpdate = 0
    r:draw(w, c, 1, true)
    full = r.canvas:newImageData()
    self:check(
        image:getString() == full:getString(),
        'Expanded receiver coverage preserves large normal bias'
    )
    image:release()
    full:release()
    w.environment.shadows.normalBias = 0.5
    w.environment.sun.enabled = true
    light.castShadow = false
    r.shadows.nextUpdate = 0
    r:draw(w, c, 1, true)
    local farCaster = w:create(
        'Mesh3D',
        { name = 'FarInvalidationProbe', position = { 3000, 0, 0 }, size = { 10, 10, 10 } }
    )
    r.shadows.nextUpdate = -1
    r:draw(w, c, 1, true)
    self:check(
        r.shadows.updatedFaces == 0,
        'Adding a caster outside every Sun depth volume skips rebuilding'
    )
    farCaster.position[1] = 3010
    r.shadows.nextUpdate = -1
    r:draw(w, c, 1, true)
    self:check(
        r.shadows.updatedFaces == 0,
        'Moving a far caster does not invalidate nearby Sun cascades'
    )
    farCaster.position = { 20, 30, 5 }
    r.shadows.nextUpdate = -1
    r:draw(w, c, 1, true)
    self:check(
        r.shadows.updatedFaces == 3,
        'Moving the caster into the Sun volume updates immediately'
    )
    local submitted = false
    for _, batch in pairs(r.shadows.faceBatches) do
        for _, group in ipairs(batch.groups) do
            for _, member in ipairs(group.members) do
                submitted = submitted or member == farCaster
            end
        end
    end
    self:check(
        not c:visible(farCaster.worldPosition, farCaster.radius) and submitted,
        'Off-camera caster remains in the Sun depth pass'
    )
    local original = self.manager:switch(require('source.game.runtime.game').new, 'original')
    r, w, c = original.renderer, original.world, original.camera
    w.environment.gizmos.enabled = false
    -- Establish spatial UI canvases first, then prohibit all material/light paths.
    r:draw(w, c, 1, true)
    local materialResolver = require('source.engine.shaders.materialResolver')
    local surface = require('source.engine.materials.surface')
    local savedResolve, savedBind = materialResolver.resolve, surface.bind
    local oldLights, oldShadows, oldSky = r.lights.update, r.shadows.update, r.drawSky
    materialResolver.resolve = function()
        error('Wireframe resolved a material')
    end
    surface.bind = function()
        error('Wireframe bound a material')
    end
    r.lights.update = function()
        error('Wireframe selected lights')
    end
    r.shadows.update = function()
        error('Wireframe generated shadows')
    end
    r.drawSky = function()
        error('Wireframe drew the sky')
    end
    local refresh = {}
    for _, board in ipairs(w.billboards) do
        refresh[board] = board.refresh
        board.refresh = function()
            error('Wireframe refreshed a textured Billboard canvas')
        end
    end
    w.debug.wireframe = true
    local ok, message = pcall(r.draw, r, w, c, 1, true)
    materialResolver.resolve, surface.bind = savedResolve, savedBind
    r.lights.update, r.shadows.update, r.drawSky = oldLights, oldShadows, oldSky
    for board, callback in pairs(refresh) do
        board.refresh = callback
    end
    self:check(
        ok,
        'Wireframe bypasses materials, lights, sky and Billboard refresh: '
            .. (ok and 'OK' or tostring(message))
    )
    self:check(
        r.stats.lights == 0 and r.stats.shadowFaces == 0,
        'Wireframe has no light or shadow passes'
    )
    self:check(r.wireMeshes[r.quad] ~= nil, 'Spatial panels use dedicated wire geometry')
    local output = os.getenv('KATSA_PROFILE_OUTPUT')
    if output then
        local image = r.canvas:newImageData()
        local encoded = image:encode('png')
        local f = assert(io.open(output .. '/wireframe.png', 'wb'))
        f:write(encoded:getString())
        f:close()
        encoded:release()
        image:release()
    end
    local wire = require('source.engine.graphics.debug.wireframe')
    local target = katsa.graphics.newCanvas(640, 360)
    local fake = {
        geometry = r.quad,
        matrix = require('source.engine.math.math3d').compose(
            { 0, 0, 10 },
            { 0, 0, 0 },
            { 6, 4, 1 }
        ),
        _renderOpacity = 1,
        isA = function()
            return false
        end,
        doubleSided = true,
    }
    c.position, c.rotation = { 0, 0, 0 }, { 0, 0, 0 }
    c:update(640, 360)
    r.camera, r.frame = c, r.frame + 1
    katsa.graphics.push('all')
    katsa.graphics.setCanvas(target)
    katsa.graphics.clear(0, 0, 0, 1)
    katsa.graphics.setDepthMode()
    wire.draw(r, fake)
    katsa.graphics.pop()
    local pixels = target:newImageData()
    local red, green, blue = pixels:getPixel(280, 195)
    self:check(red + green + blue < 0.05, 'Wire quad triangle interiors remain empty')
    local nonzero = 0
    for y = 100, 260 do
        for x = 200, 440 do
            local rr, gg, bb = pixels:getPixel(x, y)
            if rr + gg + bb > 0.1 then
                nonzero = nonzero + 1
            end
        end
    end
    self:check(nonzero > 0 and nonzero < 10000, 'Wire quad draws edges rather than a solid panel')
    pixels:release()
    target:release()
    local geom = r.quad
    local oldMesh = wire.mesh(r, geom)
    geom.revision = (geom.revision or 0) + 1
    self:check(wire.mesh(r, geom) ~= oldMesh, 'Wire mesh refreshes when geometry revisions change')
    self:check(#self.manager.journal.entries == 0, 'No runtime journal errors')
    print('PASSED ' .. self.count .. ' focused v78 checks')
    katsa.event.quit()
end

return T
