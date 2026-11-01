local Tests = {}
Tests.__index = Tests

function Tests.new(manager)
    return setmetatable({ manager = manager }, Tests)
end

function Tests:update() end

function Tests:draw()
    if self.done then
        return
    end
    self.done = true
    local phase = os.getenv('KATSA_DATA_SESSION_PHASE')
    local data = self.manager.data:scope('validation-session-v1068', {
        version = phase == 'read' and 2 or 1,
        migrations = {
            [1] = function(value)
                value.upgraded = true
                return value
            end,
        },
    })
    if phase == 'write' then
        assert(data:remove('profile'))
        assert(data:save('profile', { marker = 1068, score = 17 }))
        assert(data:writeFile('payload.bin', 'persistent\0bytes'))
    else
        assert(phase == 'read', 'Select write/read data session phase')
        local profile, metadata = data:load('profile')
        assert(
            profile and profile.marker == 1068 and profile.score == 17 and profile.upgraded,
            'Persistent progress did not survive process/source replacement'
        )
        assert(metadata.migrated and metadata.version == 2, 'Updated schema migration did not run')
        assert(
            data:readFile('payload.bin') == 'persistent\0bytes',
            'Persistent binary file changed'
        )
        assert(data:remove('profile'))
        assert(data:removeFile('payload.bin'))
    end
    print('PASSED DATA SESSION ' .. phase .. ' ' .. data:directory())
    love.event.quit()
end

return Tests
