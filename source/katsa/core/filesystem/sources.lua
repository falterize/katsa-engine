-- Read-only backends mounted by the virtual file system: a directory on disk or an archive.
local Lib = require('source.katsa.core.nativeLib')

local Sources = {}

-- A directory on disk, optionally rooted at a sub path. Read-only through this interface.
local DirectorySource = {}
DirectorySource.__index = DirectorySource

function DirectorySource.new(root)
    return setmetatable({ root = (root:gsub('\\', '/'):gsub('/+$', '')) }, DirectorySource)
end

function DirectorySource:real(path)
    return path == '' and self.root or (self.root .. '/' .. path)
end

function DirectorySource:info(path)
    local kind, size, modified = Lib.stat(self:real(path))
    if not kind then
        return nil
    end
    return { type = kind, size = kind == 'file' and size or 0, modtime = modified }
end

function DirectorySource:read(path)
    return Lib.read(self:real(path))
end

function DirectorySource:list(path)
    return Lib.list(self:real(path))
end

local ArchiveSource = {}
ArchiveSource.__index = ArchiveSource

function ArchiveSource.new(archive)
    return setmetatable({ archive = archive }, ArchiveSource)
end

function ArchiveSource:info(path)
    return self.archive:info(path)
end

function ArchiveSource:read(path)
    return self.archive:read(path)
end

function ArchiveSource:list(path)
    return self.archive:list(path)
end

Sources.Directory = DirectorySource
Sources.Archive = ArchiveSource

return Sources
