local T = {}
T.__index = T

function T.new(manager)
    io.stdout:setvbuf('no')
    katsa.errorhandler = function(message)
        print('FAILED v80 ' .. tostring(message))
        return function()
            katsa.event.quit(1)
        end
    end
    return setmetatable({ manager = manager, count = 0 }, T)
end

function T:update() end

function T:check(ok, label)
    assert(ok, label)
    self.count = self.count + 1
    print('PASS v80 ' .. label)
end

function T:draw()
    if self.done then
        return
    end
    self.done = true
    katsa.window.setMode(640, 360, { vsync = 0, depth = 24, stencil = 8 })
    print('RENDERER', katsa.graphics.getRendererInfo())
    local scene = self.manager:switch(require('source.game.runtime.game').new, 'occlusion')
    local renderer, world, camera = scene.renderer, scene.world, scene.camera
    world.environment.render.frameCache = false
    world.environment.shadows.sourceFadeSeconds = 0
    world.environment.shadows.maxUpdateFaces = 195

    local function draw(enabled)
        world.environment.render.occlusionCulling = enabled
        renderer:draw(world, camera, 1, true)
        local image = renderer.canvas:newImageData()
        image:encode('png', enabled and 'occlusion-on.png' or 'occlusion-off.png')
        local data = image:getString()
        image:release()
        return data
    end

    local function compare(label)
        renderer.shadows.nextUpdate = 0
        local reference = draw(false)
        local before = renderer.stats.mainTriangles
        renderer.shadows.nextUpdate = 0
        local result = draw(true)
        self:check(reference == result, label .. ' exact image')
        self:check(
            renderer.stats.mainTriangles <= before,
            label .. ' submitted triangles do not increase'
        )
    end
    compare('Static opaque wall')
    print(
        'OCCLUSION',
        renderer.stats.occlusionCulled,
        renderer.stats.occlusionSavedTriangles,
        renderer.stats.occlusionOccluders,
        renderer.stats.occlusionMilliseconds
    )
    self:check(
        renderer.stats.occlusionCulled > 100,
        'Opaque wall eliminates hidden cube submissions'
    )
    self:check(
        renderer.stats.occlusionSavedTriangles >= renderer.stats.occlusionCulled * 12,
        'Triangle savings count actual cube primitives'
    )
    local target = world.byName['HiddenCube8.1']
    local retained = false
    for _, object in ipairs(renderer.visible) do
        retained = retained or object == target
    end
    self:check(retained, 'Occluded meshes remain in shadow receiver and light selection lists')
    local shadowSubmitted = false
    for _, batch in pairs(renderer.shadows.faceBatches) do
        for _, group in ipairs(batch.groups) do
            for _, object in ipairs(group.members) do
                shadowSubmitted = shadowSubmitted or object == target
            end
        end
    end
    self:check(shadowSubmitted, 'Occluded cube still casts Sun shadows')
    for i = 1, 5 do
        camera.position[1] = (i - 3) * 90
        camera.rotation[2] = (i - 3) * -10
        compare('Moving camera pose ' .. i)
    end
    camera.position, camera.rotation = { 0, 25, -90 }, { 0, 0, 0 }
    for i = 1, 5 do
        scene.demo.wall.position[1] = (i - 3) * 80
        scene.demo.wall.rotation[2] = (i - 3) * 12
        target.position[3] = i % 2 == 0 and -50 or 80
        compare('Moving wall and object pose ' .. i)
    end
    scene.demo.wall.position, scene.demo.wall.rotation = { 0, 28, 10 }, { 0, 0, 0 }
    target.position[3] = 80
    scene.demo.wall.transparency = 0.5
    compare('Transparent wall')
    local wallOccluder = false
    for _, polygon in ipairs(renderer.occlusionState.polygons or {}) do
        wallOccluder = wallOccluder or polygon.object == scene.demo.wall
    end
    self:check(not wallOccluder, 'Transparent wall is never an occluder')
    scene.demo.wall.transparency = 0
    scene.demo.wall.alphaCutoff = 1
    compare('Discarded wall')
    scene.demo.wall.alphaCutoff = 0
    camera.position[3] = 10
    compare('Near-plane crossing wall')
    camera.position[3] = -90
    world.debug.wireframe = true
    compare('Wireframe bypasses occlusion')
    self:check(
        renderer.stats.occlusionCulled == 0 and renderer.stats.occlusionMilliseconds == 0,
        'Wireframe performs no occlusion preparation'
    )
    world.debug.wireframe = false
    scene.demo.wall.visible = false
    local meshHelper = require('source.engine.composition.mesh')
    local left = meshHelper.create(world, {
        name = 'DoorwayLeft',
        position = { -85, 28, 10 },
        size = { 100, 100, 6 },
        surfaceAppearance = { alphaMode = 'Opaque', colorMap = 'stone' },
    })
    local right = meshHelper.create(world, {
        name = 'DoorwayRight',
        position = { 85, 28, 10 },
        size = { 100, 100, 6 },
        surfaceAppearance = { alphaMode = 'Opaque', colorMap = 'stone' },
    })
    compare('Doorway leaves an actual visible opening')
    retained = false
    for _, object in ipairs(renderer.opaque) do
        retained = retained or object == target
    end
    self:check(retained, 'Object behind the doorway gap remains in the main draw list')
    left:destroy()
    right:destroy()
    scene.demo.wall.visible = true
    world.environment.render.frameCache = true
    draw(true)
    draw(true)
    self:check(
        renderer.stats.frameReused
            and renderer.stats.mainTriangles == 0
            and renderer.stats.shadowTriangles == 0,
        'Cached frame submits no 3D or shadow triangles'
    )
    self:check(
        renderer.stats.occlusionSavedTriangles > 0,
        'Cached frame retains scene triangle comparison'
    )
    local settings = world.environment.shadows
    local triangles = require('source.engine.graphics.debug.triangles')
    local mesh = katsa.graphics.newMesh({ { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } }, 'triangles')
    mesh:setVertexMap(1, 2, 3, 1, 3, 4)
    triangles.begin()
    self:check(triangles.mesh(mesh) == 2, 'Indexed mesh triangle count')
    mesh:setDrawRange(4, 3)
    triangles.begin()
    self:check(triangles.mesh(mesh) == 1, 'Draw-range triangle count')
    mesh:release()
    local projection = require('source.engine.graphics.occlusion.projection')
    local polygon =
        { { 0, 0, 5 }, { 100, 0, 5 }, { 100, 100, 5 }, { 0, 100, 5 }, sign = 1, depth = 5 }
    self:check(
        projection.covered({ 20, 20, 80, 80, 10 }, polygon),
        'Full convex coverage hides a strictly deeper target'
    )
    self:check(
        not projection.covered({ 0, 20, 80, 80, 10 }, polygon),
        'Coverage edges retain a safety margin'
    )
    self:check(
        not projection.covered({ 20, 20, 80, 80, 4 }, polygon),
        'A target in front remains visible'
    )
    local triangle = { { 0, 0, 5 }, { 100, 0, 5 }, { 0, 100, 5 }, sign = 1, depth = 5 }
    self:check(
        not projection.covered({ 40, 40, 80, 80, 10 }, triangle),
        'AABB coverage cannot fill a triangle hole'
    )
    world.environment.render.frameCache = false
    self:check(
        settings.sunCasterDistance == nil and settings.sunCasterRadius == nil,
        'Sun caster fields removed from lighting defaults'
    )
    local geometryHelper = require('source.engine.graphics.geometry.primitives')
    local vertices = {}
    for x = 0, 15 do
        for y = 0, 3 do
            local x1, x2, y1, y2 = -160 + x * 20, -140 + x * 20, y * 12, (y + 1) * 12
            for _, p in ipairs({
                { x1, y1 },
                { x2, y1 },
                { x1, y2 },
                { x1, y2 },
                { x2, y1 },
                {
                    x2,
                    y2,
                },
            }) do
                vertices[#vertices + 1] = { p[1], p[2], 0, 0, 0, 0, 0, -1 }
            end
        end
    end
    local geometry = geometryHelper.mesh(vertices)
    scene.resources:own(geometry.mesh)
    local panel = world:create('Mesh3D', {
        name = 'PartialTrianglePanel',
        geometry = geometry,
        position = { 0, 0, 80 },
        size = { 1, 1, 1 },
        doubleSided = true,
        unlit = true,
    })
    scene.demo.wall.size = { 80, 100, 6 }
    scene.demo.wall.position = { 0, 28, 10 }
    camera.position, camera.rotation = { 0, 25, -90 }, { 0, 0, 0 }
    compare('Partially covered mesh')
    self:check(
        renderer.occlusionMeshes[panel] ~= nil,
        'Partial mesh uses a per-camera visible index mask'
    )
    self:check(
        renderer.stats.occlusionPartialObjects > 0 and renderer.stats.occlusionPartialTriangles > 0,
        'Hidden triangles removed even when their model remains visible'
    )
    local masked = renderer.occlusionMeshes[panel]
    print('PARTIAL_PANEL', triangles.mesh(geometry.mesh), triangles.mesh(masked))
    self:check(
        triangles.mesh(masked) > 0 and triangles.mesh(masked) < triangles.mesh(geometry.mesh),
        'Partial mask retains visible triangles'
    )
    self:check(
        geometry.mesh:getVertexMap() == nil and geometry.mesh:getDrawRange() == nil,
        'Original vertex map and draw range stay unchanged'
    )
    for i = 1, 4 do
        panel.rotation[2] = (i - 2) * 7
        scene.demo.wall.position[1] = (i - 2) * 20
        compare('Dynamic triangle mask ' .. i)
    end
    panel.rotation[2], scene.demo.wall.position[1] = 0, 0
    panel.transparency = 0.5
    compare('Transparent partially covered target')
    self:check(
        renderer.occlusionMeshes[panel] ~= nil,
        'Transparent target uses a masked individual draw'
    )
    panel.transparency = 0
    local secondPanel = world:create('Mesh3D', {
        name = 'SecondPartialPanel',
        geometry = geometry,
        position = { 100, 5, 90 },
        size = { 1, 1, 1 },
        doubleSided = true,
        unlit = true,
    })
    compare('Shared geometry with different instance masks')
    self:check(
        renderer.occlusionMeshes[panel] ~= renderer.occlusionMeshes[secondPanel],
        'Instances sharing source geometry have independent index masks'
    )
    secondPanel:destroy()
    draw(true)
    self:check(
        not renderer.occlusionState.records[secondPanel],
        'Destroyed partial mesh releases its camera mask'
    )
    renderer.shadows.nextUpdate = 0
    draw(false)
    local shadowTriangles = renderer.stats.shadowTriangles
    renderer.shadows.nextUpdate = 0
    draw(true)
    self:check(
        renderer.stats.shadowTriangles == shadowTriangles,
        'Triangle masks do not reduce shadow geometry'
    )
    scene.demo.wall.visible = false
    local exposed = draw(true)
    self:check(
        renderer.occlusionMeshes[panel] == nil,
        'Removed wall restores all panel triangles immediately'
    )
    self:check(exposed == draw(false), 'Exposed panel matches culling OFF')
    scene.demo.wall.visible = true
    local map = {}
    for i = 1, #vertices do
        map[i] = i
    end
    geometry.mesh:setVertexMap(map)
    geometry.mesh:setDrawRange(7, #map - 6)
    geometry.revision = 1
    compare('Indexed partial mesh with draw range')
    local first, length = geometry.mesh:getDrawRange()
    self:check(
        first == 7 and length == #map - 6 and #geometry.mesh:getVertexMap() == #map,
        'Indexed source state preserved after partial draw'
    )
    geometry.mesh:setDrawRange()
    geometry.mesh:setVertexMap()
    geometry.revision = 2
    local wire = require('source.engine.graphics.debug.wireframe')
    local targetCanvas = katsa.graphics.newCanvas(640, 360)
    local fake = {
        geometry = renderer.quad,
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
    camera.position, camera.rotation = { 0, 0, 0 }, { 0, 0, 0 }
    camera:update(640, 360)
    renderer.camera = camera
    for _, density in ipairs({ 1, 2 }) do
        renderer.frame = renderer.frame + 1
        renderer.density = density
        katsa.graphics.push('all')
        katsa.graphics.setCanvas(targetCanvas)
        katsa.graphics.clear(0, 0, 0, 1)
        katsa.graphics.setDepthMode()
        wire.draw(renderer, fake)
        katsa.graphics.pop()
        local pixels = targetCanvas:newImageData()
        local r, g, b = pixels:getPixel(280, 195)
        self:check(
            r + g + b < 0.05,
            'Explicit wire edges leave quad interior empty at density ' .. density
        )
        local lit = 0
        for y = 100, 260 do
            for x = 200, 440 do
                local rr, gg, bb = pixels:getPixel(x, y)
                if rr + gg + bb > 0.1 then
                    lit = lit + 1
                end
            end
        end
        self:check(lit > 0 and lit < 3000, 'Wire draws thin edge coverage at density ' .. density)
        if density == 1 then
            pixels:encode('png', 'wireframe-v80.png')
        end
        pixels:release()
    end
    renderer.density = 1
    targetCanvas:release()
    -- Exercise the complete renderer path, including its initial shader binding.
    local visibility = {}
    for _, object in ipairs(world.objects) do
        visibility[object] = object.visible
        object.visible = object == panel
    end
    panel.geometry, panel.position, panel.rotation, panel.size =
        renderer.quad, { 0, 0, 10 }, { 0, 0, 0 }, { 6, 4, 1 }
    world.debug.wireframe = true
    draw(true)
    local sceneWire = renderer.canvas:newImageData()
    local rr, gg, bb = sceneWire:getPixel(280, 195)
    self:check(rr + gg + bb < 0.25, 'Full renderer wireframe leaves triangle interiors empty')
    local lit = 0
    for y = 100, 260 do
        for x = 200, 440 do
            local r, g, b = sceneWire:getPixel(x, y)
            if r + g + b > 0.5 then
                lit = lit + 1
            end
        end
    end
    self:check(lit > 0 and lit < 3000, 'Full renderer wireframe actually draws thin edges')
    sceneWire:encode('png', 'wireframe-scene-v80.png')
    sceneWire:release()
    world.debug.wireframe = false
    panel.geometry, panel.position, panel.size = geometry, { 0, 0, 80 }, { 1, 1, 1 }
    for _, object in ipairs(world.objects) do
        object.visible = visibility[object]
    end
    local skinnedVertices = {}
    for i, v in ipairs(renderer.quad.vertices) do
        local row = { unpack(v) }
        for j = 1, 4 do
            row[#row + 1] = 0
        end
        for j = 1, 4 do
            row[#row + 1] = j == 1 and 1 or 0
        end
        skinnedVertices[i] = row
    end
    local skinnedGeometry = geometryHelper.mesh(skinnedVertices, true)
    local skinCanvas = katsa.graphics.newCanvas(640, 360)
    fake.geometry = skinnedGeometry
    fake.skin = { matrices = { require('source.engine.math.math3d').identity() } }
    renderer.frame = renderer.frame + 1
    katsa.graphics.push('all')
    katsa.graphics.setCanvas(skinCanvas)
    katsa.graphics.clear(0, 0, 0, 1)
    katsa.graphics.setDepthMode()
    wire.draw(renderer, fake)
    katsa.graphics.pop()
    local skinImage = skinCanvas:newImageData()
    rr, gg, bb = skinImage:getPixel(280, 195)
    self:check(rr + gg + bb < 0.05, 'Skinned wire triangle interior remains empty')
    lit = 0
    for y = 100, 260 do
        for x = 200, 440 do
            local r, g, b = skinImage:getPixel(x, y)
            if r + g + b > 0.1 then
                lit = lit + 1
            end
        end
    end
    self:check(lit > 0 and lit < 3000, 'Skinning transforms both wire edge endpoints')
    skinImage:release()
    skinCanvas:release()
    skinnedGeometry.mesh:release()
    local crossingGeometry = geometryHelper.mesh({
        { -2, -1, -1, 0, 0, 0, 0, -1 },
        { 2, -1, 10, 1, 0, 0, 0, -1 },
        { 0, 2, 10, 0, 1, 0, 0, -1 },
    })
    fake.geometry, fake.skin, fake.matrix =
        crossingGeometry, nil, require('source.engine.math.math3d').identity()
    local crossingCanvas = katsa.graphics.newCanvas(640, 360)
    renderer.frame = renderer.frame + 1
    katsa.graphics.push('all')
    katsa.graphics.setCanvas(crossingCanvas)
    katsa.graphics.clear(0, 0, 0, 1)
    katsa.graphics.setDepthMode()
    wire.draw(renderer, fake)
    katsa.graphics.pop()
    local crossingImage = crossingCanvas:newImageData()
    lit = 0
    for y = 0, 359 do
        for x = 0, 639 do
            local r, g, b = crossingImage:getPixel(x, y)
            if r + g + b > 0.1 then
                lit = lit + 1
            end
        end
    end
    self:check(
        lit > 0 and lit < 6000,
        'Near-plane-crossing wire remains thin instead of flooding the frame'
    )
    crossingImage:release()
    crossingCanvas:release()
    crossingGeometry.mesh:release()
    local shaderText = katsa.filesystem.read('assets/shaders/engine/wireframe.glsl')
    local valid, errors = katsa.graphics.validateShader(true, shaderText)
    self:check(valid, 'Wire shader validates for OpenGL ES: ' .. tostring(errors))
    self:check(
        not shaderText:find('fwidth') and not shaderText:find('discard'),
        'Wire shader does not rasterize source triangle interiors and discard them'
    )
    local renderer2 = require('source.engine.graphics.pipeline.renderer').new(scene.resources)
    renderer2.targetWidth, renderer2.targetHeight = 320, 180
    world.environment.render.occlusionCulling = true
    renderer2:draw(world, camera, 1, true)
    self:check(
        renderer2.occlusionState ~= renderer.occlusionState,
        'Each Viewport renderer owns independent current-camera occlusion data'
    )
    renderer2:release()
    compare('Primary camera after a separate Viewport draw')
    local properties = require('source.engine.editor.inspectors.properties')
    local fields = {}
    for _, field in ipairs(properties.list(world.environment.render)) do
        fields[field.key] = field
    end
    self:check(
        fields.occlusionCulling and fields.occlusionCulling.kind == 'boolean',
        'Lighting Render exposes the occlusion toggle in Workspace'
    )
    self:check(
        fields.occlusionMaxOccluders and fields.occlusionTriangleBudget and fields.occlusionMinArea,
        'Lighting Render exposes all coverage budgets'
    )
    fields = {}
    for _, field in ipairs(properties.list(settings)) do
        fields[field.key] = field
    end
    self:check(
        not fields.sunCasterDistance and not fields.sunCasterRadius,
        'Removed Sun caster controls stay absent from Workspace'
    )
    self:check(#self.manager.journal.entries == 0, 'No runtime journal errors')
    print('PASSED ' .. self.count .. ' focused v80 checks')
    katsa.event.quit()
end

return T
