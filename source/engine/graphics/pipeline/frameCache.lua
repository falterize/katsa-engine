local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs
-- Property revisions skip stable nodes; mutable geometry/matrices retain conservative checks.
local Cache = {}
local State = require('source.engine.graphics.pipeline.renderState')

local nodeKeys = State.nodeKeys
local nodeVectors = State.nodeVectors
local meshKeys = State.meshKeys
local meshVectors = State.meshVectors
local surfaceKeys = State.surfaceKeys
local surfaceVectors = State.surfaceVectors
local lightKeys = State.lightKeys
local lightVectors = State.lightVectors
local cameraKeys = State.cameraKeys
local geometryKeys = { 'mesh', 'vertices', 'revision', 'boundsRevision', 'radius' }
local listNames = { 'objects', 'lights', 'directionalLights', 'shaderNodes' }
local mapKeys =
    { 'colorMap', 'normalMap', 'roughnessMap', 'metalnessMap', 'occlusionMap', 'emissionMap' }
local environmentKeys = { 'render', 'sky', 'fog', 'shadows', 'lightSettings', 'systemLayers' }
local environmentScalars = { 'brightness', 'toneMapping', 'exposure' }
local environmentVectors = { 'ambient' }
local empty = State.empty
local scalar = State.scalar
local vector = State.vector
local Properties = require('source.engine.graphics.pipeline.propertySnapshot')

local fields = State.fields
local settings = State.settings
-- Child lists are ordinary node arrays. Stable membership needs no numeric-value
-- conversion/version machinery, including the common empty and one-child cases.
local function childrenChanged(record, children)
    local previous = record.members
    if previous and #previous == #children then
        local same = true
        for i = 1, #children do
            if previous[i] ~= children[i] then
                same = false
                break
            end
        end
        if same then
            return false
        end
    end
    return vector(record, 'members', children)
end

local function joined(a, b)
    local result, seen = {}, {}
    for _, list in ipairs({ a, b }) do
        for _, key in ipairs(list) do
            if not seen[key] then
                result[#result + 1], seen[key] = key, true
            end
        end
    end
    return result
end
local meshNodeKeys, meshNodeVectors = joined(nodeKeys, meshKeys), joined(nodeVectors, meshVectors)
local lightNodeKeys, lightNodeVectors =
    joined(nodeKeys, lightKeys), joined(nodeVectors, lightVectors)
local cameraNodeKeys = joined(nodeKeys, cameraKeys)

function Cache.inspect(renderer, world, camera, time, offscreen)
    local c = renderer._frameCache
    if not c then
        c = {
            nodes = {},
            geometry = {},
            lists = {},
            settings = {},
            options = {},
            motion = {},
            epoch = 0,
            sceneRevision = 0,
            casterRevision = 0,
        }
        renderer._frameCache = c
    end
    local started = katsa.timer.getTime()
    local timings = c.timings or {}
    c.timings = timings
    c.epoch = c.epoch + 1
    c.objectsChanged = false
    c.scalarNodesSkipped = 0
    c.scalarNodesChecked = 0
    local resetMeshes = c.meshSnapshots ~= true
    local motion = vector(c.motion, 'matrix', camera:getRenderWorldMatrix())
    local spatial = #(world.billboards or empty) > 0 or #(world.decals or empty) > 0
    local fastReason
    if #(world.animators or empty) > 0 or #(world.rigidControllers or empty) > 0 then
        fastReason = 'Animation'
    end
    if type(world.environment.sky.texture) == 'userdata' then
        fastReason = 'External sky texture'
    end
    if not fastReason or fastReason == 'Animation' or fastReason == 'Physics' then
        for _, shader in ipairs(world.shaderNodes or empty) do
            if shader.enabled ~= false and shader.shaderPath ~= '' then
                fastReason = 'Custom shader'
                break
            end
        end
    end
    if not fastReason then
        for _, body in ipairs(world.physics and world.physics.bodies or empty) do
            if not body.destroyed and body.type ~= 'Static' then
                fastReason = 'Physics'
                break
            end
        end
    end
    if not fastReason or fastReason == 'Animation' or fastReason == 'Physics' then
        for _, record in ipairs(world.nodeTree and world.nodeTree.records or empty) do
            if record.enabled and not record.node.destroyed and record.node._class.scriptUpdate then
                fastReason = 'Custom script'
                break
            end
        end
    end
    if not fastReason or fastReason == 'Animation' or fastReason == 'Physics' then
        for _, e in ipairs(world.particles and world.particles.emitters or empty) do
            if #e.particles > 0 or e.enabled ~= false and e.visible ~= false and e.rate > 0 then
                fastReason = 'Particles'
                break
            end
        end
    end
    local dynamic = fastReason == 'Animation'
        or fastReason == 'Physics'
        or fastReason == 'Particles'
    if fastReason and not dynamic then
        timings.guards = (katsa.timer.getTime() - started) * 1000
        timings.objects, timings.lights, timings.directionalLights, timings.shaderNodes, timings.other =
            0, 0, 0, 0, 0
        c.meshSnapshots = false
        c.meshesStable = false
        c.valid = false
        c.volatile = true
        c.reason = fastReason
        c.time = time
        c.sceneRevision = c.sceneRevision + 1
        c.casterRevision = c.casterRevision + 1
        return c
    end
    timings.guards = (katsa.timer.getTime() - started) * 1000
    local phase = katsa.timer.getTime()
    Properties.begin(c)
    c.meshSnapshots = true
    c.meshesStable = spatial or dynamic
    local sceneChanged = scalar(c.options, 'world', world)
    local casterChanged = sceneChanged
    local cameraChanged = scalar(c.options, 'camera', camera) or motion
    c.externalMeshDynamics = false
    local volatile, reason =
        spatial or dynamic, fastReason or (spatial and 'Spatial UI/decals' or nil)
    local function live(why)
        volatile = true
        reason = reason or why
        if why == 'External texture' then
            c.meshesStable = false
            c.externalMeshDynamics = true
        end
    end

    local function node(n, kind)
        if not n then
            return false
        end
        local r = c.nodes[n]
        if not r then
            r = {}
            c.nodes[n] = r
            r.new = true
        end
        if r.epoch == c.epoch and (not kind or r.kind == kind) then
            return r.changed
        end
        local previousChange = r.epoch == c.epoch and r.changed
        local sameKind = r.kind == kind
        r.epoch = c.epoch
        r.kind = kind
        -- Revisions cover typed components and public scalar writes. Keep mutable
        -- child lists, shared geometry and private surface flags observable.
        if
            kind == 'mesh'
            and sameKind
            and not r.new
            and not resetMeshes
            and not rawget(n, 'body')
            and not rawget(n, 'skin')
            and Properties.unchanged(r, n, c)
        then
            local gs = c.geometry[r.geometry]
            if gs and gs.epoch ~= c.epoch then
                gs.changed = fields(gs, r.geometry, geometryKeys)
                gs.epoch = c.epoch
            end
            local stable = gs and not gs.changed
            if childrenChanged(r.children, n.children) then
                stable = false
                r.childrenChanged = true
            end
            for _, child in ipairs(r.surfaces or empty) do
                local sr = c.nodes[child]
                if sr then
                    sr.epoch = c.epoch
                    if sr.externalTexture or not Properties.unchanged(sr, child, c) then
                        stable = false
                    end
                else
                    stable = false
                end
            end
            if stable then
                c.scalarNodesSkipped = c.scalarNodesSkipped + 1 + #(r.surfaces or empty)
                r.changed = previousChange or false
                return r.changed
            end
        end
        local body = rawget(n, 'body')
        if body and body.type == 'Static' then
            body:sync()
        end
        local keys, vectors = nodeKeys, nodeVectors
        if kind == 'mesh' then
            keys, vectors = meshNodeKeys, meshNodeVectors
        elseif kind == 'light' then
            keys, vectors = lightNodeKeys, lightNodeVectors
        elseif kind == 'camera' then
            keys = cameraNodeKeys
        end
        local handled, propertyChanged = Properties.fast(r, n, keys, vectors, c)
        if not handled then
            propertyChanged = Properties.fields(r, n, keys, vectors, c)
        end
        -- Solver interpolation and skin palettes can change without authored property writes.
        -- Keep their meshes/descendants live while retaining snapshots for static neighbors.
        local changed = propertyChanged
            or r.new
            or previousChange
            or (body and body.type ~= 'Static')
            or rawget(n, 'skin') ~= nil
        r.new = nil
        if body and body.type ~= 'Static' then
            live('Physics')
        end
        if kind == 'mesh' then
            if rawget(n, 'skin') then
                live('Skinning')
            end
            local geometry = r.geometry
            local gs = c.geometry[geometry]
            if not gs then
                gs = {}
                c.geometry[geometry] = gs
            end
            if gs.epoch ~= c.epoch then
                gs.changed = fields(gs, geometry, geometryKeys)
                gs.epoch = c.epoch
            end
            changed = gs.changed or changed
            r.children = r.children or {}
            changed = childrenChanged(r.children, n.children) or r.childrenChanged or changed
            r.childrenChanged = nil
            local surfaces = r.surfaces or {}
            r.surfaces = surfaces
            local surfaceCount = 0
            for _, child in ipairs(n.children) do
                if child._class._types.SurfaceAppearance3D then
                    surfaceCount = surfaceCount + 1
                    surfaces[surfaceCount] = child
                    local sr = c.nodes[child]
                    if not sr then
                        sr = {}
                        c.nodes[child] = sr
                        changed = true
                    end
                    sr.epoch = c.epoch
                    local handled, surfaceChanged =
                        Properties.fast(sr, child, surfaceKeys, surfaceVectors, c)
                    if not handled then
                        surfaceChanged =
                            Properties.fields(sr, child, surfaceKeys, surfaceVectors, c)
                    end
                    changed = surfaceChanged or changed
                    if surfaceChanged then
                        sr.externalTexture = false
                        for _, key in ipairs(mapKeys) do
                            if type(child[key]) == 'userdata' then
                                sr.externalTexture = true
                                break
                            end
                        end
                    end
                    if sr.externalTexture then
                        live('External texture')
                    end
                end
            end
            for i = #surfaces, surfaceCount + 1, -1 do
                surfaces[i] = nil
            end
        elseif kind == 'light' then
            if n.enabled ~= false and n.rainbow then
                live('Animated light')
            end
        end
        r.changed = changed
        return changed
    end
    -- Cache inherited changes once per inspection, without recursive hierarchy walks.
    local ancestors = c.ancestors or {}
    c.ancestors = ancestors

    local function chain(n, kind)
        local changed = node(n, kind)
        local parent = n and rawget(n, '_parent')
        local count, inherited = 0, false
        while parent do
            local record = c.nodes[parent]
            if record and record.chainEpoch == c.epoch then
                inherited = record.chainChanged
                break
            end
            node(parent)
            count = count + 1
            ancestors[count] = parent
            parent = rawget(parent, '_parent')
        end
        for i = count, 1, -1 do
            local record = c.nodes[ancestors[i]]
            inherited = record.changed or inherited
            record.chainChanged, record.chainEpoch = inherited, c.epoch
            ancestors[i] = nil
        end
        changed = inherited or changed
        if n then
            c.nodes[n].chainChanged = changed
            c.nodes[n].chainEpoch = c.epoch
        end
        return changed
    end
    for _, name in ipairs(listNames) do
        phase = katsa.timer.getTime()
        local list = world[name] or empty
        local old = c.lists[name] or {}
        c.lists[name] = old
        local listChanged = vector(old, 'members', list)
        if name == 'objects' then
            casterChanged = listChanged or casterChanged
            c.objectsChanged = listChanged
        end
        sceneChanged = listChanged or sceneChanged
        for _, n in ipairs(list) do
            if name == 'shaderNodes' then
                local changed = node(n)
                sceneChanged = scalar(c.nodes[n], 'shaderPath', n.shaderPath)
                    or changed
                    or sceneChanged
                if n.enabled ~= false and n.shaderPath ~= '' then
                    live('Custom shader')
                end
            else
                local changed = chain(n, name == 'objects' and 'mesh' or 'light')
                if name == 'objects' then
                    casterChanged = changed or casterChanged
                end
                sceneChanged = changed or sceneChanged
            end
        end
        timings[name] = (katsa.timer.getTime() - phase) * 1000
    end
    phase = katsa.timer.getTime()
    cameraChanged = chain(camera, 'camera') or cameraChanged
    for n, r in pairs(c.nodes) do
        if r.epoch ~= c.epoch then
            c.nodes[n] = nil
            sceneChanged = true
        end
    end
    for geometry, gs in pairs(c.geometry) do
        if gs.epoch ~= c.epoch then
            c.geometry[geometry] = nil
        end
    end
    for _, name in ipairs(environmentKeys) do
        c.settings[name] = c.settings[name] or {}
        sceneChanged = settings(c.settings[name], world.environment[name]) or sceneChanged
    end
    c.settings.gizmos = c.settings.gizmos or {}
    sceneChanged = settings(c.settings.gizmos, world.environment.debug.gizmos) or sceneChanged
    sceneChanged = fields(c.options, world.environment, environmentScalars, environmentVectors)
        or sceneChanged
    local refreshMeshes = scalar(c.options, 'materialViewer', camera.layerGroup)
    refreshMeshes = scalar(c.options, 'materialCamera', camera) or refreshMeshes
    refreshMeshes = scalar(c.options, 'groupRevision', world.layerGroups.revision)
        or refreshMeshes
        or resetMeshes
    sceneChanged = refreshMeshes or sceneChanged
    sceneChanged = scalar(c.options, 'shaderRevision', world.shaderLayers.revision) or sceneChanged
    refreshMeshes = scalar(c.options, 'invalidate', renderer._renderInvalidationRevision)
        or refreshMeshes
    refreshMeshes = scalar(c.options, 'worldInvalidate', world._renderInvalidationRevision)
        or refreshMeshes
    sceneChanged = refreshMeshes or sceneChanged
    refreshMeshes = scalar(c.options, 'debugWireframe', world.debug and world.debug.wireframe)
        or refreshMeshes
    sceneChanged = refreshMeshes or sceneChanged
    sceneChanged = scalar(c.options, 'debugBones', world.debug and world.debug.bones)
        or sceneChanged
    sceneChanged = scalar(c.options, 'forceGeneral', renderer.forceGeneralShader) or sceneChanged
    sceneChanged = scalar(c.options, 'freezeShadows', renderer.freezeShadowUpdates) or sceneChanged
    sceneChanged = scalar(c.options, 'shadowSamplingDisabled', renderer.shadows.samplingDisabled)
        or sceneChanged
    sceneChanged = scalar(
        c.options,
        'maskForceAll',
        require('source.engine.graphics.pipeline.lightMasks').forceAll
    ) or sceneChanged
    cameraChanged = scalar(c.options, 'width', renderer.targetWidth or katsa.graphics.getWidth())
        or cameraChanged
    cameraChanged = scalar(c.options, 'height', renderer.targetHeight or katsa.graphics.getHeight())
        or cameraChanged
    cameraChanged = scalar(c.options, 'dpi', katsa.graphics.getDPIScale()) or cameraChanged
    cameraChanged = scalar(c.options, 'overlay', offscreen and renderer.renderOverlay or false)
        or cameraChanged
    if world.environment.debug.physics.enabled then
        live('Physics debug')
    end
    if offscreen and renderer.renderOverlay then
        live('Viewport overlay')
    end
    if time < (c.time or time) then
        sceneChanged = true
    end
    c.time = time
    if spatial and c.externalMeshDynamics then
        refreshMeshes = true
    end
    if casterChanged or refreshMeshes or dynamic then
        c.casterRevision = c.casterRevision + 1
    end
    c.refreshMeshes = refreshMeshes
    if sceneChanged or cameraChanged then
        c.valid = false
        c.selectionNeeded = (renderer.lights.selectionRevision or 0) + 1
    end
    if sceneChanged or volatile then
        c.sceneRevision = c.sceneRevision + 1
    end
    c.volatile = volatile
    c.reason = reason
        or (world.environment.shadows.enabled and 'Shadows')
        or (world.environment.debug.gizmos.enabled and 'Gizmos')
        or 'Static'
    if volatile then
        c.valid = false
    end
    timings.other = (katsa.timer.getTime() - phase) * 1000
    return c
end

function Cache.reusable(renderer, world, c)
    local lights = renderer.lights
    local selectionPending = c.selectionNeeded
        and (lights.selectionRevision or 0) < c.selectionNeeded
    -- Keep the last valid image between existing throttled light deadlines.
    -- Wake precisely when pending selection/upload work can change the pixels.
    local selectionDue = (selectionPending or lights.holdingUntil)
        and c.time >= lights.nextSelection
    local uploadDue = lights.pending and c.time >= (lights.pendingUntil or 0)
    return c.valid
        and not c.volatile
        and world.environment.render.frameCache ~= false
        and (not world.environment.shadows.enabled or require(
            'source.engine.graphics.shadows.shadowCache'
        ).reusable(renderer.shadows, renderer, c))
        and not world.environment.debug.gizmos.enabled
        and not (world.debug and world.debug.bones)
        and not selectionDue
        and not uploadDue
end

return Cache
