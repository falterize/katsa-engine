-- Imported assets live in the save directory under `editor/assets/<kind>/<file>` while editing
-- and are written into the `.katsa` package under `assets/<kind>/<file>` on export. A node refers
-- to an asset by its store path (`editor/assets/models/crate.glb`); the package path is the same
-- text with the `editor/` prefix removed. Pure path rules are separate from the file copy so the
-- rules can be tested.
local AssetStore = {}

AssetStore.ROOT = 'editor/assets'

local IMAGES = { png = true, jpg = true, jpeg = true, bmp = true, tga = true }
local MODELS = { obj = true, glb = true, gltf = true, blend = true }
local AUDIO = { wav = true, ogg = true, mp3 = true, flac = true }
local FONTS = { ttf = true, otf = true }

local function extension(path)
    return (path:match('%.([^%./\\]+)$') or ''):lower()
end

local function baseName(path)
    return path:match('([^/\\]+)$')
end

-- 'image', 'model', 'audio', 'font' or 'file' (anything else: xml, json, shaders, ...) by file
-- extension (models: what the engine importer registry reads). Every file can be imported.
function AssetStore.kind(path, supports)
    local ext = extension(path)
    if IMAGES[ext] then
        return 'image'
    end
    if AUDIO[ext] then
        return 'audio'
    end
    if FONTS[ext] then
        return 'font'
    end
    if supports then
        if supports(path) then
            return 'model'
        end
    elseif MODELS[ext] then
        return 'model'
    end
    return 'file'
end

local FOLDERS = { model = 'models', image = 'textures', audio = 'audio', font = 'fonts', file = 'files' }

local function safe(name)
    name = name:gsub('[^%w%._%-]', '_')
    return name
end

-- Where a source file is stored: editor/assets/models|textures/<safe name>. `taken` is a
-- function(path) -> boolean that says whether a different file already uses that path.
function AssetStore.targetPath(source, kind, taken)
    local folder = FOLDERS[kind] or 'files'
    local name = safe(baseName(source))
    local stem, ext = name:match('^(.*)(%.[^%.]+)$')
    stem, ext = stem or name, ext or ''
    local path = ('%s/%s/%s'):format(AssetStore.ROOT, folder, name)
    local index = 1
    while taken and taken(path) do
        index = index + 1
        path = ('%s/%s/%s_%d%s'):format(AssetStore.ROOT, folder, stem, index, ext)
    end
    return path
end

-- 'editor/assets/models/a.glb' -> 'assets/models/a.glb'
function AssetStore.packagePath(storePath)
    return (storePath:gsub('^editor/', ''))
end

function AssetStore.storePath(packagePath)
    return 'editor/' .. packagePath
end

-- Copies a readable file (any virtual path or an absolute one the host can read) into the store.
-- Returns the store path, or nil plus a message.
function AssetStore.import(source, supports)
    local kind = AssetStore.kind(source, supports)
    if not kind then
        return nil, 'Unsupported file type: ' .. tostring(baseName(source))
    end
    local bytes, message = katsa.filesystem.read(source)
    if not bytes then
        return nil, tostring(message)
    end
    local target = AssetStore.targetPath(source, kind, function(path)
        local existing = katsa.filesystem.read(path)
        return existing ~= nil and existing ~= bytes
    end)
    if not katsa.filesystem.getInfo(target, 'file') then
        local folder = ''
        for part in target:match('^(.*)/[^/]+$'):gmatch('[^/]+') do
            folder = folder == '' and part or (folder .. '/' .. part)
            katsa.filesystem.createDirectory(folder)
        end
        local ok, writeMessage = katsa.filesystem.write(target, bytes)
        if not ok then
            return nil, tostring(writeMessage)
        end
    end
    return target, kind
end

return AssetStore
