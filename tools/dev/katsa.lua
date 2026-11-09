-- Development launcher: run a game with the Lua sources in this repository, without building a host.
--   luajit tools/dev/katsa.lua <game folder | game.katsa | game.zip>
-- Run it from the repository root so `source.katsa.*` resolves.
package.path = './?.lua;./?/init.lua;' .. package.path
local args = {}
for i = 1, #arg do
    args[i] = arg[i]
end
local Native = require('source.katsa.core.native')
local target = ({ Windows = 'windows', Linux = 'linux', OSX = 'macos', Android = 'android' })[Native.os()]
Native.addDirectory('native/build/' .. target)
local boot = require('source.katsa.host.boot')
local status = boot.start({ exe = arg[-1] or 'luajit', args = args })
os.exit(status)
