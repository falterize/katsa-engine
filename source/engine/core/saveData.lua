local SaveData = { identity = 'katsa-engine', legacyIdentity = 'katsa-sbox-v73' }
local marker = '.legacy-save-migrated'

local function collectDirectory(fs, path, root, files)
    for _, name in ipairs(fs.getDirectoryItems(path)) do
        assert(name ~= '.' and name ~= '..' and not name:find('[/\\]'), 'Invalid save filename')
        local relative = path == '' and name or path .. '/' .. name
        -- The virtual root also contains game assets. Only collect the old save mount.
        if fs.getRealDirectory(relative) == root then
            local info = assert(fs.getInfo(relative), 'Cannot inspect legacy save: ' .. relative)
            if info.type == 'directory' then
                files[#files + 1] = { path = relative, directory = true }
                collectDirectory(fs, relative, root, files)
            elseif info.type == 'file' then
                files[#files + 1] = { path = relative, data = assert(fs.read(relative)) }
            end
        end
    end
end

function SaveData.migrate(fs)
    fs = fs or katsa.filesystem
    if fs.getIdentity() ~= SaveData.identity or fs.getInfo(marker) then
        return true, 0
    end
    -- LÖVE restricts mounting arbitrary absolute folders. Switch identities only
    -- during collection and restore the destination even if reading fails.
    local files = {}
    fs.setIdentity(SaveData.legacyIdentity)
    local ok, message = pcall(collectDirectory, fs, '', fs.getSaveDirectory(), files)
    fs.setIdentity(SaveData.identity)
    if not ok then
        return false, message
    end
    local copied = 0
    for _, file in ipairs(files) do
        local existing = fs.getInfo(file.path)
        if file.directory and not existing then
            ok, message = fs.createDirectory(file.path)
        elseif not file.directory and not existing then
            ok, message = fs.write(file.path, file.data)
            if ok then
                copied = copied + 1
            end
        end
        if not ok then
            return false, message
        end
    end
    ok, message = fs.write(marker, 'Legacy data copied without overwriting existing files.\n')
    return ok, ok and copied or message
end

return SaveData
