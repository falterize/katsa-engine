-- Engine-facing half of `.katsa` export/import: turns the Level into a package (bytes) and a
-- package back into a Level. Pure parts live in locationFormat, packagePaths and recent.
local Archive = require('source.katsa.core.archive')
local Clone = require('source.engine.nodes.core.clone')
local AssetStore = require('./assetStore')
local Format = require('./locationFormat')
local LuaText = require('./luaText')
local NodeData = require('../core.nodeData')
local PackagePaths = require('./packagePaths')
local Recent = require('./recent')

local LocationIO = {}

LocationIO.FOLDER = 'editor/locations'
LocationIO.EXPORTS = 'editor/exports'
LocationIO.AUTOSAVE = 'editor/autosave.katsa'
LocationIO.RECENT = 'editor/recent.lua'

local STORE = AssetStore.ROOT .. '/' -- 'editor/assets/'
local PACKAGE = 'assets/'

-- Runtime-only editor ids must not leak into a file; ids are handed out again on import.
local function cleanSnapshot(snapshot, warnings)
    local properties, lostProperties = PackagePaths.sanitize(snapshot.properties)
    local attributes, lostAttributes = PackagePaths.sanitize(snapshot.attributes)
    attributes.EditorId = nil
    if lostProperties + lostAttributes > 0 then
        warnings[#warnings + 1] = ('%s: %d value(s) cannot be saved'):format(
            tostring(snapshot.name),
            lostProperties + lostAttributes
        )
    end
    snapshot.properties, snapshot.attributes = properties, attributes
    for _, child in ipairs(snapshot.children) do
        cleanSnapshot(child, warnings)
    end
end

local function sourceOf(content, relative)
    return assert(katsa.filesystem.read(content.context.root .. '/scripts/' .. relative), relative)
end

-- Returns the package bytes and a list of warnings (dropped values, missing asset files).
function LocationIO.export(content)
    local warnings, nodes = {}, {}
    for _, node in ipairs(content.level.children) do
        if not node.destroyed then
            local snapshot = NodeData.capture(node)
            cleanSnapshot(snapshot, warnings)
            nodes[#nodes + 1] = snapshot
        end
    end
    local used = {}
    for _, snapshot in ipairs(nodes) do
        PackagePaths.collect(snapshot, STORE, used)
    end
    local files = {}
    for storePath in pairs(used) do
        local bytes = katsa.filesystem.read(storePath)
        if bytes then
            files[PackagePaths.rewrite(storePath, STORE, PACKAGE)] = bytes
        else
            warnings[#warnings + 1] = 'Missing asset file: ' .. storePath
        end
    end
    nodes = PackagePaths.rewrite(nodes, STORE, PACKAGE)
    local data = Format.encode(nodes, {
        className = function(node)
            return node.class
        end,
        name = function(node)
            return node.name
        end,
        properties = function(node)
            return node.properties
        end,
        attributes = function(node)
            return node.attributes
        end,
        model = function(node)
            return node.model
        end,
        children = function(node)
            return node.children
        end,
    })
    local camera = content.camera
    data.camera = {
        position = { camera.position[1], camera.position[2], camera.position[3] },
        rotation = { camera.rotation[1], camera.rotation[2], camera.rotation[3] },
        fov = camera.fov,
    }
    files['scripts/shapes.lua'] = sourceOf(content, 'builders/shapes.lua')
    files['scripts/luaText.lua'] = sourceOf(content, 'io/luaText.lua')
    return Format.pack(data, files, sourceOf(content, 'package/loader.lua')), warnings
end

local function ensureFolder(path)
    local folder = ''
    for part in (path:match('^(.*)/[^/]+$') or ''):gmatch('[^/]+') do
        folder = folder == '' and part or (folder .. '/' .. part)
        katsa.filesystem.createDirectory(folder)
    end
end

local function writeFile(path, bytes)
    ensureFolder(path)
    return katsa.filesystem.write(path, bytes)
end

-- Copies the package's asset files into the store; a name that already holds different bytes
-- gets a new numbered name. Returns the package-path -> store-path map.
local function importAssets(archive)
    local map = {}
    local function walk(folder)
        for _, name in ipairs(archive:list(folder) or {}) do
            local path = folder .. '/' .. name
            if archive:has(path) then
                if path ~= 'assets/location.lua' then
                    map[path] = true
                end
            else
                walk(path)
            end
        end
    end
    walk('assets')
    for packagePath in pairs(map) do
        local bytes = archive:read(packagePath)
        local target = PackagePaths.rewrite(packagePath, PACKAGE, STORE)
        local index = 1
        while true do
            local existing = katsa.filesystem.read(target)
            if existing == nil or existing == bytes then
                break
            end
            index = index + 1
            target = PackagePaths.rewrite(packagePath, PACKAGE, STORE):gsub('(%.[^%./]+)$', '_' .. index .. '%1')
        end
        if katsa.filesystem.read(target) == nil then
            writeFile(target, bytes)
        end
        map[packagePath] = target
    end
    return map
end

local function mapPaths(value, map)
    if type(value) == 'string' then
        return map[value] or value
    elseif type(value) == 'table' then
        local result = {}
        for key, item in pairs(value) do
            result[key] = mapPaths(item, map)
        end
        return result
    end
    return value
end

-- Replaces the Level with the package's content, or with `merge` adds the objects to it as one
-- undo step. Returns the node count or nil plus a message; on a bad file the Level is untouched.
function LocationIO.import(content, bytes, merge)
    local ok, archive = pcall(Archive.fromString, bytes, 'location')
    if not ok then
        return nil, 'Not a valid .katsa file: ' .. tostring(archive)
    end
    local text = archive:read('assets/location.lua')
    if not text then
        return nil, 'The file has no assets/location.lua'
    end
    local data, message = Format.parse(text)
    if not data then
        return nil, message
    end
    local nodes = mapPaths(data.nodes, importAssets(archive))
    if not merge then
        content:clearLevel()
    end
    local world = content.world
    local count = 0
    local created = {}
    local function walk(entry)
        count = count + 1
        for _, child in ipairs(entry.children or {}) do
            walk(child)
        end
    end
    for _, entry in ipairs(nodes) do
        entry.attributes = entry.attributes or {}
        entry.children = entry.children or {}
        entry.properties = entry.properties or {}
        walk(entry)
        if merge then
            entry.name = Clone.uniqueName(world, entry.name or entry.class)
            entry.attributes.EditorId = nil
        end
        local node = NodeData.build(world, entry, content.level)
        content.ops:adopt(node, merge)
        created[#created + 1] = node
    end
    if merge then
        content.ops:record('Import location', created)
        content.selection:set(created)
    elseif data.camera then
        content.camera.position = data.camera.position
        content.camera.rotation = data.camera.rotation
    end
    return count, created
end

local function safeName(name)
    name = (name or ''):gsub('%.katsa$', ''):gsub('[^%w%._%- ]', '_')
    return name ~= '' and name or 'untitled'
end

function LocationIO.pathFor(name)
    return ('%s/%s.katsa'):format(LocationIO.FOLDER, safeName(name))
end

function LocationIO.nameOf(path)
    return path:match('([^/]+)%.katsa$') or path
end

function LocationIO.readRecent()
    local text = katsa.filesystem.read(LocationIO.RECENT)
    local list = text and LuaText.parse(text, 'recent.lua')
    return type(list) == 'table' and list or {}
end

function LocationIO.remember(path)
    local list = Recent.push(LocationIO.readRecent(), path)
    writeFile(LocationIO.RECENT, LuaText.serialize(list))
    return list
end

function LocationIO.forget(path)
    writeFile(LocationIO.RECENT, LuaText.serialize(Recent.remove(LocationIO.readRecent(), path)))
end

LocationIO.write = writeFile

return LocationIO
