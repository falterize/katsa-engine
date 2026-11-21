-- Per-pixel motion of the 3D render: camera motion from the depth, mesh motion from the previous
-- matrices, and zero for a still scene.
local Renderer = require('source.engine.graphics.pipeline.renderer')
local Resources = require('source.engine.core.resources')
local Velocity = require('source.engine.graphics.pipeline.velocity')
local World3D = require('source.engine.world.world')

local Module = {}

local WIDTH, HEIGHT = 160, 90

local function build()
    local resources = Resources.new(require('validation.tests.fixtures.manifest'))
    local settings = require('source.runtime.settings').create()
    settings.gizmos.enabled, settings.shadows.enabled = false, false
    local world = World3D.new(resources, settings)
    local camera = world:addCamera({ position = { 0, 0, 0 }, rotation = { 0, 0, 0 }, drawDistance = 800 })
    world.environment.sky.enabled = false
    world:create('Mesh3D', {
        name = 'Wall',
        position = { 0, 0, 20 },
        size = { 200, 100, 1 },
        color = { 0.5, 0.6, 0.7, 1 },
    })
    local renderer = Renderer.new(resources)
    renderer.targetWidth, renderer.targetHeight = WIDTH, HEIGHT
    world.environment.render.msaa, world.environment.render.renderDensity = 0, 1
    return world, camera, renderer
end

function Module.run(self)
    local world, camera, renderer = build()
    local cube = world:create('Mesh3D', {
        name = 'Cube',
        position = { 0, 0, 10 },
        size = { 2, 2, 2 },
        color = { 1, 0.2, 0.2, 1 },
    })
    local clock = 0
    -- Draws a frame and reads the velocity back: { rg, b } at the pixel (x, y).
    local function frame()
        clock = clock + 1
        world:updateNodes(1 / 60)
        camera:update(WIDTH, HEIGHT)
        renderer:draw(world, camera, clock, true)
        local data = Velocity.get(renderer):newImageData()
        return function(x, y)
            local r, g, b = data:getPixel(x, y)
            return r, g, b
        end
    end
    frame()
    local at = frame()
    local vx, vy, mask = at(20, 20)
    self:check(
        math.abs(vx) < 1e-4 and math.abs(vy) < 1e-4 and mask == 0,
        'A still camera and a still scene have zero velocity'
    )

    -- The camera moves right: the wall slides left by focal * 0.5 / 20 pixels.
    local wall = { 0, 10, 20 }
    local x1, y1 = camera:project(wall)
    camera.position = { 0.5, 0, 0 }
    at = frame()
    local x2, y2 = camera:project(wall)
    vx, vy, mask = at(20, 20)
    self:check(
        math.abs(vx - (x2 - x1) / WIDTH) < 0.0008 and math.abs(vy - (y2 - y1) / HEIGHT) < 0.0008
            and vx < -0.005 and mask == 0,
        ('Camera motion gives the velocity of the surfaces behind it (%.4f, expected %.4f)'):format(
            vx,
            (x2 - x1) / WIDTH
        )
    )

    -- The camera is still again and the cube moves right by 0.5: 0.5 * focal / 9 pixels (front face).
    frame()
    local cx1 = camera:project({ 0, 0, 9 }) -- the front face of the cube
    cube.position = { 0.5, 0, 10 }
    at = frame()
    local cx2, cy2 = camera:project({ 0.5, 0, 9 })
    local px, py = math.floor(cx2), math.floor(cy2)
    vx, vy, mask = at(px, py)
    self:check(
        mask == 1 and math.abs(vx - (cx2 - cx1) / WIDTH) < 0.0008 and math.abs(vy) < 0.0008,
        ('A moving mesh writes its own velocity (%.4f, expected %.4f, mask %d)'):format(
            vx,
            (cx2 - cx1) / WIDTH,
            mask
        )
    )
    local wx, _, wm = at(5, 5)
    self:check(math.abs(wx) < 1e-4 and wm == 0, 'Pixels outside the moving mesh keep the camera velocity')

    -- Frames the cache replays have no motion.
    cube.position = { 0.5, 0, 10 }
    frame()
    at = frame()
    vx, _, mask = at(px, py)
    self:check(math.abs(vx) < 1e-4 and mask == 0, 'A mesh that stopped has zero velocity again')
end

return Module
