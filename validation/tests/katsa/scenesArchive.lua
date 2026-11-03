-- A packed game holds many scenes; the virtual filesystem lists and loads all of them, both from a
-- plain .katsa and from an archive appended to another file (fused executable).
return function(T)
    local dir = os.tmpname()
    os.remove(dir)
    os.execute('mkdir -p ' .. dir .. '/game/scenes/empty')
    for i = 1, 60 do
        local scene = ('%s/game/scenes/s%02d'):format(dir, i)
        os.execute('mkdir -p ' .. scene)
        local f = io.open(scene .. '/init.lua', 'w')
        f:write(('return { id = %d }'):format(i))
        f:close()
    end
    io.open(dir .. '/game/main.lua', 'w'):close()
    local pack = 'python3 tools/build/packageKatsa.py --source ' .. dir .. '/game '
    os.execute(pack .. '--output ' .. dir .. '/g.katsa >/dev/null')
    local host, fused = dir .. '/host', dir .. '/fused'
    local command = 'echo prefix > ' .. host .. '; ' .. pack .. '--host ' .. host
    os.execute(command .. ' --output ' .. fused .. ' >/dev/null')

    local native = require('source.katsa.core.native')
    native.addDirectory('build/native/' .. ({ Windows = 'windows', Linux = 'linux', OSX = 'macos' })[native.os()])
    for _, name in ipairs({ 'g.katsa', 'fused' }) do
        local FS = package.loaded['source.katsa.core.filesystem']
        package.loaded['source.katsa.core.filesystem'] = nil
        FS = require('source.katsa.core.filesystem')
        FS.setSource(dir .. '/' .. name, name == 'fused')
        local items = FS.getDirectoryItems('scenes')
        T.check(#items == 61, name .. ': 60 scenes and an empty folder are listed')
        local sum = 0
        for _, item in ipairs(items) do
            if FS.getInfo('scenes/' .. item .. '/init.lua', 'file') then
                sum = sum + assert(FS.load('scenes/' .. item .. '/init.lua'))().id
            end
        end
        T.check(sum == 1830, name .. ': every scene loads from the archive')
    end
    os.execute('rm -rf ' .. dir)
end
