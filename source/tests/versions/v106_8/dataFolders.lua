local Data = require('source.engine.persistence.data')
local FileIO = require('source.engine.persistence.fileIO')
local Json = require('vendor.json')

local Tests = {}

function Tests.run(tester)
    local root = tester.manager.data:scope('validation-folders-v1068')
    local shooter = root:scope('shooter')
    local extra = shooter:scope('extra')
    local direct = root:scope('shooter/extra')
    for _, path in ipairs(root:listFiles('', true)) do
        assert(root:removeFile(path))
    end
    tester:check(
        extra.name == direct.name and extra.store.root == direct.store.root,
        'Chained scopes and slash-separated categories address the same directory'
    )
    tester:check(
        root.name == 'validation-folders-v1068'
            and extra:scopeDirectory()
                == love.filesystem.getSaveDirectory() .. '/saves/validation-folders-v1068/shooter/extra',
        'The scene data root selects top-level scopes without an implicit shared prefix'
    )
    assert(extra:write('fun.txt', 'Hello!'))
    assert(shooter:write('settings.txt', 'volume=0.8\n'))
    tester:check(
        direct:read('fun.txt') == 'Hello!' and root:read('shooter/settings.txt') == 'volume=0.8\n',
        'One read/write API stores original text in nested saves folders'
    )
    tester:check(
        love.filesystem.read('saves/' .. shooter.name .. '/settings.txt') == 'volume=0.8\n',
        'Raw and structured data use the same visible saves hierarchy'
    )
    assert(extra:write('progress.json', { score = 1 }))
    assert(extra:write('progress.json', { score = 2 }))
    local primary = 'saves/' .. extra.name .. '/progress.json'
    local envelope = Json.decode(assert(love.filesystem.read(primary)))
    tester:check(
        Json.decode(envelope.payload).data.score == 2 and direct:read('progress.json').score == 2,
        'An explicit JSON filename always contains the latest verified table'
    )
    tester:check(
        extra:exists('progress.json')
            and extra:exists('fun.txt')
            and not extra:exists('missing.txt'),
        'Unified existence checks cover tables, text and missing files'
    )
    local binary = '\0\255\1bytes'
    local bytes = love.data.newByteData(binary)
    assert(extra:write('payload.bin', bytes))
    bytes:release()
    tester:check(
        extra:read('payload.bin') == binary,
        'Unified binary writes preserve LÖVE Data bytes'
    )
    tester:check(
        not extra:write('table.txt', { score = 3 })
            and extra:write('table.txt', { score = 3 }, { format = 'json' })
            and extra:read('table.txt', { format = 'json' }).score == 3,
        'Nonstandard table extensions require an explicit matching format'
    )
    assert(extra:write('literal.json', '{"external":true}', { format = 'text' }))
    tester:check(
        extra:read('literal.json', { format = 'text' }) == '{"external":true}',
        'A format override can preserve an external JSON document as original text'
    )
    tester:check(
        not extra:write('../escape.txt', 'x')
            and not pcall(root.scope, root, '../outside')
            and not pcall(root.scope, root, 'C:/outside')
            and not pcall(root.scope, root, 'shooter//extra')
            and not pcall(root.scope, root, 'CON'),
        'Nested categories retain traversal, absolute-path and reserved-name protection'
    )
    local defaults = { nested = { score = 7 } }
    local first = assert(extra:read('new.json', { defaults = defaults }))
    first.nested.score = 99
    tester:check(
        extra:read('new.json', { defaults = defaults }).nested.score == 7,
        'Per-file defaults are copied without leaking edits into later loads'
    )
    tester:check(
        not extra:read('invalid.json', { version = 0 })
            and not extra:write('invalid.json', {}, { format = 'unknown' }),
        'Invalid per-file options return errors through the same read/write contract'
    )
    local fs = {}
    for key, value in pairs(love.filesystem) do
        fs[key] = value
    end
    local parent = Data.new(root.name, {
        filesystem = fs,
        maxFileBytes = 4,
        defaults = { parentOnly = true },
    })
    local child = parent:scope('limits')
    tester:check(
        child.store.fs == fs
            and not child:write('large.bin', '12345')
            and child:read('empty.json').parentOnly == nil,
        'Children inherit filesystem and limits without inheriting unrelated parent defaults'
    )
    assert(extra:write('versioned.json', { old = 8 }))
    local version = {
        version = 2,
        migrations = {
            [1] = function(value)
                return { score = value.old }
            end,
        },
    }
    local migrated, migration = extra:read('versioned.json', version)
    assert(extra:write('versioned.json', migrated, version))
    tester:check(
        migrated.score == 8
            and migration.migrated
            and not extra:read('versioned.json')
            and not extra:write('versioned.json', { score = 9 }),
        'Named documents retain migration and future-schema overwrite protection'
    )
    assert(love.filesystem.write(primary, 'damaged primary'))
    local recovered, recovery = extra:read('progress.json')
    tester:check(
        recovered.score == 1 and recovery.status == 'recovered',
        'A corrupt named primary recovers the previous verified backup'
    )
    fs.rename = function(source, target)
        if source:match('%.tmp$') then
            return nil, 'Injected document commit failure'
        end
        return FileIO.rename(love.filesystem, source, target)
    end
    local failing = Data.new(extra.name, { filesystem = fs })
    tester:check(
        not failing:write('progress.json', { score = 3 }) and extra:read('progress.json').score == 1,
        'A failed publish after recovery preserves the verified generation'
    )
    assert(extra:write('progress.json', { score = 3 }))
    tester:check(extra:read('progress.json').score == 3, 'A recovered document can be saved again')
    assert(love.filesystem.write(primary, 'broken'))
    assert(love.filesystem.write(primary .. '.bak', 'also broken'))
    tester:check(
        not extra:read('progress.json'),
        'Damaged documents fail instead of returning defaults'
    )
    assert(extra:delete('progress.json'))
    tester:check(
        not extra:exists('progress.json')
            and not love.filesystem.getInfo(primary .. '.bak')
            and not love.filesystem.getInfo(primary .. '.tmp'),
        'Unified JSON deletion removes primary, backup and abandoned temporary files'
    )

    local legacyRoot = 'files/' .. extra.name
    assert(love.filesystem.createDirectory(legacyRoot))
    assert(love.filesystem.write(legacyRoot .. '/legacy.txt', 'old'))
    tester:check(
        extra:read('legacy.txt') == 'old'
            and extra:filePath('legacy.txt') == legacyRoot .. '/legacy.txt',
        'Earlier raw files remain readable through their legacy storage location'
    )
    assert(extra:write('legacy.txt', 'new'))
    tester:check(
        extra:read('legacy.txt') == 'new'
            and love.filesystem.read(legacyRoot .. '/legacy.txt') == 'old',
        'New writes use saves without deleting or shadowing the latest data with legacy bytes'
    )
    local large = string.rep('x', 70000)
    assert(love.filesystem.write(legacyRoot .. '/append.txt', large))
    local stream = assert(extra:openFile('append.txt', 'a'))
    assert(stream:write('!'))
    assert(stream:close())
    tester:check(
        extra:read('append.txt') == large .. '!'
            and love.filesystem.read(legacyRoot .. '/append.txt') == large,
        'Appending imports a legacy file in bounded chunks and preserves its original'
    )
    assert(extra:delete('legacy.txt'))
    tester:check(
        not extra:exists('legacy.txt') and not love.filesystem.getInfo(legacyRoot .. '/legacy.txt'),
        'Deletion clears both locations so an old raw file cannot reappear'
    )
    assert(root:createDirectory('empty/category'))
    local directories = assert(root:listDirectories())
    tester:check(
        directories[1] == 'empty' and directories[2] == 'shooter',
        'Directory creation and sorted folder listings include empty categories'
    )
    local preferences = assert(extra:settings('compatibility.json', { defaults = { volume = 1 } }))
    preferences:set('volume', 0.25)
    assert(preferences:save())
    tester:check(
        extra:read('compatibility.json').volume == 0.25,
        'The optional old settings wrapper interoperates with the unified document API'
    )
    local Saves = require('source.game.scenes.starterGame.scripts.data.saves')
    assert(extra:save('legacy-progress', { score = 55 }))
    local imported = assert(Saves.read(extra, 'imported.json', 'legacy-progress'))
    tester:check(
        imported.score == 55
            and extra:read('imported.json').score == 55
            and extra:load('legacy-progress').score == 55,
        'Starter migration copies an old slot to a named document without deleting its source'
    )
    assert(extra:write('imported.json', { score = 80 }))
    tester:check(
        Saves.read(extra, 'imported.json', 'legacy-progress').score == 80,
        'An existing named document is never replaced by an older Starter slot'
    )
    for _, path in ipairs(root:listFiles('', true)) do
        assert(root:removeFile(path))
    end
    tester:check(
        #root:listFiles('', true) == 0,
        'Nested test data is removed without deleting categories'
    )
end

return Tests
