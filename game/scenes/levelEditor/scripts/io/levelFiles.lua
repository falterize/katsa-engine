-- The files of the level that is open in the editor: everything under `editor/assets` in the save
-- directory (imported models and textures, plus whatever the author creates). Listing, creating,
-- renaming and deleting are here, with the name rules that keep every path inside that root. The
-- file system is a parameter (default `katsa.filesystem`) so the rules can be tested. Pure Lua.
local LevelFiles = {}

LevelFiles.ROOT = 'editor/assets'

-- A single path component: no separators, no leading dot, no control characters.
function LevelFiles.validName(name)
    if type(name) ~= 'string' or name == '' or #name > 100 then
        return false, 'Enter a name (up to 100 characters)'
    end
    if name:find('[/\\:%*%?"<>|%c]') or name:sub(1, 1) == '.' or name:sub(-1) == ' ' then
        return false, 'A name cannot contain / \\ : * ? " < > | or start with a dot'
    end
    return true
end

-- `path` is a folder below the root ('' = the root): normalises it and rejects anything that
-- would leave the root. Returns the clean relative path or nil.
function LevelFiles.clean(path)
    local parts = {}
    for part in (path or ''):gmatch('[^/\\]+') do
        if part == '..' or part == '.' then
            return nil
        end
        parts[#parts + 1] = part
    end
    return table.concat(parts, '/')
end

function LevelFiles.full(path)
    return path == '' and LevelFiles.ROOT or (LevelFiles.ROOT .. '/' .. path)
end

function LevelFiles.join(path, name)
    return path == '' and name or (path .. '/' .. name)
end

function LevelFiles.parent(path)
    return path:match('^(.*)/[^/]+$') or ''
end

-- Folder an import lands in when the author is not looking at a level folder.
local FOLDERS = { model = 'models', image = 'textures', audio = 'audio', font = 'fonts', file = 'files' }

function LevelFiles.folderFor(kind)
    return FOLDERS[kind] or 'files'
end

local function ensure(fs, path)
    local folder = ''
    for part in path:gmatch('[^/]+') do
        folder = folder == '' and part or (folder .. '/' .. part)
        fs.createDirectory(folder)
    end
end

-- { dirs = { { name, path } }, files = { { name, path, store } } } for the folder `path`.
-- `path` is relative to the root; `store` is the full store path a node can refer to.
function LevelFiles.list(path, fs)
    fs = fs or katsa.filesystem
    path = LevelFiles.clean(path) or ''
    ensure(fs, LevelFiles.ROOT)
    local result = { dirs = {}, files = {} }
    for _, name in ipairs(fs.getDirectoryItems(LevelFiles.full(path))) do
        local relative = LevelFiles.join(path, name)
        local store = LevelFiles.full(relative)
        if fs.getInfo(store, 'directory') then
            result.dirs[#result.dirs + 1] = { name = name, path = relative, store = store, dir = true }
        else
            result.files[#result.files + 1] = { name = name, path = relative, store = store }
        end
    end
    return result
end

function LevelFiles.createFolder(path, name, fs)
    fs = fs or katsa.filesystem
    local ok, message = LevelFiles.validName(name)
    if not ok then
        return nil, message
    end
    local relative = LevelFiles.join(LevelFiles.clean(path) or '', name)
    if fs.getInfo(LevelFiles.full(relative)) then
        return nil, name .. ' already exists'
    end
    ensure(fs, LevelFiles.full(relative))
    return relative
end

function LevelFiles.createFile(path, name, fs)
    fs = fs or katsa.filesystem
    local ok, message = LevelFiles.validName(name)
    if not ok then
        return nil, message
    end
    local relative = LevelFiles.join(LevelFiles.clean(path) or '', name)
    if fs.getInfo(LevelFiles.full(relative)) then
        return nil, name .. ' already exists'
    end
    ensure(fs, LevelFiles.full(path ~= '' and LevelFiles.clean(path) or ''))
    local written, writeMessage = fs.write(LevelFiles.full(relative), '')
    if not written then
        return nil, tostring(writeMessage)
    end
    return relative
end

-- Renames a file or folder in place (same parent). Returns the new relative path or nil, message.
function LevelFiles.rename(path, newName, fs)
    fs = fs or katsa.filesystem
    path = LevelFiles.clean(path)
    if not path or path == '' then
        return nil, 'Nothing to rename'
    end
    local ok, message = LevelFiles.validName(newName)
    if not ok then
        return nil, message
    end
    local target = LevelFiles.join(LevelFiles.parent(path), newName)
    if target == path then
        return path
    end
    if fs.getInfo(LevelFiles.full(target)) then
        return nil, newName .. ' already exists'
    end
    local renamed, renameMessage = fs.rename(LevelFiles.full(path), LevelFiles.full(target))
    if not renamed then
        return nil, tostring(renameMessage or 'Rename failed')
    end
    return target
end

local function removeAll(fs, store)
    if fs.getInfo(store, 'directory') then
        for _, name in ipairs(fs.getDirectoryItems(store)) do
            if not removeAll(fs, store .. '/' .. name) then
                return false
            end
        end
    end
    return fs.remove(store) and true or false
end

-- Bytes of a file: through the virtual file system first, then straight from disk for an absolute
-- path (the system file dialog returns those, and the virtual file system does not see them).
local function readSource(fs, source)
    local bytes, message = fs.read(source)
    if bytes then
        return bytes
    end
    if source:match('^%a:[/\\]') or source:sub(1, 1) == '/' or source:sub(1, 2) == '\\\\' then
        local handle = io.open(source, 'rb')
        if handle then
            local data = handle:read('*a')
            handle:close()
            return data
        end
    end
    return nil, message
end

-- Copies the bytes of `source` (any readable path) into level folder `folder` under a clean,
-- unused name (a.png, a_2.png, ...). Returns the new relative path or nil, message.
function LevelFiles.importFile(source, folder, fs)
    fs = fs or katsa.filesystem
    folder = LevelFiles.clean(folder)
    if not folder then
        return nil, 'Invalid folder'
    end
    local bytes, message = readSource(fs, source)
    if not bytes then
        return nil, tostring(message or ('Cannot read ' .. tostring(source)))
    end
    local name = (source:match('([^/\\]+)$') or 'file'):gsub('[^%w%._%-]', '_')
    if name:sub(1, 1) == '.' then
        name = '_' .. name
    end
    local stem, ext = name:match('^(.*)(%.[^%.]+)$')
    stem, ext = stem or name, ext or ''
    local relative, index = LevelFiles.join(folder, name), 1
    while fs.getInfo(LevelFiles.full(relative)) do
        if fs.read(LevelFiles.full(relative)) == bytes then
            return relative -- the same file is already there
        end
        index = index + 1
        relative = LevelFiles.join(folder, ('%s_%d%s'):format(stem, index, ext))
    end
    ensure(fs, LevelFiles.full(folder))
    local ok, writeMessage = fs.write(LevelFiles.full(relative), bytes)
    if not ok then
        return nil, tostring(writeMessage)
    end
    return relative
end

-- Deletes a file, or a folder with everything in it. Never the root itself.
function LevelFiles.delete(path, fs)
    fs = fs or katsa.filesystem
    path = LevelFiles.clean(path)
    if not path or path == '' then
        return false, 'The assets folder itself cannot be deleted'
    end
    if not removeAll(fs, LevelFiles.full(path)) then
        return false, 'Could not delete ' .. path
    end
    return true
end

-- A free `name` in `folder`: name, name_2, name_3 ... (the extension stays last).
local function freeName(fs, folder, name)
    local stem, ext = name:match('^(.*)(%.[^%.]+)$')
    stem, ext = stem or name, ext or ''
    local relative, index = LevelFiles.join(folder, name), 1
    while fs.getInfo(LevelFiles.full(relative)) do
        index = index + 1
        relative = LevelFiles.join(folder, ('%s_%d%s'):format(stem, index, ext))
    end
    return relative
end

local function copyAll(fs, from, to)
    if fs.getInfo(from, 'directory') then
        fs.createDirectory(to)
        for _, name in ipairs(fs.getDirectoryItems(from)) do
            if not copyAll(fs, from .. '/' .. name, to .. '/' .. name) then
                return false
            end
        end
        return true
    end
    local bytes = fs.read(from)
    return bytes ~= nil and fs.write(to, bytes) and true or false
end

local function inside(path, folder)
    return folder == path or folder:sub(1, #path + 1) == path .. '/'
end

-- Copies a file or folder into level folder `folder` under a free name (a copy in the same
-- folder becomes name_2). Returns the new relative path or nil, message.
function LevelFiles.copy(path, folder, fs)
    fs = fs or katsa.filesystem
    path, folder = LevelFiles.clean(path), LevelFiles.clean(folder)
    if not path or path == '' or not folder then
        return nil, 'Nothing to copy'
    end
    if inside(path, folder) and folder ~= LevelFiles.parent(path) then
        return nil, 'A folder cannot be copied into itself'
    end
    if not fs.getInfo(LevelFiles.full(path)) then
        return nil, path .. ' does not exist'
    end
    ensure(fs, LevelFiles.full(folder))
    local target = freeName(fs, folder, path:match('([^/]+)$'))
    if not copyAll(fs, LevelFiles.full(path), LevelFiles.full(target)) then
        return nil, 'Could not copy ' .. path
    end
    return target
end

-- Moves a file or folder into level folder `folder`. Returns the new relative path or nil,
-- message; a name already used there is refused (nothing is overwritten).
function LevelFiles.move(path, folder, fs)
    fs = fs or katsa.filesystem
    path, folder = LevelFiles.clean(path), LevelFiles.clean(folder)
    if not path or path == '' or not folder then
        return nil, 'Nothing to move'
    end
    if inside(path, folder) then
        return nil, 'A folder cannot be moved into itself'
    end
    local name = path:match('([^/]+)$')
    local target = LevelFiles.join(folder, name)
    if target == path then
        return path
    end
    if fs.getInfo(LevelFiles.full(target)) then
        return nil, name .. ' already exists in ' .. (folder == '' and 'the assets folder' or folder)
    end
    ensure(fs, LevelFiles.full(folder))
    local moved, message = fs.rename(LevelFiles.full(path), LevelFiles.full(target))
    if not moved then
        return nil, tostring(message or 'Move failed')
    end
    return target
end

return LevelFiles
