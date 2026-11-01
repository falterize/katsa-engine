local Data = require('source.engine.persistence.data')
local FileIO = require('source.engine.persistence.fileIO')

local Tests = {}

function Tests.run(tester)
    local shared = tester.manager.data:scope('validation-shared-v1068', {
        defaults = { score = 0 },
    })
    assert(shared:remove('progress'))
    assert(shared:save('progress', { score = 42, flags = { unlocked = true } }))
    local restarted = Data.new('validation-shared-v1068')
    local loaded = assert(restarted:load('progress'))
    tester:check(
        loaded.score == 42 and loaded.flags.unlocked,
        'A fresh data service reads committed data from another scene or application session'
    )
    tester:check(
        shared:directory() == love.filesystem.getSaveDirectory()
            and shared:directory() ~= love.filesystem.getSource(),
        'Persistent data lives in the application save directory outside the replaceable game source'
    )
    local updated = Data.new('validation-shared-v1068', {
        version = 2,
        migrations = {
            [1] = function(value)
                value.level = 1
                return value
            end,
        },
    })
    local migrated, metadata = updated:load('progress')
    tester:check(
        migrated.score == 42 and migrated.level == 1 and metadata.migrated,
        'Updated game code can migrate the same persistent slot without changing its identity'
    )
    local isolated = Data.new('validation-isolated-v1068', { defaults = { score = -1 } })
    tester:check(
        isolated:load('progress').score == -1,
        'Different named data scopes never share a progress slot'
    )
    assert(shared:remove('progress'))

    local files = Data.new('validation-files-v1068', { maxFileBytes = 128 })
    for _, path in ipairs({
        'profiles/player.bin',
        'text/config.ini',
        'stream/log.txt',
        '.metadata',
    }) do
        assert(files:removeFile(path))
    end
    local binary = '\0\255\1saved\0bytes\n'
    tester:check(
        files:writeFile('profiles/player.bin', binary),
        'Binary files keep their original bytes and extension'
    )
    tester:check(
        Data.new('validation-files-v1068'):readFile('profiles/player.bin') == binary,
        'File data is shared across independent service instances'
    )
    tester:check(
        files:writeFile('text/config.ini', 'volume=0.5\n')
            and files:readFile('text/config.ini') == 'volume=0.5\n',
        'Text files round-trip without JSON wrapping'
    )
    local bytes = love.data.newByteData('revision-2\0')
    assert(files:writeFile('profiles/player.bin', bytes))
    bytes:release()
    tester:check(
        files:readFile('profiles/player.bin') == 'revision-2\0',
        'LÖVE Data objects can be written as raw files'
    )
    local primary = files:filePath('profiles/player.bin')
    tester:check(
        not files:writeFile('profiles', 'not a directory')
            and files:fileExists('profiles/player.bin'),
        'File writes cannot replace a data directory'
    )
    assert(love.filesystem.remove(primary))
    local recovered, recovery = files:readFile('profiles/player.bin')
    tester:check(
        recovered == binary and recovery.recovered and files:fileExists('profiles/player.bin'),
        'An interrupted raw-file publication can read the retained backup'
    )
    assert(files:writeFile('profiles/player.bin', 'committed'))
    local fs = {}
    for key, value in pairs(love.filesystem) do
        fs[key] = value
    end
    fs.rename = function(source, target)
        if source:match('%.tmp$') then
            return nil, 'Injected raw-file commit failure'
        end
        return FileIO.rename(love.filesystem, source, target)
    end
    local failing = Data.new('validation-files-v1068', { filesystem = fs })
    tester:check(
        not failing:writeFile('profiles/player.bin', 'uncommitted')
            and files:readFile('profiles/player.bin') == 'committed',
        'A failed raw-file commit restores the existing published file'
    )
    local stream = assert(files:openFile('stream/log.txt', 'w'))
    assert(stream:write('first\n'))
    assert(stream:close())
    stream = assert(files:openFile('stream/log.txt', 'a'))
    assert(stream:write('second\n'))
    assert(stream:flush())
    assert(stream:close())
    tester:check(
        files:readFile('stream/log.txt') == 'first\nsecond\n',
        'Streaming handles support explicit write, append, flush and close'
    )
    assert(files:writeFile('.metadata', 'ok'))
    local listing = assert(files:listFiles('', true))
    tester:check(
        #listing == 4 and listing[1] == '.metadata',
        'Sorted recursive listings hide temporary files and deduplicate backup generations'
    )
    tester:check(
        not files:writeFile('../escape.bin', 'x')
            and not files:writeFile('C:/escape.bin', 'x')
            and not files:writeFile('CON.txt', 'x')
            and not files:writeFile('file.BAK', 'x'),
        'File paths reject traversal, absolute paths, reserved devices and recovery names'
    )
    tester:check(
        not files:writeFile('oversized.bin', string.rep('x', 129)),
        'Whole-file operations enforce their configured memory limit'
    )
    for _, path in ipairs(listing) do
        assert(files:removeFile(path))
    end
    tester:check(
        #files:listFiles('', true) == 0 and not files:fileExists('profiles/player.bin'),
        'Explicit removal clears raw data and companion recovery files'
    )
end

return Tests
