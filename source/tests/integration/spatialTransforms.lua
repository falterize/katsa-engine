return function(test)
    local Node = require('source.engine.nodes')
    local Math = require('source.engine.math.math3d')
    local Affine = require('source.engine.math.affine')

    local function close(a, b)
        if #a ~= #b then
            return false
        end
        for i = 1, #a do
            if math.abs(a[i] - b[i]) > 1e-5 then
                return false
            end
        end
        return true
    end

    local function check(ok, msg)
        test:check(ok, msg)
    end
    for _, angles in ipairs({ { 23, -41, 17 }, { -63, 87, -29 }, { 0, 90, 35 }, { 12, -90, 0 } }) do
        local m = Math.compose({ 3, 5, -7 }, angles, { 2, 3, 4 })
        local p, r, s = Affine.decompose(m)
        check(
            close(Math.compose(p, r, s), m),
            'TRS decomposition preserves mixed/gimbal rotation ' .. table.concat(angles, ',')
        )
        check(
            close(Math.multiply(Affine.inverse(m), m), Math.identity()),
            'Affine inverse restores identity ' .. table.concat(angles, ',')
        )
    end
    local root = Node.new('World3D', {})
    local a = Node.new('Mesh3D', {
        position = { 10, 0, 0 },
        rotation = { 0, 90, 0 },
        size = { 8, 6, 4 },
        scale = { 2, 2, 2 },
    }, root)
    local folder = Node.new('Folder', {}, a)
    local child = Node.new('Node3D', { position = { 0, 0, 3 } }, folder)
    check(
        close(child:getWorldPosition(), { 4, 0, 0 }),
        'Folder hierarchy inherits spatial scale and rotation'
    )
    a.size = { 40, 30, 20 }
    check(
        close(child:getWorldPosition(), { 4, 0, 0 }),
        'Geometry dimensions do not scale descendant offsets'
    )
    local socket = Node.new('Attachment3D', { position = { 0, 0, 3 } }, a)
    check(
        close(socket:getWorldPosition(), { 7, 0, 0 }),
        'Attachment3D excludes parent scale by default'
    )
    socket.inheritScale = true
    check(
        close(socket:getWorldPosition(), { 4, 0, 0 }),
        'Attachment3D can opt into spatial scale inheritance'
    )
    local v = { 1, 2, 3 }
    check(
        close(child:pointToLocalSpace(child:pointToWorldSpace(v)), v),
        'Point space conversions round trip'
    )
    check(
        close(child:vectorToLocalSpace(child:vectorToWorldSpace(v)), v),
        'Direction space conversions round trip'
    )
    check(
        close(child:vectorToWorldSpace({ 0, 0, 1 }), { -2, 0, 0 }),
        'Direction conversion excludes translation and retains scale'
    )
    local old = Affine.copy(child:getWorldMatrix())
    local b = Node.new(
        'Node3D',
        { position = { -10, 6, 0 }, rotation = { 15, -20, 8 }, scale = { 3, 3, 3 } },
        root
    )
    local observed = false
    child:connect('parentChanged', function()
        observed = close(child:getWorldMatrix(), old)
    end)
    child:setParent(b, { keepWorldTransform = true })
    check(
        close(child:getWorldMatrix(), old) and observed,
        'Reparent preserves world pose before parentChanged event'
    )
    local desired = Math.compose({ 12, 13, 14 }, { 32, -12, 54 }, { 2, 2, 2 })
    child:setWorldMatrix(desired)
    check(close(child:getWorldMatrix(), desired), 'World3D matrix setter resolves parent pose')
    local localPose = child:getLocalTransform()
    child:setLocalTransform(localPose)
    check(close(child:getWorldMatrix(), desired), 'Local TRS getter/setter round trip')
    child:setWorldTransform({
        position = { 2, 4, 6 },
        rotation = { 10, 20, 30 },
        scale = { 3, 3, 3 },
    })
    check(
        close(child:getWorldTransform().position, { 2, 4, 6 }),
        'World3D TRS setter and getter agree'
    )
    local frame = child:getWorldCFrame()
    child:setWorldCFrame(frame)
    check(
        close(child:getWorldTransform().scale, { 3, 3, 3 }),
        'World3D CFrame setter preserves spatial scale'
    )
    local camera = Node.new('Camera3D', { rotation = { 12, 28, 9 } }, root)
    local cp = camera:getLocalTransform()
    check(
        close(cp.rotation, camera.rotation),
        'Camera3D retains existing pitch/yaw property convention'
    )
    local cm = Affine.copy(camera:getWorldMatrix())
    camera:setLocalMatrix(cm)
    check(close(camera:getWorldMatrix(), cm), 'Camera3D matrix setter retains existing orientation')
    local viewCamera = require('source.engine.cameras.camera').new({
        position = { 3, 5, 7 },
        rotation = { 12, 28, 9 },
        scale = { 2, 2, 2 },
    })
    viewCamera:update(1280, 720)
    local basis = Affine.withoutScale(viewCamera:getWorldMatrix())
    check(
        close(viewCamera.forward, { basis[3], basis[7], basis[11] })
            and close(viewCamera.up, { basis[2], basis[6], basis[10] }),
        'Camera3D view follows full spatial rotation including root roll'
    )
    viewCamera.parent = a
    viewCamera:update(1280, 720)
    check(
        close(viewCamera.worldPosition, viewCamera:getWorldPosition()),
        'Camera3D listener and view use inherited world position'
    )
    viewCamera:destroy()
    local skew = Node.new('Node3D', { scale = { 2, 3, 4 }, rotation = { 10, 30, 0 } }, root)
    local previous = child.parent
    local before = Affine.copy(child:getWorldMatrix())
    check(
        not pcall(child.setParent, child, skew, { keepWorldTransform = true })
            and child.parent == previous
            and close(child:getWorldMatrix(), before),
        'Unrepresentable sheared reparent rejects atomically'
    )
    check(
        not pcall(child.setLocalTransform, child, { scale = { 0, 1, 1 } }),
        'Zero scale rejected before mutation'
    )
    check(
        not pcall(child.setLocalTransform, child, { scale = { -1, 1, 1 } }),
        'Mirrored scale rejected before mutation'
    )
    local rendered = Node.new('Mesh3D', {
        position = { 1, 2, 3 },
        size = { 4, 5, 6 },
        scale = { 2, 3, 4 },
        matrix = Math.identity(),
        normal = {},
        geometry = { radius = 1 },
    }, root)
    require('source.engine.world.world').updateObject({}, rendered)
    check(
        rendered.matrix[1] == 8 and rendered.matrix[6] == 15 and rendered.matrix[11] == 24,
        'Render matrix combines geometry dimensions with independent spatial scale'
    )
    rendered.size[1] = 7
    local rev = rendered._transformRevision
    require('source.engine.world.world').updateObject({}, rendered)
    check(
        rendered.matrix[1] == 14 and rendered._transformRevision == rev,
        'Geometry-only edit updates render bounds without spatial revision'
    )
    root:destroy()
end
