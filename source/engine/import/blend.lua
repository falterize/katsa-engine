-- Imports .blend files the way Godot does: the installed Blender converts them to GLB, the GLB
-- importer reads the result.
--   1. `<file>.blend.glb` beside the file wins (made at packaging time, see
--      tools/build/packageKatsa.py --convert-blend), so shipped games need no Blender.
--   2. Otherwise a cached conversion in the save directory (`blend-cache/<fingerprint>.glb`).
--   3. Otherwise Blender runs once (`KATSA_BLENDER` / `BLENDER`, PATH, or its usual install folders).
-- Not available on Android/iOS: convert at packaging time there.
local Fingerprint = require('source.engine.core.fingerprint')

local Blend = {}

local SCRIPT = 'source/engine/import/blendExport.py'
local CACHE = 'blend-cache'

local function isWindows()
    return package.config:sub(1, 1) == '\\'
end

local function exists(path)
    local file = io.open(path, 'rb')
    if file then
        file:close()
        return true
    end
    return false
end

local function capture(command)
    local pipe = io.popen(command, 'r')
    if not pipe then
        return nil
    end
    local text = pipe:read('*a')
    pipe:close()
    return text
end

local function newestWindowsInstall()
    local roots = { 'C:\\Program Files\\Blender Foundation', 'C:\\Program Files (x86)\\Blender Foundation' }
    local best
    for _, root in ipairs(roots) do
        local listing = capture('dir /b /ad "' .. root .. '" 2>nul') or ''
        for folder in listing:gmatch('[^\r\n]+') do
            local candidate = root .. '\\' .. folder .. '\\blender.exe'
            if exists(candidate) and (not best or candidate > best) then
                best = candidate
            end
        end
    end
    return best
end

-- Returns the Blender executable path, or nil plus a message listing what was tried.
function Blend.find()
    local configured = os.getenv('KATSA_BLENDER') or os.getenv('BLENDER')
    if configured and configured ~= '' then
        if exists(configured) then
            return configured
        end
        return nil, 'KATSA_BLENDER points to a missing file: ' .. configured
    end
    if isWindows() then
        local found = newestWindowsInstall()
        if found then
            return found
        end
        local onPath = (capture('where blender 2>nul') or ''):match('[^\r\n]+')
        if onPath then
            return onPath
        end
    else
        local onPath = (capture('command -v blender 2>/dev/null') or ''):match('[^\r\n]+')
        if onPath then
            return onPath
        end
        for _, candidate in ipairs({
            '/Applications/Blender.app/Contents/MacOS/Blender',
            '/snap/bin/blender',
            '/usr/local/bin/blender',
        }) do
            if exists(candidate) then
                return candidate
            end
        end
    end
    return nil, 'Blender was not found. Install Blender 3.6+ or set KATSA_BLENDER to its executable.'
end

local function quote(value)
    return '"' .. value:gsub('"', '\\"') .. '"'
end

local function run(blender, blendFile, script, output)
    local command = table.concat({
        quote(blender),
        '--background --factory-startup --python-exit-code 1',
        quote(blendFile),
        '--python',
        quote(script),
        '--',
        quote(output),
    }, ' ')
    -- cmd.exe strips the outer quotes of a command line, so Windows needs one more pair.
    local status = os.execute(isWindows() and ('"' .. command .. '"') or command)
    return status == 0 or status == true
end

local function cacheFile(path, bytes)
    local save = katsa.filesystem.getSaveDirectory()
    assert(katsa.filesystem.createDirectory(CACHE))
    local key = Fingerprint.of(bytes)
    return CACHE .. '/' .. key .. '.glb', save .. '/' .. CACHE .. '/' .. key
end

-- Returns a virtual-filesystem path of the GLB for a .blend, converting if needed.
function Blend.convert(path)
    local sibling = path .. '.glb'
    if katsa.filesystem.getInfo(sibling, 'file') then
        return sibling
    end
    local bytes = assert(katsa.filesystem.read(path), 'Missing blend file: ' .. path)
    -- Plain, gzip-compressed (\31\139) or zstd-compressed (\40\181\47\253) blend files.
    local magic = bytes:sub(1, 7)
    assert(
        magic == 'BLENDER' or magic:sub(1, 2) == '\31\139' or magic:sub(1, 4) == '\40\181\47\253',
        'Not a .blend file: ' .. path
    )
    local virtual, absolute = cacheFile(path, bytes)
    if katsa.filesystem.getInfo(virtual, 'file') then
        return virtual
    end
    local blender, why = Blend.find()
    if not blender then
        error(why .. ' (Shipped games convert at packaging time: packageKatsa.py --convert-blend.)')
    end
    -- Blender reads real files, so a .blend that lives in an archive is extracted first.
    assert(katsa.filesystem.write(CACHE .. '/' .. Fingerprint.of(bytes) .. '.blend', bytes))
    assert(katsa.filesystem.write(CACHE .. '/export.py', assert(katsa.filesystem.read(SCRIPT))))
    local save = katsa.filesystem.getSaveDirectory()
    print('Converting ' .. path .. ' with Blender (first import only)...')
    local ok = run(blender, absolute .. '.blend', save .. '/' .. CACHE .. '/export.py', absolute .. '.glb')
    assert(ok and katsa.filesystem.getInfo(virtual, 'file'),
        'Blender could not convert ' .. path .. '; run it by hand with tools/import/blendToGlb.py to see why')
    return virtual
end

function Blend.load(path, resources)
    return require('source.engine.import.glb').load(Blend.convert(path), resources)
end

return Blend
