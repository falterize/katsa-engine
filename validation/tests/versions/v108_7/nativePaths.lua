-- Native libraries load from folders with non-ASCII names (UTF-8 paths, Native.loadFile). On
-- Windows this takes the LoadLibraryW branch; elsewhere ffi.load reads UTF-8 directly.
local Module = {}

function Module.run(self)
    local Native = require('source.katsa.core.native')
    local source = Native.paths.Katsa
    local bytes = source and katsa.filesystem.read(source)
    if not bytes then
        -- The library was found through the loader's default path; nothing to copy.
        self:check(true, 'A library loads from a non-ASCII folder (skipped: no file path)')
        return
    end
    local folder = 'tmp/Папка игры'
    assert(katsa.filesystem.createDirectory(folder))
    local name = source:match('[^/\\]+$')
    assert(katsa.filesystem.write(folder .. '/' .. name, bytes))
    local path = katsa.filesystem.getSaveDirectory() .. '/' .. folder .. '/' .. name
    local ok, library = pcall(Native.loadFile, path)
    self:check(ok and library.katsa_version() >= 1, 'A library loads from a non-ASCII folder')
end

return Module
