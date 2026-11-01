-- katsa.filesystem: virtual file system over directories and ZIP-style archives
-- (.katsa, .love, .zip, or an archive appended to the executable) plus a writable save directory.
-- It follows love.filesystem: reads search the save directory first and then the mounted sources;
-- writes go only to the save directory; paths use '/' and may not contain '..'.
local Archive = require('source.katsa.core.archive')
local Native = require('source.katsa.core.native')
local Lib = require('source.katsa.core.nativeLib')
local Paths = require('source.katsa.core.filesystem.paths')
local Sources = require('source.katsa.core.filesystem.sources')
local FileData = require('source.katsa.core.filesystem.fileData')
local File = require('source.katsa.core.filesystem.file')

local normalize = Paths.normalize
local DirectorySource, ArchiveSource = Sources.Directory, Sources.Archive

local FS = {}

local state = {
    identity = 'katsa',
    saveRoot = nil,
    source = nil,
    sourceKind = nil,
    mounts = {},
    fused = false,
}

-- Mounts `source` at `point` ('' is the root). Paths below the mount point resolve into it.
local function resolve(mount, path)
    if mount.point == '' then
        return path
    end
    if path == mount.point then
        return ''
    end
    local prefix = mount.point .. '/'
    if path:sub(1, #prefix) == prefix then
        return path:sub(#prefix + 1)
    end
    return nil
end

-- A mount point such as 'a/b' makes 'a' and 'a/b' appear as directories even if no file exists
-- there.
local function intermediate(mount, path)
    if mount.point == '' then
        return nil
    end
    if path == '' then
        return mount.point:match('^[^/]+')
    end
    local prefix = path .. '/'
    if mount.point:sub(1, #prefix) == prefix then
        return mount.point:sub(#prefix + 1):match('^[^/]+')
    end
    return nil
end

local function saveReal(path)
    assert(state.saveRoot or state.saveFull, 'Save directory is not initialised')
    local base = state.saveFull or (state.saveRoot .. '/' .. state.identity)
    return path == '' and base or (base .. '/' .. path)
end

-- Uses `directory` itself as the save directory (the platform's per-app data path).
function FS.setSaveDirectory(directory)
    state.saveFull = (directory:gsub('\\', '/'):gsub('/+$', ''))
    state.saveRoot = state.saveRoot or state.saveFull
end

function FS.setSaveRoot(directory)
    state.saveRoot = (directory:gsub('\\', '/'):gsub('/+$', ''))
end

-- Default per-user data directory when the platform did not supply one (SDL_GetPrefPath).
function FS.defaultSaveRoot()
    local name = Native.os()
    if name == 'Windows' then
        return (os.getenv('APPDATA') or '.') .. '/Katsa'
    elseif name == 'OSX' then
        return (os.getenv('HOME') or '.') .. '/Library/Application Support/Katsa'
    end
    local data = os.getenv('XDG_DATA_HOME')
    if not data or data == '' then
        data = (os.getenv('HOME') or '.') .. '/.local/share'
    end
    return data .. '/katsa'
end

function FS.setIdentity(identity)
    assert(type(identity) == 'string' and identity ~= '', 'Identity must be a non-empty string')
    state.identity = identity
    state.saveFull = nil
end

function FS.getIdentity()
    return state.identity
end

function FS.getSaveDirectory()
    if not state.saveRoot and not state.saveFull then
        FS.setSaveRoot(FS.defaultSaveRoot())
    end
    return saveReal('')
end

function FS.getSource()
    return state.source
end

function FS.getWorkingDirectory()
    return (os.getenv('PWD') or '.')
end

function FS.isFused()
    return state.fused
end

-- Sets the game source: a directory, an archive file, or an Archive object (with a label).
-- `fused` marks an archive appended to the running executable.
function FS.setSource(source, fused)
    for i = #state.mounts, 1, -1 do
        if state.mounts[i].isSource then
            table.remove(state.mounts, i)
        end
    end
    local backend
    if type(source) == 'table' then
        backend = ArchiveSource.new(source)
        state.source = source.label
        state.sourceKind = 'archive'
    else
        local kind = Lib.stat(source)
        assert(kind, 'Game source not found: ' .. tostring(source))
        if kind == 'directory' then
            backend = DirectorySource.new(source)
            state.sourceKind = 'directory'
        else
            backend = ArchiveSource.new(Archive.fromFile(source, Lib))
            state.sourceKind = 'archive'
        end
        state.source = source
    end
    state.fused = fused == true
    table.insert(state.mounts, { point = '', backend = backend, isSource = true })
end

function FS.getSourceKind()
    return state.sourceKind
end

local function searchPlan(path)
    local plan = {}
    for _, mount in ipairs(state.mounts) do
        plan[#plan + 1] = mount
    end
    return plan
end

local function saveInfo(path)
    if not state.saveRoot then
        return nil
    end
    local kind, size, modified = Lib.stat(saveReal(path))
    if not kind then
        return nil
    end
    return { type = kind, size = kind == 'file' and size or 0, modtime = modified }
end

function FS.getInfo(path, filter, info)
    path = normalize(path)
    local result = saveInfo(path)
    if not result then
        for _, mount in ipairs(searchPlan(path)) do
            local inner = resolve(mount, path)
            if inner then
                local found = mount.backend:info(inner)
                if found then
                    result = found
                    result.readonly = true
                    break
                end
            elseif intermediate(mount, path) then
                result = { type = 'directory', size = 0, modtime = 0, readonly = true }
                break
            end
        end
    end
    if not result then
        return nil
    end
    if type(filter) == 'string' and result.type ~= filter then
        return nil
    end
    if type(filter) == 'table' then
        info = filter
    end
    if type(info) == 'table' then
        info.type = result.type
        info.size = result.size
        info.modtime = result.modtime
        info.readonly = result.readonly
        return info
    end
    return result
end

function FS.exists(path)
    return FS.getInfo(path) ~= nil
end

function FS.isFile(path)
    return FS.getInfo(path, 'file') ~= nil
end

function FS.isDirectory(path)
    return FS.getInfo(path, 'directory') ~= nil
end

function FS.read(path, size)
    path = normalize(path)
    local data
    if state.saveRoot then
        data = Lib.read(saveReal(path))
    end
    if not data then
        for _, mount in ipairs(searchPlan(path)) do
            local inner = resolve(mount, path)
            if inner then
                data = mount.backend:read(inner)
                if data then
                    break
                end
            end
        end
    end
    if not data then
        return nil, 'Could not open file ' .. path .. '. Does not exist.'
    end
    if size then
        data = data:sub(1, size)
    end
    return data, #data
end

function FS.write(path, data, size)
    path = normalize(path)
    assert(path ~= '', 'Invalid file name')
    if type(data) == 'table' and data.getString then
        data = data:getString()
    end
    if size then
        data = data:sub(1, size)
    end
    FS.getSaveDirectory()
    local parent = path:match('^(.*)/[^/]+$')
    if parent then
        Lib.mkdir(saveReal(parent))
    else
        Lib.mkdir(saveReal(''))
    end
    if not Lib.write(saveReal(path), data) then
        return false, 'Could not write file ' .. path
    end
    return true
end

function FS.append(path, data, size)
    path = normalize(path)
    if size then
        data = data:sub(1, size)
    end
    FS.getSaveDirectory()
    local parent = path:match('^(.*)/[^/]+$')
    Lib.mkdir(saveReal(parent or ''))
    if not Lib.write(saveReal(path), data, true) then
        return false, 'Could not write file ' .. path
    end
    return true
end

function FS.createDirectory(path)
    path = normalize(path)
    FS.getSaveDirectory()
    return Lib.mkdir(saveReal(path))
end

function FS.remove(path)
    path = normalize(path)
    assert(path ~= '', 'Invalid path')
    if not state.saveRoot then
        return false
    end
    return Lib.remove(saveReal(path))
end

function FS.getDirectoryItems(path)
    path = normalize(path)
    local seen, names = {}, {}
    local function add(list)
        for _, name in ipairs(list or {}) do
            if not seen[name] then
                seen[name] = true
                names[#names + 1] = name
            end
        end
    end
    if state.saveRoot then
        add(Lib.list(saveReal(path)))
    end
    for _, mount in ipairs(searchPlan(path)) do
        local inner = resolve(mount, path)
        if inner then
            add(mount.backend:list(inner))
        else
            add({ intermediate(mount, path) })
        end
    end
    table.sort(names)
    return names
end

function FS.lines(path)
    local data = assert(FS.read(path))
    return data:gmatch('([^\r\n]*)\r?\n?')
end

function FS.load(path)
    local data, message = FS.read(path)
    if not data then
        return nil, message
    end
    return loadstring(data, '@' .. normalize(path))
end

-- Hooks File objects use to reach the save directory and the mounted sources.
local fileResolver = {
    realPath = function(path, forWriting)
        if forWriting then
            FS.getSaveDirectory()
            return saveReal(path)
        end
        if state.saveRoot and Lib.stat(saveReal(path)) == 'file' then
            return saveReal(path)
        end
        return nil
    end,
    readVirtual = function(path)
        return FS.read(path)
    end,
    size = function(path)
        local info = FS.getInfo(path, 'file')
        return info and info.size
    end,
}

function FS.newFile(path, mode)
    local file = File.new(normalize(path), fileResolver)
    if mode then
        local ok, message = file:open(mode)
        if not ok then
            return nil, message
        end
    end
    return file
end

-- Renames a file inside the save directory.
function FS.rename(source, target)
    source, target = normalize(source), normalize(target)
    if not state.saveRoot then
        return false, 'No save directory'
    end
    local ok, message = os.rename(saveReal(source), saveReal(target))
    return ok and true or false, message
end

-- Directory or archive that provides `path`: the save directory first, then the mounts.
function FS.getRealDirectory(path)
    path = normalize(path)
    if state.saveRoot and Lib.stat(saveReal(path)) then
        return saveReal('')
    end
    for _, mount in ipairs(searchPlan(path)) do
        local inner = resolve(mount, path)
        if inner and mount.backend:info(inner) then
            return mount.backend.root or mount.key or state.source
        end
    end
    return nil
end

-- newFileData(contents, name) or newFileData(path)
function FS.newFileData(contents, name)
    if name == nil then
        local data, message = FS.read(contents)
        if not data then
            -- Real files outside the virtual tree (dropped files) are readable by absolute path.
            data = Lib.read(contents)
        end
        if not data then
            return nil, message or ('Could not read ' .. tostring(contents))
        end
        return FileData.new(data, contents:match('[^/\\]+$'))
    end
    if type(contents) == 'table' and contents.getString then
        contents = contents:getString()
    end
    return FileData.new(contents, name)
end

-- Mounts an archive: a virtual path, a FileData, or a real file path.
function FS.mount(archive, mountpoint, appendToPath)
    local key = archive
    local data
    if type(archive) == 'table' and archive.getString then
        data = archive:getString()
    elseif type(archive) == 'string' then
        local virtual = FS.getInfo(normalize(archive), 'file') and FS.read(archive)
        data = virtual or Lib.read(archive)
        if not data then
            return false, 'Could not mount ' .. archive
        end
        local kind = Lib.stat(archive)
        if not virtual and kind == 'directory' then
            data = nil
        end
    else
        return false, 'Invalid mount source'
    end
    local backend
    if data then
        local ok, result = pcall(Archive.fromString, data, tostring(archive))
        if not ok then
            return false, tostring(result)
        end
        backend = ArchiveSource.new(result)
    else
        backend = DirectorySource.new(archive)
    end
    local mount = { point = normalize(mountpoint or ''), backend = backend, key = key }
    if appendToPath then
        state.mounts[#state.mounts + 1] = mount
    else
        table.insert(state.mounts, 1, mount)
    end
    return true
end

function FS.unmount(archive)
    for i = #state.mounts, 1, -1 do
        if state.mounts[i].key == archive and not state.mounts[i].isSource then
            table.remove(state.mounts, i)
            return true
        end
    end
    return false
end

-- Debugging helper: describes the active search path.
function FS.getSearchPath()
    local list = {}
    for _, mount in ipairs(state.mounts) do
        local point = mount.point == '' and '/' or mount.point
        list[#list + 1] = point .. ' <- ' .. tostring(mount.key or state.source)
    end
    return list
end

return FS
