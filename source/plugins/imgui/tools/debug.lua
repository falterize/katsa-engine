-- Debug window (F4): the render, physics and diagnostics switches of the old Debug menu, one tab
-- per area. Every control reads the live setting each frame, so nothing goes stale when another
-- part of the engine changes it. The legacy overlay is source/engine/debug/menu.lua.
local Plugins = require('source.engine.plugins')
local Profiles = require('source.engine.graphics.quality.profiles')

local Debug = { id = 'debug', title = 'Debug', key = 'f4' }

local PHYSICS_2D = { 'enabled', 'shapes', 'joints', 'centers', 'velocities', 'contacts' }
local PHYSICS_3D = {
    'drawShapes',
    'drawAabbs',
    'drawBases',
    'drawContacts',
    'drawContactBases',
    'drawPairs',
    'drawJoints',
    'drawJointLimits',
    'drawBvh',
}
local BODY_FIELDS = {
    { 'density', 0, 10 },
    { 'friction', 0, 1 },
    { 'restitution', 0, 1 },
    { 'linearDamping', 0, 1 },
    { 'angularDamping', 0, 1 },
    { 'gravityScale', 0, 3 },
}
local POSE_MODES = { 'Render', 'Solver', 'Both' }

function Debug.new()
    -- `showTab` (a tab title) switches to that tab on the next frame.
    return { selected = nil, pickText = nil, showTab = nil }
end

-- A checkbox bound to a getter and a setter; `set` gets the new state.
local function toggle(ig, label, get, set)
    local changed, value = ig.checkbox(label, get() == true)
    if changed then
        set(value)
    end
end

local function slider(ig, label, value, min, max, set, format)
    local changed, new = ig.sliderFloat(label, value, min, max, format)
    if changed then
        set(new)
    end
end

local function step(physics)
    local paused = physics.paused
    physics.paused = false
    physics:update(physics.fixedDelta)
    physics.paused = paused
end

local function ui2D(scene)
    return scene.root:find('World3D/World2D') or { debug = {} }
end

local function physics2D(ig, scene)
    local physics = ui2D(scene).physics2D
    if not physics then
        ig.textWrapped('This World2D has no physics.')
        return
    end
    for _, setting in ipairs(PHYSICS_2D) do
        toggle(ig, '2D physics ' .. setting, function()
            return physics.debug[setting]
        end, function(value)
            physics.debug[setting] = value
        end)
    end
    toggle(ig, 'Pause 2D physics', function()
        return physics.paused
    end, function(value)
        physics.paused = value
    end)
    if ig.button('Single 2D physics step') then
        step(physics)
    end
end

-- The Body3D under the screen centre, for the per-body controls below.
local function pick(scene, physics, state)
    scene.camera:update(katsa.graphics.getDimensions())
    local p, f = scene.camera.worldPosition or scene.camera.position, scene.camera.forward
    local hit = physics:raycast(p, { p[1] + f[1] * 1000, p[2] + f[2] * 1000, p[3] + f[3] * 1000 })
    state.selected = hit and hit.node and hit.node.physics
    state.pickText = state.selected and ('Selected: ' .. state.selected.node.name)
        or 'No body at screen center'
end

local function selectedBody(ig, state)
    local selected = state.selected
    if not selected or selected.node.destroyed then
        state.selected = nil
        return
    end
    for _, field in ipairs(BODY_FIELDS) do
        local current = selected.settings and selected.settings[field[1]] or selected.node[field[1]] or 0
        slider(ig, 'Body3D ' .. field[1], current, field[2], field[3], function(value)
            if selected.node:isA('Body3D') then
                selected.node[field[1]] = value
            end
            selected:set({ [field[1]] = field[1] == 'density' and math.max(0.01, value) or value })
        end)
    end
    toggle(ig, 'Selected collision', function()
        return selected.canCollide ~= false
    end, function()
        selected:set({ canCollide = not selected.canCollide })
    end)
    toggle(ig, 'Selected query', function()
        return selected.canQuery ~= false
    end, function()
        selected:set({ canQuery = not selected.canQuery })
    end)
    if ig.button('Sleep / wake selected') then
        if selected.raw:isSleeping() then
            selected.raw:wakeUp()
        else
            selected.raw:sleep()
        end
    end
end

local function physics3D(ig, scene, state)
    local physics = scene.physics
    if not physics then
        ig.textWrapped('This scene has no physics world. Open Physics Lab, Collision Models or Night Player.')
        return
    end
    local debug = scene.world.environment.debug.physics
    toggle(ig, 'Physics debug', function()
        return debug.enabled
    end, function(value)
        debug.enabled = value
    end)
    local mode = 1
    for index, name in ipairs(POSE_MODES) do
        mode = name == (debug.poseMode or 'Render') and index or mode
    end
    local changed, picked = ig.combo('Debug pose', mode, POSE_MODES)
    if changed then
        debug.enabled, debug.poseMode = true, POSE_MODES[picked]
    end
    toggle(ig, 'Pause physics', function()
        return physics.paused
    end, function(value)
        physics.paused = value
    end)
    if ig.button('Single physics step') then
        step(physics)
    end
    for _, field in ipairs(PHYSICS_3D) do
        toggle(ig, field, function()
            return debug[field]
        end, function(value)
            debug.enabled, debug[field] = true, value
        end)
    end
    ig.separator()
    slider(ig, 'Gravity Y', physics.gravity[2], -400, 100, function(value)
        physics:setGravity(physics.gravity[1], value, physics.gravity[3])
    end, '%.1f')
    local world = physics.world
    local velocity, position = world:getNumVelocityIterations(), world:getNumPositionIterations()
    local _, newVelocity = ig.sliderInt('Velocity iterations', velocity, 1, 20)
    if newVelocity ~= velocity then
        world:setNumVelocityIterations(newVelocity)
    end
    local _, newPosition = ig.sliderInt('Position iterations', position, 1, 10)
    if newPosition ~= position then
        world:setNumPositionIterations(newPosition)
    end
    ig.separator()
    if ig.button('Pick body at screen center') then
        pick(scene, physics, state)
    end
    ig.sameLine()
    ig.text(state.pickText or 'Nothing picked')
    selectedBody(ig, state)
end

local function rendering(ig, scene)
    local world = scene.world
    world.debug = world.debug or { bones = false, wireframe = false }
    toggle(ig, 'Bone debug', function()
        return world.debug.bones
    end, function(value)
        world.debug.bones = value
        for _, animator in ipairs(world.animators or {}) do
            animator.debugEnabled = value
        end
    end)
    toggle(ig, 'Wireframe render', function()
        return world.debug.wireframe
    end, function(value)
        world.debug.wireframe = value
    end)
    toggle(ig, 'Free debug camera', function()
        return scene.freeDebugCamera ~= nil
    end, function()
        require('source.engine.cameras.debugCamera').toggle(scene)
    end)
    for _, section in ipairs(Plugins.debugSections(world)) do
        toggle(ig, section.title .. ' debug', function()
            return section.settings.enabled
        end, function(value)
            section.settings.enabled = value
        end)
    end
    local lighting, environment = world.lighting, world.environment
    ig.separator()
    toggle(ig, 'Light gizmos', function()
        return lighting.debug.gizmos.enabled
    end, function(value)
        lighting.debug.gizmos.enabled = value
    end)
    toggle(ig, 'Shadow view (red shadowed, green lit, blue none)', function()
        return lighting.debug.shadowView
    end, function(value)
        lighting.debug.shadowView = value
    end)
    toggle(ig, 'Normal view (world normals as colour)', function()
        return lighting.debug.normalView
    end, function(value)
        lighting.debug.normalView = value
    end)
    ig.separator()
    local index = 1
    for position, name in ipairs(Profiles.names) do
        index = name == (world.qualityProfile or scene.qualityProfileName) and position or index
    end
    local changed, picked = ig.combo('Quality profile (weak GPU: Low)', index, Profiles.names)
    if changed then
        scene.qualityProfileName = Profiles.names[picked]
        world:setQualityProfile(scene.qualityProfileName)
    end
    local render = environment.render
    local loops = { 'Direct', 'Masked' }
    local loop = render.lightLoop == 'Masked' and 2 or 1
    local loopChanged, newLoop = ig.combo('Light loop', loop, loops)
    if loopChanged then
        render.lightLoop = loops[newLoop]
    end
    toggle(ig, 'Static frame cache', function()
        return render.frameCache
    end, function(value)
        render.frameCache = value
    end)
    slider(ig, '3D density', render.renderDensity, 0.5, 3, function(value)
        render.renderDensity = math.floor(value * 4 + 0.5) / 4
    end, '%.2f')
    slider(ig, 'Active lights', lighting.lightSettings.maxActiveLights, 0, 32, function(value)
        lighting.lightSettings.maxActiveLights = math.floor(value)
    end, '%.0f')
    slider(ig, 'Mesh draw distance', scene.camera.drawDistance, 50, 3000, function(value)
        scene.camera.drawDistance = value
    end, '%.0f')
    local layers = scene.camera.layers
    local layerNames = { '1', '2', 'All' }
    local layer = layers == 1 and 1 or layers == 2 and 2 or 3
    local layerChanged, newLayer = ig.combo('Camera3D layers', layer, layerNames)
    if layerChanged then
        scene.camera.layers = ({ 1, 2, -1 })[newLayer]
    end
    ig.separator()
    local shadows = lighting.shadows
    toggle(ig, 'Shadows', function()
        return shadows.enabled
    end, function(value)
        shadows.enabled = value
    end)
    local resolutions = { 256, 512, 1024 }
    local resolution = shadows.resolution == 512 and 2 or shadows.resolution == 1024 and 3 or 1
    local resolutionChanged, newResolution = ig.combo('Shadow map size', resolution, { '256', '512', '1024' })
    if resolutionChanged then
        shadows.resolution = resolutions[newResolution]
    end
    local taps = { 1, 4, 9 }
    local filter = shadows.filterSamples == 4 and 2 or shadows.filterSamples == 9 and 3 or 1
    local filterChanged, newFilter = ig.combo('Shadow filter (taps)', filter, { '1', '4', '9' })
    if filterChanged then
        shadows.filterSamples = taps[newFilter]
    end
    slider(ig, 'Shadow strength', shadows.strength, 0, 1, function(value)
        shadows.strength = value
    end, '%.2f')
    slider(ig, 'Shadow update Hz', shadows.updateHz, 1, 60, function(value)
        shadows.updateHz = value
    end, '%.0f')
    slider(ig, 'Shadow distance', shadows.distance, 40, 600, function(value)
        shadows.distance = value
    end, '%.0f')
end

local function directions(ig, scene)
    local ui = ui2D(scene)
    ui.debug = ui.debug or {}
    for _, dimension in ipairs({ '2D', '3D' }) do
        local key = 'orientation' .. dimension
        local target = dimension == '2D' and ui.debug or scene.world.debug
        toggle(ig, dimension .. ' orientation axes', function()
            return target[key]
        end, function(value)
            target[key] = value
            if dimension == '2D' then
                scene.world.debug[key] = false
            end
        end)
    end
end

local function diagnostics(ig, scene, _, host)
    toggle(ig, 'Console (F1)', function()
        return host.open.console
    end, function()
        host:toggle('console')
    end)
    toggle(ig, 'Profiler / error journal', function()
        return host.open.profiler
    end, function()
        host:toggle('profiler')
    end)
    local manager = scene.manager
    if manager then
        toggle(ig, 'Keep running when the window is unfocused', function()
            return manager:runsInBackground()
        end, function(value)
            manager.backgroundOverride = value
            -- Audio follows the same rule the next time the focus changes.
            if not manager.focused and scene.audio then
                if value then
                    scene.audio:resume()
                else
                    scene.audio:pause()
                end
            end
        end)
    end
    if scene.statistics and ig.button('Export Stats CSV (F6, last 30 s)') then
        scene.statistics:export(30)
    end
    if ig.button('Measure shadow build / sampling costs') then
        scene.pendingShadowProbe = true
    end
end

local TABS = {
    { '2D Physics', physics2D },
    { '3D Physics', physics3D },
    { 'Rendering', rendering },
    { 'Directions', directions },
    { 'Diagnostics', diagnostics },
}

function Debug.draw(ig, scene, state, host)
    local width, height = katsa.graphics.getDimensions()
    ig.setNextWindowPos(10, 60)
    ig.setNextWindowSize(math.min(520, width - 20), math.min(600, height * 0.75))
    local visible, open = ig.begin('Debug', true)
    if visible and ig.beginTabBar('debugTabs') then
        for _, tab in ipairs(TABS) do
            if ig.beginTabItem(tab[1], state.showTab == tab[1]) then
                tab[2](ig, scene, state, host)
                ig.endTabItem()
            end
        end
        ig.endTabBar()
    end
    state.showTab = nil
    ig.finish()
    if not open then
        host:close('debug')
    end
end

return Debug
