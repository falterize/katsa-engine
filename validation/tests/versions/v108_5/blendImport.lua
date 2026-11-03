-- .blend import runs Blender once, caches the GLB and prefers a shipped `<file>.blend.glb`. A fake
-- Blender executable (a shell script that copies a fixture GLB) stands in for the real program.
local ffi = require('ffi')
local Blend = require('source.engine.import.blend')
local Models = require('source.engine.import.models')

local Module = {}

function Module.run(self)
    if package.config:sub(1, 1) == '\\' then
        return
    end
    ffi.cdef('int setenv(const char* name, const char* value, int overwrite); int unsetenv(const char* name);')
    local fixture = 'validation/tests/fixtures/models/autoCollision.glb'
    -- The cache lives in the save directory and survives runs, so every run uses fresh contents.
    local salt = tostring(os.time()) .. tostring(os.clock())
    local save = katsa.filesystem.getSaveDirectory()
    local fake, calls = os.tmpname(), os.tmpname()
    local file = io.open(fake, 'w')
    file:write(('#!/bin/sh\necho run >> %s\nfor last; do :; done\ncp "$(pwd)/%s" "$last"\n'):format(calls, fixture))
    file:close()
    os.execute('chmod +x ' .. fake)
    local function runs()
        local log = io.open(calls, 'r')
        local text = log and log:read('*a') or ''
        if log then
            log:close()
        end
        return select(2, text:gsub('run', ''))
    end

    ffi.C.setenv('KATSA_BLENDER', '/nonexistent/blender', 1)
    local ok, message = pcall(Blend.convert, 'blend-test/never-created.blend')
    self:check(not ok, 'a missing .blend file is an error')
    assert(katsa.filesystem.createDirectory('blend-test'))
    assert(katsa.filesystem.write('blend-test/a.blend', 'BLENDER-v400 first ' .. salt))
    ok, message = pcall(Blend.convert, 'blend-test/a.blend')
    self:check(not ok and tostring(message):find('missing file', 1, true), 'a bad KATSA_BLENDER is reported')

    ffi.C.setenv('KATSA_BLENDER', fake, 1)
    local model = Models.load('blend-test/a.blend', self.manager.resources:scope())
    self:check(runs() == 1 and #model.parts == 4, 'Blender runs once and the GLB loads (4 meshes)')
    Blend.convert('blend-test/a.blend')
    self:check(runs() == 1, 'the converted GLB is cached by content')

    assert(katsa.filesystem.write('blend-test/a.blend', 'BLENDER-v400 changed ' .. salt))
    Blend.convert('blend-test/a.blend')
    self:check(runs() == 2, 'a changed .blend converts again')

    assert(katsa.filesystem.write('blend-test/b.blend', 'BLENDER-v400 shipped ' .. salt))
    local glb = assert(katsa.filesystem.read(fixture))
    assert(katsa.filesystem.write('blend-test/b.blend.glb', glb))
    self:check(Blend.convert('blend-test/b.blend') == 'blend-test/b.blend.glb' and runs() == 2,
        'a shipped .blend.glb needs no Blender')

    assert(katsa.filesystem.write('blend-test/c.blend', 'not a blend file'))
    ok, message = pcall(Blend.convert, 'blend-test/c.blend')
    self:check(not ok and tostring(message):find('Not a .blend', 1, true), 'other files are rejected')
    self:check(Models.supports('x.blend') and Models.supports('x.BLEND'), 'the importer registry knows .blend')

    ffi.C.unsetenv('KATSA_BLENDER')
    ffi.C.setenv('BLENDER', '', 1)
    os.remove(fake)
    os.remove(calls)
    for _, name in ipairs({ 'a.blend', 'b.blend', 'b.blend.glb', 'c.blend' }) do
        katsa.filesystem.remove('blend-test/' .. name)
    end
end

return Module
