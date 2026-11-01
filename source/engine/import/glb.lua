local ipairs = require('source.engine.math.array').ipairs
local JSON = require('vendor.json')
local Geometry = require('source.engine.graphics.geometry.primitives')
local M = require('source.engine.math.math3d')

local GLB = {}

function GLB.load(path, resources)
    local data = assert(katsa.filesystem.read(path), 'Missing GLB: ' .. path)
    if path:lower():match('%.gltf$') then
        local document = JSON.decode(data)
        local dir = path:match('^(.*[/])') or ''
        local uri = assert(document.buffers[1].uri, 'glTF buffer URI is required')
        local binary = uri:match('^data:')
                and katsa.data.decode('string', 'base64', uri:match(',([%s%S]+)$'))
            or assert(katsa.filesystem.read(dir .. uri), 'Missing glTF binary buffer')
        assert(#document.buffers == 1, 'Combine glTF buffers before import')
        return GLB.decode(document, binary, path, resources)
    end
    assert(data:sub(1, 4) == 'glTF', 'Invalid GLB magic')
    local version, length = katsa.data.unpack('<I4I4', data, 5)
    assert(version == 2 and length == #data, 'GLB must be a complete glTF 2.0 container')
    local offset, document, binary = 13, nil, nil
    while offset <= #data do
        local size, kind = katsa.data.unpack('<I4I4', data, offset)
        offset = offset + 8
        assert(offset + size - 1 <= #data, 'Truncated GLB chunk')
        local chunk = data:sub(offset, offset + size - 1)
        if kind == 0x4E4F534A then
            document = JSON.decode(chunk)
        elseif kind == 0x004E4942 then
            binary = chunk
        end
        offset = offset + size
    end
    assert(document and binary, 'GLB requires JSON and BIN chunks')
    return GLB.decode(document, binary, path, resources)
end

function GLB.decode(document, binary, path, resources)
    assert(
        not document.extensionsRequired or #document.extensionsRequired == 0,
        'Required glTF extensions are unsupported; export core glTF 2.0'
    )
    local accessor = require('source.engine.import.gltf.accessors').create(document, binary)
    local texture =
        require('source.engine.import.gltf.textures').create(document, binary, path, resources)
    local meshes = {}
    for meshIndex, mesh in ipairs(document.meshes or {}) do
        local parts = {}
        meshes[meshIndex] = parts
        for _, primitive in ipairs(mesh.primitives) do
            assert(not primitive.targets, 'GLB morph targets are unsupported')
            assert(not primitive.mode or primitive.mode == 4, 'GLB supports TRIANGLES only')
            assert(not primitive.extensions, 'GLB primitive extensions require conversion')
            local attrs = primitive.attributes
            local positions = accessor(assert(attrs.POSITION, 'GLB POSITION is required'))
            local normals = attrs.NORMAL and accessor(attrs.NORMAL)
            local uv = attrs.TEXCOORD_0 and accessor(attrs.TEXCOORD_0)
            local joints = attrs.JOINTS_0 and accessor(attrs.JOINTS_0)
            local weights = attrs.WEIGHTS_0 and accessor(attrs.WEIGHTS_0)
            local extraJoints = attrs.JOINTS_1 and accessor(attrs.JOINTS_1)
            local extraWeights = attrs.WEIGHTS_1 and accessor(attrs.WEIGHTS_1)
            assert((joints ~= nil) == (weights ~= nil), 'GLB requires both JOINTS_0 and WEIGHTS_0')
            assert(
                (extraJoints ~= nil) == (extraWeights ~= nil),
                'GLB requires paired extra skin attributes'
            )
            assert(not extraJoints or joints, 'GLB extra weights require the first skin set')
            assert(not attrs.JOINTS_2, 'Export at most eight weights per vertex')
            assert(not attrs.COLOR_0, 'GLB vertex colors require baking into a texture')
            local indices = primitive.indices and accessor(primitive.indices)
            local count = indices and #indices or #positions
            assert(count % 3 == 0, 'GLB triangle index count must be divisible by three')
            local vertices = {}
            for i = 1, count do
                local index = indices and indices[i][1] + 1 or i
                local p = assert(positions[index], 'GLB index exceeds position array')
                local n = normals and normals[index]
                local t = uv and uv[index]
                vertices[i] = {
                    p[1],
                    p[2],
                    p[3],
                    t and t[1] or 0,
                    t and t[2] or 0,
                    n and n[1],
                    n and n[2],
                    n and n[3],
                }
            end
            if joints then
                for i, v in ipairs(vertices) do
                    local index = indices and indices[i][1] + 1 or i
                    local total = 0
                    for j = 1, 4 do
                        total = total + weights[index][j]
                        if extraWeights then
                            total = total + extraWeights[index][j]
                        end
                    end
                    assert(total > 1e-8, 'Skin vertex has no positive weight')
                    for j = 1, 4 do
                        assert(weights[index][j] >= 0, 'Skin weights must be nonnegative')
                        v[8 + j], v[12 + j] = joints[index][j], weights[index][j] / total
                        if extraWeights then
                            assert(extraWeights[index][j] >= 0, 'Skin weights must be nonnegative')
                            v[16 + j], v[20 + j] =
                                extraJoints[index][j], extraWeights[index][j] / total
                        end
                    end
                end
            end
            local material = primitive.material and document.materials[primitive.material + 1] or {}
            local pbr = material.pbrMetallicRoughness or {}
            local base = pbr.baseColorTexture
            assert(
                not base or (not base.texCoord or base.texCoord == 0),
                'GLB uses only TEXCOORD_0'
            )
            assert(
                not base or not base.extensions,
                'GLB texture transform extensions require baking'
            )
            local batches = joints
                    and require('source.engine.import.gltf.skinGeometry').build(vertices, resources)
                or { { geometry = Geometry.mesh(Geometry.normals(vertices)) } }
            for _, batch in ipairs(batches) do
                if not joints then
                    resources:own(batch.geometry.mesh)
                end
                parts[#parts + 1] = {
                    geometry = batch.geometry,
                    palette = batch.palette,
                    material = {
                        color = pbr.baseColorFactor or { 1, 1, 1, 1 },
                        image = base and texture(base.index),
                        blend = material.alphaMode == 'BLEND',
                        alphaCutoff = material.alphaMode == 'MASK'
                                and (material.alphaCutoff or 0.5)
                            or 0,
                        doubleSided = material.doubleSided == true,
                    },
                }
            end
        end
    end
    local nodes = {}
    for i, n in ipairs(document.nodes or {}) do
        local matrix
        if n.matrix then
            matrix = {}
            for row = 0, 3 do
                for col = 0, 3 do
                    matrix[row * 4 + col + 1] = n.matrix[col * 4 + row + 1]
                end
            end
        end
        nodes[i] = {
            name = n.name or ('node' .. i),
            translation = n.translation or { 0, 0, 0 },
            rotation = n.rotation or { 0, 0, 0, 1 },
            scale = n.scale or { 1, 1, 1 },
            matrix = matrix,
            children = n.children or {},
            mesh = n.mesh,
            skin = n.skin,
            extras = n.extras,
            world = M.identity(),
        }
    end
    local scene =
        assert((document.scenes or {})[(document.scene or 0) + 1], 'GLB scene is required')
    local model = {
        nodes = nodes,
        roots = scene.nodes or {},
        parts = {},
        animations = {},
        time = 0,
        loop = true,
    }
    local visiting, visited = {}, {}

    local function visit(index, parent)
        assert(not visiting[index] and not visited[index], 'GLB node cycle or multiple parents')
        visiting[index] = true
        visited[index] = true
        local n = assert(nodes[index + 1], 'Invalid GLB node reference')
        n.parent = parent
        if n.mesh then
            for _, part in ipairs(assert(meshes[n.mesh + 1], 'Invalid GLB mesh')) do
                model.parts[#model.parts + 1] = {
                    name = n.name,
                    geometry = part.geometry,
                    material = part.material,
                    node = n,
                    localMatrix = n.world,
                    palette = part.palette,
                    skin = n.skin,
                }
            end
        end
        for _, child in ipairs(n.children) do
            visit(child, n)
        end
        visiting[index] = nil
    end
    for _, root in ipairs(model.roots) do
        visit(root, nil)
    end
    for i, animation in ipairs(document.animations or {}) do
        local clip = {
            name = animation.name or ('animation' .. i),
            channels = {},
            duration = 0,
            markers = animation.extras and animation.extras.markers or {},
        }
        for _, channel in ipairs(animation.channels) do
            local sampler = animation.samplers[channel.sampler + 1]
            local method = sampler.interpolation or 'LINEAR'
            assert(
                method == 'LINEAR' or method == 'STEP' or method == 'CUBICSPLINE',
                'Unsupported glTF interpolation'
            )
            local target = channel.target.path
            assert(
                target == 'translation' or target == 'rotation' or target == 'scale',
                'GLB morph animation is unsupported'
            )
            local n = assert(nodes[channel.target.node + 1], 'Invalid animated node')
            assert(not n.matrix, 'Animated GLB node must use TRS')
            local times, values = accessor(sampler.input), accessor(sampler.output)
            assert(
                #values == #times * (method == 'CUBICSPLINE' and 3 or 1),
                'GLB animation sample count mismatch'
            )
            local previous = -1
            for _, key in ipairs(times) do
                assert(
                    key[1] >= 0 and key[1] > previous and key[1] < math.huge,
                    'Animation key times must be finite and strictly increasing'
                )
                previous = key[1]
            end
            clip.duration = math.max(clip.duration, times[#times][1])
            clip.channels[#clip.channels + 1] =
                { node = n, target = target, times = times, values = values, method = method }
        end
        model.animations[i] = clip
    end
    model.skins = {}

    local function row(matrix)
        local out = {}
        for r = 0, 3 do
            for c = 0, 3 do
                out[r * 4 + c + 1] = matrix[c * 4 + r + 1]
            end
        end
        return out
    end
    for _, skin in ipairs(document.skins or {}) do
        local matrices = skin.inverseBindMatrices and accessor(skin.inverseBindMatrices)
        local definition =
            { name = skin.name or 'Skeleton', joints = skin.joints, inverseBindMatrices = {} }
        assert(
            not matrices or #matrices == #skin.joints,
            'Skin bind matrix count does not match joints'
        )
        for i, joint in ipairs(skin.joints) do
            assert(nodes[joint + 1], 'Skin references a missing joint')
            definition.inverseBindMatrices[i] = matrices and row(matrices[i]) or M.identity()
            nodes[joint + 1].isBone = true
        end
        model.skins[#model.skins + 1] = definition
    end
    require('source.engine.animation.skeleton.rig').initialize(model)
    model:update(0)
    return model
end

return GLB
