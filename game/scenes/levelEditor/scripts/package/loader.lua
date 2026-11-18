-- Runtime loader that ships inside every exported `.katsa` package (copied to scripts/loader.lua
-- together with scripts/shapes.lua and scripts/luaText.lua). It reads assets/location.lua and
-- builds the nodes into the scene's world. Asset paths in the file are package-relative
-- (`assets/...`); they are resolved against the package root here. Self-contained on purpose:
-- the package must run without the editor.
local Loader = {}

local SUPPORTED = 1

local function resolve(value, root)
    if type(value) == 'string' then
        if value:sub(1, 7) == 'assets/' then
            return root .. '/' .. value
        end
        return value
    elseif type(value) == 'table' then
        local result = {}
        for key, item in pairs(value) do
            result[key] = resolve(item, root)
        end
        return result
    end
    return value
end

local function build(world, entry, parent, root, Shapes)
    local properties = resolve(entry.properties or {}, root)
    properties.name = entry.name
    local node
    if entry.model then
        node = world:loadModel(root .. '/' .. entry.model)
        node:setParent(parent)
        for key, value in pairs(properties) do
            node[key] = value
        end
    else
        local shape = entry.attributes and entry.attributes.EditorShape
        if shape then
            properties.geometry = Shapes.geometry(world, shape)
        end
        node = world:create(entry.class, properties, parent)
    end
    for name, value in pairs(entry.attributes or {}) do
        node:setAttribute(name, value)
    end
    for _, child in ipairs(entry.children or {}) do
        build(world, child, node, root, Shapes)
    end
    return node
end

local function hasSun(entries)
    for _, entry in ipairs(entries) do
        if entry.class == 'DirectionalLight3D' or hasSun(entry.children or {}) then
            return true
        end
    end
    return false
end

function Loader.create(scene, context)
    local LuaText = context:require('scripts.luaText')
    local Shapes = context:require('scripts.shapes')
    local text = assert(katsa.filesystem.read(context.root .. '/assets/location.lua'), 'Missing assets/location.lua')
    local data = assert(LuaText.parse(text, 'location.lua'))
    assert(data.format == 'katsa-location', 'Not a Katsa location file')
    assert(
        type(data.version) == 'number' and data.version >= 1 and data.version <= SUPPORTED,
        'Unsupported location version ' .. tostring(data.version)
    )
    local world = scene.world
    local level = world:create('Node3D', { name = 'Level' })
    for _, entry in ipairs(data.nodes) do
        build(world, entry, level, context.root, Shapes)
    end
    if data.ambient then
        world.environment.ambient = data.ambient
    end
    if not hasSun(data.nodes) then
        world:create('DirectionalLight3D', { name = 'Sun', rotation = { 50, 35, 0 } })
    end
    local camera = scene.camera
    if data.camera then
        camera.position = data.camera.position or camera.position
        camera.rotation = data.camera.rotation or camera.rotation
        camera.fov = data.camera.fov or camera.fov
    end
    return { level = level, data = data }
end

return Loader
