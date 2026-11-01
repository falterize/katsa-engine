local World = require('source.engine.world.world')
local Models = require('source.engine.import.models')
local References = require('source.engine.editor.inspectors.nodeReferences')
local Properties = require('source.engine.editor.inspectors.properties')
local Geometry = require('source.engine.physics.3d.modelCollider')

local Tests = {}

local function bounds(points)
    local result = { math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge }
    for _, point in ipairs(points) do
        for i = 1, 3 do
            result[i] = math.min(result[i], point[i])
            result[i + 3] = math.max(result[i + 3], point[i])
        end
    end
    return result
end

function Tests.run(tester)
    for _, backend in ipairs({ 'oimo', 'jolt' }) do
        local resources = tester.manager.resources:scope()
        local world = World.new(resources)
        world:createPhysics({ backend = backend, gravity = { 0, 0, 0 } })
        local body = world:create('Body3D', { bodyType = 'Static', position = { 20, 30, 40 } })
        local collider = world:create('Collider3D', {
            shape = 'Geometry',
            collisionLevel = 'Convex',
            size = { 2, 3, 4 },
        }, body)
        for _, filename in ipairs({ 'pyramid.obj', 'cubeTriangle.glb', 'skinRibbon.gltf' }) do
            local path = 'shared://models/examples/' .. filename
            local count = #world.root:getDescendants()
            collider.shape, collider.geometrySource = 'Geometry', path
            local points, indices = collider:getPointsFromModel()
            tester:check(
                #points >= 3 and #indices >= 3 and #world.root:getDescendants() == count,
                backend .. ': ' .. filename .. ' extracts without render nodes'
            )
            world:updateNodes(1 / 60)
            tester:check(
                collider.status == 'Ready' and #body.body.shapes > 0,
                backend .. ': ' .. filename .. ' creates native file collision'
            )
            collider.collisionLevel = 'Detailed'
            world:updateNodes(1 / 60)
            tester:check(
                collider.status == 'Ready' and #body.body.shapes == #indices / 3,
                backend .. ': ' .. filename .. ' supports direct Detailed file collision'
            )
            collider.collisionLevel = 'Simple'
            world:updateNodes(1 / 60)
            tester:check(
                collider.status == 'Ready',
                backend .. ': ' .. filename .. ' supports direct Simple file collision'
            )
            collider.collisionLevel = 'Convex'
            local parts = Geometry.collect(collider, body)
            tester:check(
                parts == Geometry.collect(collider, body),
                backend .. ': unchanged file source reuses collected geometry'
            )
            local model = Models.load(path, resources)
            local _, root = Models.instantiate(world, model, { parent = body, scale = { 2, 3, 4 } })
            local fromNode = collider:getPointsFromMesh(root)
            local a, b, matches = bounds(points), bounds(fromNode), true
            for i = 1, 6 do
                matches = matches and math.abs(a[i] - b[i]) < 0.0001
            end
            tester:check(matches, backend .. ': file transforms match mounted model geometry')
            tester:check(
                References.accepts(collider, 'geometrySource', path)
                    and References.accepts(collider, 'geometrySource', root),
                backend .. ': picker accepts both path and live node'
            )
            local zero = Geometry.collect({ geometrySource = root }, body)
            local shifted = Geometry.collect(
                { geometrySource = root, position = { 7, 8, 9 }, rotation = { 0, 35, 0 } },
                body
            )
            local same = true
            for i = 1, 16 do
                same = same and math.abs(zero[1].frame[i] - shifted[1].frame[i]) < 0.00001
            end
            tester:check(same, backend .. ': node geometry does not bake the collider offset twice')
            root:destroy()
            collider:setPointsFromModel(path)
            points[1][1] = points[1][1] + 100
            tester:check(
                collider.shape == 'Points' and collider.points[1][1] ~= points[1][1],
                backend .. ': baked points are independent editable copies'
            )
            collider.collisionLevel = 'Detailed'
            world:updateNodes(1 / 60)
            tester:check(
                collider.status == 'Ready',
                backend .. ': file points retain triangle topology'
            )
            collider.collisionLevel = 'Convex'
        end
        collider.shape, collider.geometrySource = 'Geometry', 'shared://models/examples/pyramid.obj'
        world:updateNodes(1 / 60)
        local previous = collider._descriptor
        collider.geometrySource = 'shared://models/not-found.glb'
        world:updateNodes(1 / 60)
        tester:check(
            collider._descriptor == previous
                and collider.status:find('Missing collider model', 1, true),
            backend .. ': invalid path preserves the last valid collider'
        )
        local ok = Properties.set(
            nil,
            collider,
            { key = 'geometrySource', kind = 'node' },
            'shared://models/examples/cubeTriangle.glb'
        )
        tester:check(
            ok and type(collider.geometrySource) == 'string',
            backend .. ': inspector writes model paths'
        )
        tester:check(
            not Properties.set(
                nil,
                collider,
                { key = 'geometrySource', kind = 'node' },
                'shared://models/not-found.fbx'
            ),
            backend .. ': inspector rejects unsupported model paths'
        )
        world:updateNodes(1 / 60)
        tester:check(
            collider.status == 'Ready',
            backend .. ': valid path recovers after source error'
        )
        world:release()
        resources:release()
    end
    local scene = require('source.game.runtime.application').new(tester.manager, 'collisionModels')
    scene:load()
    scene:update(1 / 60, 1 / 60)
    local fileCollider
    for _, node in ipairs(scene.world.root:getDescendants()) do
        if
            node:isA('Collider3D')
            and type(node.geometrySource) == 'string'
            and node.shape == 'Geometry'
        then
            fileCollider = node
            break
        end
    end
    tester:check(
        fileCollider and fileCollider.status == 'Ready',
        'Collision Models example runs its direct file collider'
    )
    local workspace = scene.workspace
    workspace:select(fileCollider)
    workspace:updateValues()
    local field = { key = 'geometrySource', kind = 'node', value = fileCollider.geometrySource }
    workspace:openPopup(field)
    local inputs = 0
    for _, child in ipairs(workspace.popup.body.children) do
        if child:isA('TextBox') then
            inputs = inputs + 1
        end
    end
    tester:check(inputs == 1, 'Geometry source picker includes an editable model path')
    workspace.popup:close(false)
    scene:draw()
    scene:release()
end

return Tests
