-- Stored as `__katsa/boot.lua` inside the runtime archive. The C host runs it first; it makes the
-- runtime modules (stored uncompressed under source/katsa/) loadable, then starts the game.
local host = katsa_host
local function searcher(name)
    if name:sub(1, 12) ~= 'source.katsa' then
        return nil
    end
    local base = name:gsub('%.', '/')
    for _, file in ipairs({ base .. '.lua', base .. '/init.lua' }) do
        local text = host.read(file)
        if text then
            return assert(loadstring(text, '@' .. file))
        end
    end
    return "\n\tno runtime module '" .. name .. "'"
end
table.insert(package.loaders, 2, searcher)

local dir = host.exe:match('^(.*)[/\\][^/\\]*$') or '.'
require('source.katsa.core.native').addDirectory(dir)
require('source.katsa.core.native').addDirectory(dir .. '/lib')
local Archive = require('source.katsa.core.archive')
local ok, archive = pcall(Archive.fromFile, host.exe, require('source.katsa.core.nativeLib'))
host.archive = ok and archive or nil
return require('source.katsa.host.boot').start(host)
