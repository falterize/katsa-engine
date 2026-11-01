local Paths = require('source.engine.persistence.paths')
local FileIO = require('source.engine.persistence.fileIO')

local Files = {}
Files.__index = Files

function Files.new(namespace, options)
    options = options or {}
    namespace = Paths.namespace(namespace)
    return setmetatable({
        root = 'saves/' .. namespace,
        legacyRoot = 'files/' .. namespace,
        fs = options.filesystem or katsa.filesystem,
        maxBytes = options.maxFileBytes or 64 * 1024 * 1024,
    }, Files)
end

function Files:path(relative)
    return self.root .. '/' .. Paths.relative(relative)
end

function Files:readPath(relative)
    relative = Paths.relative(relative)
    for _, root in ipairs({ self.root, self.legacyRoot }) do
        local path = root .. '/' .. relative
        if self.fs.getInfo(path, 'file') then
            return path, false
        end
        if self.fs.getInfo(path .. '.bak', 'file') then
            return path .. '.bak', true
        end
    end
end

function Files:read(relative)
    local ok, bytes, metadata = pcall(function()
        local path, recovered = self:readPath(relative)
        assert(path, 'Data file does not exist')
        local fs = self.fs
        local info = assert(fs.getInfo(path, 'file'))
        assert(self.maxBytes == 0 or info.size <= self.maxBytes, 'Data file exceeds the read limit')
        return assert(fs.read(path)), { path = path, recovered = recovered, bytes = info.size }
    end)
    if not ok then
        return nil, tostring(bytes)
    end
    return bytes, metadata
end

function Files:write(relative, bytes)
    local ok, result = pcall(function()
        local path = self:path(relative)
        if type(bytes) ~= 'string' then
            assert(
                type(bytes) == 'userdata' and bytes.typeOf and bytes:typeOf('Data'),
                'Data file content must be a string or LÖVE Data object'
            )
            bytes = bytes:getString()
        end
        assert(self.maxBytes == 0 or #bytes <= self.maxBytes, 'Data file exceeds the write limit')
        FileIO.publish(self.fs, path, bytes)
        return { path = path, bytes = #bytes }
    end)
    return ok and true or nil, ok and result or tostring(result)
end

function Files:exists(relative)
    return self:readPath(relative) ~= nil
end

function Files:remove(relative)
    local ok, failure = pcall(function()
        relative = Paths.relative(relative)
        for _, root in ipairs({ self.root, self.legacyRoot }) do
            local path = root .. '/' .. relative
            for _, name in ipairs({ path, path .. '.bak', path .. '.tmp' }) do
                if self.fs.getInfo(name) then
                    assert(self.fs.remove(name), 'Cannot remove data file')
                end
            end
        end
    end)
    return ok and true or nil, not ok and tostring(failure) or nil
end

function Files:list(directory, recursive)
    local ok, result = pcall(function()
        directory = Paths.relative(directory or '', true)
        local found, seen = {}, {}
        local function visit(root, relative)
            local path = root .. (relative == '' and '' or '/' .. relative)
            if not self.fs.getInfo(path, 'directory') then
                return
            end
            for _, name in ipairs(self.fs.getDirectoryItems(path)) do
                local item = relative == '' and name or relative .. '/' .. name
                if self.fs.getInfo(root .. '/' .. item, 'directory') then
                    if recursive then
                        visit(root, item)
                    end
                elseif not item:match('%.tmp$') then
                    item = item:gsub('%.bak$', '')
                    if not seen[item] then
                        found[#found + 1], seen[item] = item, true
                    end
                end
            end
        end
        visit(self.root, directory)
        visit(self.legacyRoot, directory)
        table.sort(found)
        return found
    end)
    if not ok then
        return nil, tostring(result)
    end
    return result
end

function Files:open(relative, mode)
    local ok, file = pcall(function()
        mode = mode or 'r'
        assert(mode == 'r' or mode == 'w' or mode == 'a', 'Use r, w or a file mode')
        local path = self:path(relative)
        if mode == 'r' then
            path = assert(self:readPath(relative), 'Data file does not exist')
        else
            assert(self.fs.createDirectory(path:match('^(.*)/')))
            if mode == 'a' and not self.fs.getInfo(path, 'file') then
                local previous = self:readPath(relative)
                if previous then
                    -- Preserve old bytes when appending to a legacy/recovered
                    -- file. Copy in chunks so large streams stay bounded.
                    local temporary = path .. '.tmp'
                    FileIO.copy(self.fs, previous, temporary)
                    assert(FileIO.rename(self.fs, temporary, path), 'Cannot import append source')
                end
            end
        end
        local handle = assert(self.fs.newFile(path))
        assert(handle:open(mode))
        return handle
    end)
    if not ok then
        return nil, tostring(file)
    end
    return file
end

function Files:createDirectory(directory)
    local ok, failure = pcall(function()
        directory = Paths.relative(directory or '', true)
        assert(self.fs.createDirectory(self.root .. (directory == '' and '' or '/' .. directory)))
    end)
    return ok and true or nil, not ok and tostring(failure) or nil
end

function Files:listDirectories(directory)
    local ok, result = pcall(function()
        directory = Paths.relative(directory or '', true)
        local found, seen = {}, {}
        for _, root in ipairs({ self.root, self.legacyRoot }) do
            local path = root .. (directory == '' and '' or '/' .. directory)
            if self.fs.getInfo(path, 'directory') then
                for _, name in ipairs(self.fs.getDirectoryItems(path)) do
                    if self.fs.getInfo(path .. '/' .. name, 'directory') and not seen[name] then
                        found[#found + 1], seen[name] = name, true
                    end
                end
            end
        end
        table.sort(found)
        return found
    end)
    if not ok then
        return nil, tostring(result)
    end
    return result
end

return Files
