-- The packager must keep the runtime readable by the C host (STORE entries) and leave out
-- non-game folders, and the Android project template must reference files that exist.
local Module = {}

function Module.run(self)
    local dir = os.tmpname()
    os.remove(dir)
    os.execute('mkdir -p ' .. dir .. '/game/scenes/empty')
    io.open(dir .. '/game/main.lua', 'w'):close()
    local archive = dir .. '/game.katsa'
    local command = 'python3 tools/build/packageKatsa.py --source ' .. dir .. '/game --with-runtime'
    self:check(os.execute(command .. ' --output ' .. archive .. ' >/dev/null') == 0, 'the packager runs')

    local Archive = require('source.katsa.core.archive')
    local nativeLib = require('source.katsa.core.nativeLib')
    local ok, zip = pcall(Archive.fromFile, archive, nativeLib)
    self:check(ok and zip:has('main.lua'), 'the archive holds the game')
    self:check(ok and zip:has('__katsa/boot.lua') and zip:has('source/katsa/host/boot.lua'), 'the archive holds the runtime')
    local entry = ok and zip.files['__katsa/boot.lua']
    self:check(entry and entry.method == 0, 'runtime entries are stored without compression')
    local whole = dir .. '/whole.katsa'
    os.execute('python3 tools/build/packageKatsa.py --source . --output ' .. whole .. ' >/dev/null')
    local okWhole, project = pcall(Archive.fromFile, whole, nativeLib)
    self:check(okWhole and project:has('main.lua'), 'the repository packs as a game')
    self:check(okWhole and not project:has('android/prepare.py'), 'the android project folder is not packed')
    self:check(okWhole and not project:has('tools/native/build.py'), 'build tools are not packed')

    for _, path in ipairs({
        'android/prepare.py',
        'android/app/build.gradle',
        'android/app/src/main/AndroidManifest.xml',
        'android/app/src/main/cpp/CMakeLists.txt',
        'android/app/src/main/java/org/katsa/game/KatsaActivity.java',
    }) do
        local file = io.open(path, 'rb')
        self:check(file ~= nil, 'template file exists: ' .. path)
        if file then
            file:close()
        end
    end
    os.execute('rm -rf ' .. dir)
end

return Module
