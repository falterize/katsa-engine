local Game = require('source.game.runtime.game')
local Application = require('source.game.runtime.application')
local Limits = require('source.engine.animation.skeleton.skinLimits')
local Schema = require('source.engine.editor.inspectors.schema')
local Properties = require('source.engine.editor.inspectors.properties')

local Tests = {}

local function capture(scene, name)
    local directory = os.getenv('KATSA_TEST_OUTPUT')
    if not directory then
        return
    end
    local g = love.graphics
    local canvas = g.newCanvas(g.getWidth(), g.getHeight(), { dpiscale = 1 })
    g.push('all')
    g.setCanvas(canvas)
    g.clear(0, 0, 0, 1)
    local image = scene.renderer:draw(scene.world, scene.camera, scene.time, true)
    g.setColor(1, 1, 1, 1)
    g.draw(image)
    scene.ui.backgroundCanvas = image
    scene.ui:draw()
    g.pop()
    local pixels = canvas:newImageData()
    local encoded = pixels:encode('png')
    local file = assert(io.open(directory .. '/' .. name .. '.png', 'wb'))
    file:write(encoded:getString())
    file:close()
    encoded:release()
    pixels:release()
    canvas:release()
end

local function inspect(tester, owner, influences, cap)
    local triangles = 0
    local objects = { owner }
    for _, piece in ipairs(owner._skinLimits.pieces) do
        objects[#objects + 1] = piece
    end
    for _, piece in ipairs(objects) do
        assert(#piece.skin.palette <= cap, 'Palette exceeds effective cap')
        for _, vertex in ipairs(piece.geometry.vertices) do
            local total, count = 0, 0
            for j = 1, piece.geometry.eightWeights and 8 or 4 do
                local offset = j > 4 and 4 or 0
                local weight = vertex[12 + j + offset]
                if weight > 0 then
                    count, total = count + 1, total + weight
                    assert(piece.skin.palette[vertex[8 + j + offset] + 1], 'Missing palette joint')
                end
            end
            assert(count <= influences and math.abs(total - 1) < 1e-5, 'Invalid reduced weights')
        end
        triangles = triangles + #piece.geometry.vertices / 3
    end
    tester:check(
        triangles == #owner._skinLimits.geometry.vertices / 3,
        'Skin reduction retains every triangle, normalized weights and valid palette indices'
    )
end

function Tests.run(tester)
    for _, backend in ipairs({ 'jolt', 'oimo' }) do
        local scene =
            assert(tester.manager:switch(Game.new, 'stareShooter', { physicsBackend = backend }))
        local input, player = scene.input, scene.demo.player
        input.captureMouse = false
        for _ = 1, 6 do
            tester.manager:update(1 / 60)
        end
        scene.demo.orbit.distance = 4
        scene.demo.orbit:update()
        scene:draw()
        local owner = player.model.objects[1]
        for _, mesh in ipairs(player.model.objects) do
            if #mesh.skin.palette > #owner.skin.palette then
                owner = mesh
            end
        end
        local geometry, skin, objectCount = owner.geometry, owner.skin, #scene.world.objects
        tester:check(
            owner.MaxBoneInfluences == 8 and owner.BonePaletteLimit == 32,
            backend .. ': mesh limits preserve the full imported rig by default'
        )
        tester:check(
            Schema.descriptor(owner, 'maxBoneInfluences').integer
                and Schema.descriptor(owner, 'skinDrawCount').readOnly,
            'Workspace exposes editable integer limits and read-only batching diagnostics'
        )
        local ok =
            Properties.set(scene, owner, { key = 'maxBoneInfluences', kind = 'number' }, '1.5')
        tester:check(
            not ok and owner.MaxBoneInfluences == 8,
            'Fractional influence limits are rejected'
        )
        scene.demo.hud.visible = false
        capture(scene, backend .. '-skin-full')
        owner.MaxBoneInfluences, owner.BonePaletteLimit = 1, 8
        scene:draw()
        tester:check(
            owner.geometry ~= geometry and owner.skinDrawCount > 1,
            'Runtime limits create private geometry and additional palette draws'
        )
        inspect(tester, owner, 1, owner.effectiveBonePaletteLimit)
        tester:check(
            player.model.parts[1].geometry ~= owner.geometry,
            'Editing a model instance does not mutate the cached model asset'
        )
        local piece = owner._skinLimits.pieces[1]
        tester:check(
            piece.parent == owner and piece._surfaceAppearance == owner._surfaceAppearance,
            'Split draws preserve hierarchy and source material components'
        )
        local layers, shadowLayers = owner.layers, owner.shadowLayers
        owner.layers, owner.shadowLayers = 4, 8
        Limits.prepare(scene.world)
        tester:check(
            piece.layers == 4
                and piece.shadowLayers == 8
                and piece.layerGroup == owner.layerGroup
                and piece.shadowGroup == owner.shadowGroup,
            'Split draws preserve owner visibility and shadow layer membership'
        )
        owner.layers, owner.shadowLayers = layers, shadowLayers
        scene.world.debug.wireframe = true
        scene:draw()
        scene.world.debug.wireframe = false
        capture(scene, backend .. '-skin-one')
        local oldBatch = owner._skinLimits.batches[1].geometry
        owner.MaxBoneInfluences, owner.BonePaletteLimit = 8, 1
        Limits.prepare(scene.world)
        tester:check(
            owner.effectiveBonePaletteLimit > 1 and owner.effectiveBonePaletteLimit <= 32,
            'Indivisible triangles raise the effective palette floor without losing bone weights'
        )
        inspect(tester, owner, 8, owner.effectiveBonePaletteLimit)
        local leased = false
        for _, item in ipairs(scene.resources.owned) do
            leased = leased or item == oldBatch.mesh
        end
        tester:check(not leased, 'Replacing a skin variant releases its previous GPU geometry')
        owner.MaxBoneInfluences, owner.BonePaletteLimit = 8, 32
        scene:draw()
        tester:check(
            owner.geometry == geometry
                and owner.skin == skin
                and #scene.world.objects == objectCount
                and owner.skinDrawCount == 1,
            'Restoring defaults restores the exact source geometry and removes generated draws'
        )
        local shadows = scene.renderer.shadows
        shadows.nextUpdate = love.timer.getTime() + 10
        local generation = shadows.generation
        scene:keypressed('w')
        for _ = 1, 3 do
            tester.manager:update(1 / 60)
        end
        scene:draw()
        tester:check(
            shadows.updatedFaces > 0 and shadows.generation > generation,
            'Animated/moving casters refresh shadows before the next scheduled scan ('
                .. tostring(shadows.updatedFaces)
                .. ', generations '
                .. tostring(generation)
                .. '/'
                .. tostring(shadows.generation)
                .. ', assigned '
                .. #shadows.assignments
                .. ')'
        )
        scene:keyreleased('w')
        scene:draw()
        tester:check(
            shadows.updatedFaces == 0,
            'An unchanged animated pose reuses all shadow maps between simulation updates'
        )
        local sun = scene.world.directionalLights[1]
        sun.rotation[2] = sun.rotation[2] + 5
        scene:draw()
        tester:check(
            shadows.updatedFaces > 0,
            'Moving light projections refresh without waiting for the maintenance clock'
        )
        if backend == 'jolt' then
            owner.MaxBoneInfluences, owner.BonePaletteLimit = 1, 8
            require('source.tests.versions.v106_6.stareShooter').extendedDepth(tester, scene)
            tester:check(
                owner.skinDrawCount > 1 and scene.renderer.depthPrepassActive,
                'Reduced split skins render through an active depth prepass'
            )
            owner.MaxBoneInfluences, owner.BonePaletteLimit = 8, 32
            scene:draw()
        end
        scene.demo.hud.visible = true
        tester:check(
            not scene.navigation.visible
                and not scene.workspace.tab.visible
                and not scene.debugButton.visible,
            'Clean gameplay hides engine navigation initially'
        )
        input.menuKey = 'f8'
        scene:keypressed('tab')
        tester:check(
            input.captureWanted,
            'Menu key can be rebound without a hardcoded Tab dependency'
        )
        scene:keypressed('f8')
        tester:check(
            not input.captureWanted
                and scene.navigation.visible
                and scene.workspace.tab.visible
                and scene.debugButton.visible
                and not love.mouse.getRelativeMode(),
            'Menu key releases the cursor and reveals common engine menus'
        )
        scene:keypressed('w')
        tester.manager:update(1 / 60)
        tester:check(
            not input:playing() and player.input.jump == false,
            'Open navigation suspends gameplay input'
        )
        scene.toolsPanel.visible = true
        scene.workspace:toggle(true)
        capture(scene, backend .. '-engine-menu')
        scene:keypressed('f8')
        tester:check(
            input.captureWanted
                and not scene.toolsPanel.visible
                and not scene.workspace.opened
                and not scene.navigation.visible
                and not scene.debugButton.visible,
            'Returning to gameplay closes engine panels and restores capture intent'
        )
        local button = input.menuButton
        local x, y, w, h =
            button._x * scene.ui.scale + scene.ui.offsetX,
            button._y * scene.ui.scale + scene.ui.offsetY,
            button._width * scene.ui.scale,
            button._height * scene.ui.scale
        scene:pointerpressed('phone-menu', x + w / 2, y + h / 2)
        scene:pointerreleased('phone-menu', x + w / 2, y + h / 2)
        tester:check(
            not input.captureWanted and scene.navigation.visible,
            'Touching the screen button opens the same engine navigation'
        )
        x, y, w, h =
            button._x * scene.ui.scale + scene.ui.offsetX,
            button._y * scene.ui.scale + scene.ui.offsetY,
            button._width * scene.ui.scale,
            button._height * scene.ui.scale
        scene:pointerpressed('phone-menu', x + w / 2, y + h / 2)
        scene:pointerreleased('phone-menu', x + w / 2, y + h / 2)
        tester:check(
            input.captureWanted and not scene.navigation.visible,
            'Touching Resume game returns to gameplay'
        )
        local rootA, modelA = scene.world:loadModel('assets/models/examples/skinRibbon.glb', {
            name = 'FourWeightProbeA',
            position = { 20, 0, 0 },
        })
        local rootB, modelB = scene.world:loadModel('assets/models/examples/skinRibbon.glb', {
            name = 'FourWeightProbeB',
            position = { 24, 0, 0 },
        })
        local ribbonA, ribbonB = modelA.objects[1], modelB.objects[1]
        local shared = ribbonA.geometry
        tester:check(
            shared == ribbonB.geometry and not shared.eightWeights,
            'Four-weight model instances share their immutable source mesh'
        )
        ribbonA.MaxBoneInfluences, ribbonA.BonePaletteLimit = 1, 1
        scene:draw()
        inspect(tester, ribbonA, 1, ribbonA.effectiveBonePaletteLimit)
        tester:check(
            ribbonA.geometry ~= shared and ribbonB.geometry == shared,
            'Four-weight reduction remains private to the edited model instance'
        )
        rootA:destroy()
        rootB:destroy()
        assert(tester.manager:switch(Application.new, 'menu'))
    end
end

function Tests.new(manager)
    love.errorhandler = function(message)
        print('FAILED skin/menu ' .. tostring(message))
        os.exit(1)
    end
    return setmetatable({ manager = manager, count = 0 }, { __index = Tests })
end

function Tests:check(value, label)
    assert(value, label)
    self.count = self.count + 1
    print('PASS skin/menu', label)
end

function Tests:update() end

function Tests:draw()
    if self.done then
        return
    end
    self.done = true
    Tests.run(self)
    self:check(#self.manager.journal.entries == 0, 'No runtime journal errors')
    print('PASSED ' .. self.count .. ' skin/menu checks')
    love.event.quit()
end

return Tests
