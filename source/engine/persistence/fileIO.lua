local FileIO = {}

function FileIO.rename(fs, source, target)
    if fs.rename then
        return fs.rename(source, target)
    end
    local directory = fs.getSaveDirectory() .. '/'
    return os.rename(directory .. source, directory .. target)
end

function FileIO.write(fs, path, bytes)
    local file = assert(fs.newFile(path))
    assert(file:open('w'))
    local written, failure = pcall(function()
        assert(file:write(bytes))
        assert(file:flush())
    end)
    local closed, closeError = file:close()
    assert(written, failure)
    assert(closed, closeError)
end

function FileIO.publish(fs, path, bytes, verify, preserveBackup)
    local existing = fs.getInfo(path)
    assert(not existing or existing.type == 'file', 'Data destination is not a file')
    assert(fs.createDirectory(path:match('^(.*)/')), 'Cannot create data directory')
    local temporary, backup = path .. '.tmp', path .. '.bak'
    FileIO.write(fs, temporary, bytes)
    if verify then
        verify(temporary)
    end
    if existing then
        if preserveBackup then
            -- Recovery may have selected the backup because the primary is bad.
            -- Never rotate that damaged primary over the last verified record.
            assert(fs.remove(path), 'Cannot replace damaged primary')
        else
            if fs.getInfo(backup) then
                assert(fs.remove(backup), 'Cannot replace previous backup')
            end
            assert(FileIO.rename(fs, path, backup), 'Cannot retain the previous data file')
        end
    end
    local committed, failure = FileIO.rename(fs, temporary, path)
    if not committed then
        if fs.getInfo(backup) and not fs.getInfo(path) then
            FileIO.rename(fs, backup, path)
        end
        error('Cannot commit data file: ' .. tostring(failure), 0)
    end
end

function FileIO.copy(fs, source, target)
    local input, output = assert(fs.newFile(source)), assert(fs.newFile(target))
    assert(input:open('r'))
    local ok, failure = pcall(function()
        assert(output:open('w'))
        while not input:isEOF() do
            local bytes = assert(input:read(65536))
            assert(output:write(bytes))
        end
        assert(output:flush())
    end)
    input:close()
    local closed, closeError = output:close()
    assert(ok, failure)
    assert(closed, closeError)
end

return FileIO
