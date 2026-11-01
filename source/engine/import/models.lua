local Array = require('source.engine.math.array')
local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs

local Models = {}
local formats = {
    obj = 'source.engine.import.obj',
    glb = 'source.engine.import.glb',
    gltf = 'source.engine.import.glb',
}

local function format(path)
    local extension = type(path) == 'string' and path:match('%.([^%.]+)$')
    return extension and formats[extension:lower()]
end

function Models.supports(path)
    return not not format(path)
end

function Models.decode(path, resources)
    local packed = require('source.engine.import.packedModel').try(path, resources)
    if packed then
        return packed
    end
    local importer = format(path)
    if importer then
        return require(importer).load(path, resources)
    end
    local extension = path:match('%.([^%.]+)$')
    error(
        'Unsupported runtime format: '
            .. tostring(extension)
            .. '. Convert FBX to GLB on desktop; see docs/guides/modelImport.md'
    )
end
-- Model instances own mutable node poses and animation state, while GPU assets are shared.
local function copy(value, seen)
    if require('source.engine.math.managedValue').is(value) then
        return value:clone()
    end
    if not Array.is(value) or value._assetGeometry or value.mesh and rawget(value, 'vertices') then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do
        result[key] = copy(item, seen)
    end
    return setmetatable(result, getmetatable(value))
end

function Models.load(path, resources)
    path = resources:canonical(path and path ~= '' and path or 'assets/internal/missing-model')
    local asset = resources:cached('model', path, function(owner)
        if not katsa.filesystem.getInfo(path, 'file') then
            -- Keep missing model instances visible and independently editable;
            -- share only the immutable placeholder geometry and texture.
            local geometry = require('source.engine.graphics.geometry.primitives').cube()
            geometry._assetGeometry = true
            owner:own(geometry.mesh)
            if owner.store.journal then
                owner.store.journal:record('Resources', 'Missing model: ' .. path, nil, path)
            end
            return {
                parts = {
                    {
                        name = 'MissingModel',
                        geometry = geometry,
                        material = { image = 'assets/textures/internal/missing.png' },
                    },
                },
                animations = {},
                skins = {},
                time = 0,
                loop = true,
                missing = true,
                source = path,
            }
        end
        return Models.decode(path, owner)
    end)
    local started = katsa.timer.getTime()
    local instance = copy(asset)
    instance.cloneSeconds = katsa.timer.getTime() - started
    return instance
end

function Models.instantiate(world, model, settings)
    assert(not model.root, 'A model instance is already mounted; load/copy another instance')
    settings = settings or {}
    local root = world:create('Node3D', {
        name = settings.name or 'Model',
        position = settings.position,
        rotation = settings.rotation,
        scale = settings.scale or settings.size,
        parent = settings.parent,
    }, settings.parent)
    model.root, model.world = root, world
    local objects, partsByNode, created = {}, {}, {}
    for i, part in ipairs(model.parts) do
        if part.node then
            partsByNode[part.node] = partsByNode[part.node] or {}
            partsByNode[part.node][#partsByNode[part.node] + 1] = { part = part, index = i }
        end
    end

    local function mesh(part, index, parent, name, pose)
        local material = part.material or {}
        local object = world:create('Mesh3D', {
            name = root.name .. '.' .. name,
            poseMatrix = pose,
            geometry = part.geometry,
            maxBoneInfluences = settings.maxBoneInfluences or settings.MaxBoneInfluences,
            bonePaletteLimit = settings.bonePaletteLimit or settings.BonePaletteLimit,
            color = material.color,
            blend = material.blend,
            alphaCutoff = material.alphaCutoff,
            doubleSided = material.doubleSided,
        }, parent)
        assert(
            settings.texture == nil,
            'Model texture override was removed; use settings.colorMap or SurfaceAppearance3D'
        )
        if material.image or settings.colorMap then
            world:create('SurfaceAppearance3D', {
                name = 'SurfaceAppearance',
                colorMap = settings.colorMap or material.image,
                alphaMode = material.blend and 'Blend'
                    or (material.alphaCutoff and material.alphaCutoff > 0 and 'Mask' or 'Inherit'),
                alphaCutoff = material.alphaCutoff,
            }, object)
        end
        objects[index] = object
        created[part] = true
        if part.palette then
            object.skin = {
                model = model,
                definition = model.skins[part.skin + 1],
                palette = part.palette,
                matrices = {},
                node = part.node,
            }
            require('source.engine.animation.skeleton.skinning').initialize(object)
        end
        return object
    end
    if model.nodes then
        local animated = {}
        for _, clip in ipairs(model.animations) do
            for _, channel in ipairs(clip.channels) do
                animated[channel.node] = true
            end
        end

        local function identity(n)
            local m = n.localPose
            for i = 1, 16 do
                if
                    math.abs(m[i] - ((i == 1 or i == 6 or i == 11 or i == 16) and 1 or 0)) > 1e-7
                then
                    return false
                end
            end
            return true
        end

        local function mount(index, parent, isRoot)
            local n = model.nodes[index + 1]
            local entries = partsByNode[n] or {}
            if
                isRoot
                and #model.roots == 1
                and #entries == 0
                and not n.isBone
                and not animated[n]
                and identity(n)
            then
                n.instance = root
            elseif #entries == 1 and not n.isBone then
                n.instance = mesh(entries[1].part, entries[1].index, parent, n.name, n.localPose)
            else
                n.instance = world:create(n.isBone and 'Bone3D' or 'Node3D', {
                    name = n.name,
                    poseMatrix = n.localPose,
                    restPosition = n.rest.translation,
                    restRotation = n.rest.rotation,
                    restScale = n.rest.scale,
                }, parent)
                for j, entry in ipairs(entries) do
                    mesh(entry.part, entry.index, n.instance, n.name .. '_Part' .. j)
                end
            end
            for _, child in ipairs(n.children) do
                mount(child, n.instance, false)
            end
        end
        for _, index in ipairs(model.roots) do
            mount(index, root, true)
        end
    end
    for i, part in ipairs(model.parts) do
        if not created[part] then
            mesh(part, i, root, part.name or ('Mesh' .. i))
        end
    end
    model.objects = objects
    if model.nodes then
        local hasSkin = model.skins and #model.skins > 0
        if hasSkin then
            model.animator = world:create('Animator', { model = model, name = 'Animator' }, root)
        elseif #model.animations > 0 then
            local Class = require('source.engine.nodes').getClass('Animator')
            local controller = setmetatable(
                { model = model, _world = world, _trackParent = root },
                { __index = Class }
            )
            Class.initialize(controller)
            model.controller = controller
            world.rigidControllers = world.rigidControllers or {}
            world.rigidControllers[#world.rigidControllers + 1] = controller
            root:onDestroy(function()
                for i, c in ipairs(world.rigidControllers) do
                    if c == controller then
                        table.remove(world.rigidControllers, i)
                        break
                    end
                end
            end)
        end
        model:update(0)
    end
    root.model = model
    return objects, root
end

return Models
