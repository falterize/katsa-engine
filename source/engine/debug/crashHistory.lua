local History = {}

function History.write(filesystem, traceback)
    -- Fixed slots make retention deterministic even when several errors share a timestamp.
    local previous = filesystem.read and filesystem.read('last-error.txt')
    filesystem.write('last-error.txt', traceback)
    if not filesystem.createDirectory or not filesystem.read then
        return
    end
    assert(filesystem.createDirectory('crashes'))
    if previous and not filesystem.read('crashes/crash-01.txt') then
        assert(filesystem.write('crashes/crash-01.txt', previous))
    end
    for index = 9, 1, -1 do
        local old = filesystem.read(string.format('crashes/crash-%02d.txt', index))
        if old then
            assert(filesystem.write(string.format('crashes/crash-%02d.txt', index + 1), old))
        end
    end
    assert(
        filesystem.write(
            'crashes/crash-01.txt',
            os.date('!%Y-%m-%dT%H:%M:%SZ') .. '\n\n' .. traceback
        )
    )
end

return History
