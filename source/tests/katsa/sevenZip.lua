-- 7z packages: stored, LZMA and LZMA2 folders (built by tools/testing/makeSevenZip.py).
local FIXTURES = 'source/tests/fixtures/lifecycle/'

local function slurp(path)
    local file = io.open(path, 'rb')
    if not file then
        return nil
    end
    local data = file:read('*a')
    file:close()
    return data
end

return function(T)
    local Archive = require('source.katsa.core.archive')
    local expected = slurp(FIXTURES .. 'basic/main.lua')
    if not expected then
        return T.skip('sevenZip: fixtures are missing')
    end
    for _, name in ipairs({ 'basic', 'compressed', 'compressedLzma2' }) do
        local archive = Archive.fromString(slurp(FIXTURES .. name .. '.7z'), name .. '.7z')
        T.check(archive:read('main.lua') == expected, name .. ': main.lua matches the source')
        T.check(archive:read('scripts/ui/interface.lua') ~= nil, name .. ': nested files')
        T.check(archive:info('scripts').type == 'directory', name .. ': directories are listed')
        T.check(archive:read('missing.lua') == nil, name .. ': missing files return nil')
    end
end
