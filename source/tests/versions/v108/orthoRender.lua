local Application = require('source.game.runtime.application')

local Tests = {}

local function capture(scene, name)
    local g = love.graphics
    scene.camera:update(g.getDimensions())
    local canvas = g.newCanvas(g.getWidth(), g.getHeight(), { dpiscale = 1 })
    g.push('all')
    g.setCanvas(canvas)
    g.clear(0, 0, 0, 1)
    local image = scene.renderer:draw(scene.world, scene.camera, scene.time, true)
    g.setColor(1, 1, 1, 1)
    g.draw(image)
    g.pop()
    local data = canvas:newImageData()
    local directory = os.getenv('KATSA_TEST_OUTPUT')
    if directory then
        local encoded = data:encode('png')
        local file = assert(io.open(directory .. '/' .. name .. '.png', 'wb'))
        file:write(encoded:getString())
        file:close()
    end
    -- Count distinct coarse colors: a fogged or empty frame collapses to very few.
    local seen, distinct = {}, 0
    for y = 0, data:getHeight() - 1, 8 do
        for x = 0, data:getWidth() - 1, 8 do
            local r, gr, b = data:getPixel(x, y)
            local key = math.floor(r * 15) * 256 + math.floor(gr * 15) * 16 + math.floor(b * 15)
            if not seen[key] then
                seen[key], distinct = true, distinct + 1
            end
        end
    end
    return distinct, scene.renderer.stats.mainTriangles
end

function Tests.run(tester)
    local scene = Application.new(tester.manager, 'models')
    scene:load()
    for _ = 1, 10 do
        scene:update(1 / 60, 1 / 60)
    end
    local camera = scene.camera
    local perspectiveLit, perspectiveTriangles = capture(scene, 'camera-perspective')
    camera.projectionMode = 'Orthographic'
    camera.orthoSize = 70
    local orthoLit, orthoTriangles = capture(scene, 'camera-orthographic')
    tester:check(
        perspectiveLit > 40 and orthoLit > 40 and orthoTriangles > 0,
        ('Orthographic render draws varied geometry (distinct colors %d vs %d, triangles %d vs %d)'):format(
            orthoLit,
            perspectiveLit,
            orthoTriangles,
            perspectiveTriangles
        )
    )
    camera.projectionMode = 'Perspective'
    scene:release()
end

return Tests
