local Resources = require('source.engine.core.resources')
local World3D = require('source.engine.world.world')
local Camera3D = require('source.engine.cameras.camera')
local Renderer = require('source.engine.graphics.pipeline.renderer')
local BillboardUI = require('source.engine.ui.spatial.billboard')
return function(test)
    local resources = Resources.new(require('source.game.data.manifest'))
    local settings = require('source.game.data.settings').create()
    settings.sky.enabled = false
    settings.fog.enabled = false
    settings.gizmos.enabled = false
    settings.ambient = { 0, 0, 0 }
    local world = World3D.new(resources, settings)
    local camera = Camera3D.new()
    local renderer = Renderer.new(resources)
    local near = world:addObject({
        name = 'Near',
        position = { 0, 0, 20 },
        size = { 10, 10, 10 },
        texture = 'white',
    })
    local light = world:addLight({
        type = 'PointLight3D',
        position = { 0, 0, 0 },
        range = 100,
        radius = 0,
        brightness = 1,
        color = { 255, 255, 255 },
    })
    local time = 0

    local function sample()
        time = time + 1
        renderer:draw(world, camera, time)
        local data = renderer.canvas:newImageData()
        local r, g, b =
            data:getPixel(math.floor(renderer.width / 2), math.floor(renderer.height / 2))
        data:release()
        return r, g, b
    end
    local mapped = sample()
    test:check(
        mapped > 0.40 and mapped < 0.44,
        'Reinhard tone mapping preserves unsaturated local illumination'
    )
    -- The remaining analytic color checks intentionally measure linear output.
    settings.toneMapping = false
    local bright = sample()
    test:check(bright > 0.6, 'Point light illuminates outward-facing front normal')
    light.type = 'SpotLight3D'
    light.radius = 50
    local spot = sample()
    test:check(spot > 0.6, 'SpotLight3D cone illuminates its forward axis')
    light.rotation[2] = 180
    local outside = sample()
    test:check(outside < 0.02, 'SpotLight3D rejects fragments outside its cone')
    light.type = 'PointLight3D'
    light.enabled = false
    local dark = sample()
    test:check(dark < 0.02, 'Disabling light removes its illumination')
    settings.ambient = { 255, 255, 255 }
    near.color = { 1, 0, 0, 1 }
    world:addObject({
        name = 'Far',
        position = { 0, 0, 40 },
        size = { 20, 20, 20 },
        texture = 'white',
        color = {
            0,
            0,
            1,
            1,
        },
    })
    local r, g, b = sample()
    test:check(r > 0.95 and b < 0.02, 'Depth buffer keeps near object over later far geometry')
    local Material = require('source.engine.graphics.material')
    near.material = Material.new(resources, { fragmentCode = 'result = vec3(0.0, 1.0, 0.0);' })
    r, g, b = sample()
    test:check(
        g > 0.95 and r < 0.02 and b < 0.02,
        'Object fragment material changes pixels while retaining depth'
    )
    near.transparency = 0.5
    r, g, b = sample()
    test:check(
        g > 0.45 and b > 0.45 and g < 0.55 and b < 0.55,
        'Custom material preserves transparent depth pass'
    )
    near.transparency = 0
    near.material = Material.new(resources, {
        vertexDeclarations = 'uniform float shift;',
        vertexCode = 'localPosition.x += shift;',
        uniforms = { shift = 2 },
    })
    r, g, b = sample()
    test:check(b > 0.95 and r < 0.02, 'Vertex material moves geometry away from the sampled pixel')
    near.material:set('shift', 0)
    r, g, b = sample()
    test:check(
        r > 0.95 and b < 0.02,
        'Changing a material uniform updates pixels without recompiling'
    )
    near.material = nil
    local board = BillboardUI.new(
        world,
        { name = 'DepthTest', position = { 0, 0, 30 }, size = { 100, 100 }, onTop = false }
    )
    board.ui:create(
        'Frame',
        { width = 240, height = 120, color = { 0, 1, 0, 1 } },
        board.ui.content
    )
    r, g, b = sample()
    test:check(r > 0.95 and g < 0.02, 'Non-OnTop billboard is rejected by depth buffer')
    board.onTop = true
    r, g, b = sample()
    test:check(g > 0.95 and r < 0.02, 'OnTop billboard overlays world geometry')
    local uiMaterial = Material.new(resources, {
        kind = 'ui',
        code = [[
        vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
            vec4 p = Texel(tex,uv)*color;
            return vec4(p.a,0.0,p.a,p.a);
        }
    ]],
    })
    board.ui.children[1].material = uiMaterial
    r, g, b = sample()
    test:check(r > 0.95 and b > 0.95 and g < 0.02, 'UI shader changes billboard canvas pixels')
    board.ui.children[1].material = nil
    local ui = require('source.engine.ui').new(32, 32, resources)
    ui:container(
        { width = 32, height = 32, color = { 0, 1, 0, 1 }, material = uiMaterial },
        ui.content
    )
    local canvas = resources:own(katsa.graphics.newCanvas(32, 32, { dpiscale = 1 }))
    katsa.graphics.push('all')
    katsa.graphics.setCanvas(canvas)
    katsa.graphics.clear()
    ui:draw()
    katsa.graphics.pop()
    local pixels = canvas:newImageData()
    local cr, cg, cb = pixels:getPixel(16, 16)
    pixels:release()
    test:check(cr > 0.95 and cb > 0.95 and cg < 0.02, 'Same UI shader works in screen interface')
    board.transparency = 0.5
    r, g, b = sample()
    test:check(
        r > 0.45 and g > 0.45 and r < 0.55 and g < 0.55,
        'BillboardUI alpha blends correctly'
    )
    board.visible = false
    settings.fog.enabled = true
    settings.fog.color = { 0, 0, 255 }
    settings.fog.mode = 'Linear'
    settings.fog.offset = 0
    settings.fog.endDistance = 15
    settings.fog.maxOpacity = 1
    r, g, b = sample()
    test:check(b > 0.95 and r < 0.02, 'Linear fog reaches configured color')
    settings.fog.enabled = false
    near.visible = false
    r, g, b = sample()
    test:check(b > 0.95 and r < 0.02, 'Direct visibility assignment updates instanced draw list')
    near.visible = true
    near.transparency = 0.5
    r, g, b = sample()
    test:check(
        r > 0.45 and b > 0.45 and r < 0.55 and b < 0.55,
        'Transparent mesh blends over opaque depth'
    )
    near.transparency = 0
    near.layers = 2
    camera.layers = 1
    r, g, b = sample()
    test:check(
        b > 0.95 and r < 0.02,
        'Camera3D visibility layer hides geometry through GPU draw selection'
    )
    world:setLayerVisible(camera, 'player', true)
    r, g, b = sample()
    test:check(r > 0.95 and b < 0.02, 'Named camera visibility layer restores geometry')
    local invalid = pcall(function()
        world:addLight({ type = 'PointLight3D', range = -1 })
    end)
    test:check(not invalid, 'Invalid light settings produce an explicit error')
    local success = pcall(function()
        require('source.engine.import.models').load('unsupported.fbx', resources)
    end)
    test:check(not success, 'Runtime FBX fails with explicit conversion requirement')
    renderer:release()
    resources:release()
end
