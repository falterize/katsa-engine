local Game = require('source.game.runtime.game')
local UI = require('source.engine.ui')
local SaveData = require('source.engine.core.saveData')
local Tests = {}
Tests.__index = Tests

function Tests.new(manager)
    io.stdout:setvbuf('no')
    love.errorhandler = function(message)
        print('FAILED v106.2 ' .. tostring(message))
        os.exit(1)
    end
    if os.getenv('KATSA_TEST_INTERPRETER') == '1' then
        jit.off()
        jit.flush()
    end
    return setmetatable({ manager = manager, count = 0 }, Tests)
end

function Tests:update() end

function Tests:check(value, label)
    assert(value, label)
    self.count = self.count + 1
    print('PASS v106.2', label)
end

function Tests:migration()
    local identity = SaveData.identity
    local old = { ['stats-logs'] = true, ['stats-logs/user.csv'] = 'recorded', conflict = 'old' }
    local current = { conflict = 'new' }
    local fs = {}
    local function storage()
        return identity == SaveData.identity and current or old
    end
    fs.getIdentity = function()
        return identity
    end
    fs.setIdentity = function(value)
        identity = value
    end
    fs.getSaveDirectory = function()
        return '/saves/' .. identity
    end
    fs.getInfo = function(path)
        local value = storage()[path]
        return value ~= nil and { type = value == true and 'directory' or 'file' } or nil
    end
    fs.getDirectoryItems = function(path)
        local result = {}
        local prefix = path == '' and '' or path .. '/'
        for name in pairs(storage()) do
            if name:sub(1, #prefix) == prefix and not name:sub(#prefix + 1):find('/') then
                result[#result + 1] = name:sub(#prefix + 1)
            end
        end
        if path == '' then
            result[#result + 1] = 'main.lua'
        end
        return result
    end
    fs.getRealDirectory = function(path)
        return path == 'main.lua' and '/game' or fs.getSaveDirectory()
    end
    fs.read = function(path)
        return assert(storage()[path])
    end
    fs.write = function(path, data)
        storage()[path] = data
        return true
    end
    fs.createDirectory = function(path)
        storage()[path] = true
        return true
    end
    local ok, count = SaveData.migrate(fs)
    self:check(
        ok and count == 1 and current['stats-logs/user.csv'] == 'recorded',
        'Migration copies nested user data'
    )
    self:check(
        current.conflict == 'new' and not current['main.lua'],
        'Migration preserves destination files and excludes project assets'
    )
    self:check(identity == SaveData.identity, 'Migration restores the destination identity')
    ok, count = SaveData.migrate(fs)
    self:check(ok and count == 0, 'Completed migration is idempotent')
    current['.legacy-save-migrated'] = nil
    fs.read = function()
        error('Read failure fixture')
    end
    ok = SaveData.migrate(fs)
    self:check(
        not ok and identity == SaveData.identity and not current['.legacy-save-migrated'],
        'Read errors restore the identity and remain retryable'
    )
    fs.read = function(path)
        return assert(storage()[path])
    end
    current = {}
    fs.write = function()
        return false, 'Write failure fixture'
    end
    ok = SaveData.migrate(fs)
    self:check(
        not ok and identity == SaveData.identity and not current['.legacy-save-migrated'],
        'Write errors preserve the source and remain retryable'
    )
end

function Tests:scrolling(scene, scale)
    local resources = self.manager.resources:scope()
    local ui = UI.new(320, 220, resources):bindWorld(scene.world)
    ui.scale = scale
    ui:setDensity(scale)
    local outer = ui:container(
        { position = { 0, 30, 0, 30 }, size = { 0, 200, 0, 160 }, clip = true },
        ui.content
    )
    local frame = ui:scroll({
        size = { 0, 180, 0, 140 },
        scrollingDirection = 'XY',
        canvasSize = { 0, 500, 0, 400 },
        scrollBarThickness = 16,
        scrollBarImageColor3 = { 0, 1, 0 },
        scrollBarImageTransparency = 0,
    }, outer)
    ui:container(
        { size = { 0, 500, 0, 400 }, backgroundColor = { 1, 0, 0 }, backgroundTransparency = 0 },
        frame
    )
    local canvas = love.graphics.newCanvas(320 * scale, 220 * scale)
    for _, direction in ipairs({ 'X', 'Y', 'XY' }) do
        for _, side in ipairs({ 'Left', 'Right' }) do
            for _, inset in ipairs({ 'None', 'Always', 'ScrollBar' }) do
                frame.scrollingDirection = direction
                frame.verticalScrollBarPosition = side
                frame.verticalScrollBarInset, frame.horizontalScrollBarInset = inset, inset
                love.graphics.push('all')
                love.graphics.setCanvas({ canvas, stencil = true })
                love.graphics.clear(0, 0, 0, 1, 0)
                ui:draw()
                love.graphics.pop()
                local image = canvas:newImageData()
                if direction ~= 'X' then
                    local x = side == 'Left' and 33 or 193
                    local _, green = image:getPixel(math.floor(x * scale), math.floor(45 * scale))
                    local _, edge =
                        image:getPixel(math.floor((x + 13) * scale), math.floor(45 * scale))
                    self:check(
                        green > 0.95 and edge > 0.95,
                        'Full vertical bar: ' .. direction .. '/' .. side .. '/' .. inset
                    )
                end
                if direction ~= 'Y' then
                    local x = 45 + frame._windowX
                    local _, green = image:getPixel(math.floor(x * scale), math.floor(153 * scale))
                    local _, edge = image:getPixel(math.floor(x * scale), math.floor(166 * scale))
                    self:check(
                        green > 0.95 and edge > 0.95,
                        'Full horizontal bar: ' .. direction .. '/' .. side .. '/' .. inset
                    )
                end
                local red, green = image:getPixel(math.floor(235 * scale), math.floor(80 * scale))
                self:check(red == 0 and green == 0, 'Ancestor clip remains active')
                image:release()
            end
        end
    end
    frame.position = { 0, 100, 0, 0 }
    ui:layout()
    love.graphics.push('all')
    love.graphics.setCanvas({ canvas, stencil = true })
    love.graphics.clear(0, 0, 0, 1, 0)
    ui:draw()
    love.graphics.pop()
    local image = canvas:newImageData()
    local red, green = image:getPixel(math.floor(235 * scale), math.floor(80 * scale))
    self:check(red == 0 and green == 0, 'An overflowing scrollbar cannot escape its ancestor')
    image:release()
    canvas:release()
    ui:release()
    resources:release()
end

function Tests:draw()
    if self.done then
        return
    end
    self.done = true
    self:migration()
    self:check(
        require('source.engine.core.runtime').machineCodeKiB == 32768,
        'The machine-code budget covers the extended rig workload'
    )
    self:check(
        love.filesystem.getIdentity() == 'katsa-engine',
        'Application uses katsa-engine save identity'
    )
    local scene = assert(self.manager:switch(Game.new, 'platformer', { physicsBackend = 'jolt' }))
    self.manager:update(1 / 60)
    scene.showStats = true
    scene.statistics:sample()
    local panel = scene.statistics.panel
    self:check(
        panel.rows[1].clip and panel.histories.fps.count > 0,
        'Stats clips row geometry while retaining histories'
    )
    self.manager:focus(false)
    scene.statistics:sample()
    self:check(
        panel.definitions[1].last == nil,
        'Paused scene update timing is unavailable instead of stale'
    )
    self:check(
        panel.histories['physics.updateMilliseconds'].revision == 1,
        'Paused physics does not repeat stale samples'
    )
    local history = panel.histories['physics.updateMilliseconds']
    self:check(
        history:summary(5, {}, self.manager.frameTime + 10).count == 0,
        'Unavailable metrics age out against the current panel clock'
    )
    self.manager:focus(true)
    for _, scale in ipairs({ 1, 1.25, 2 }) do
        self:scrolling(scene, scale)
    end
    self.manager.drawFinishedAt = love.timer.getTime() - 0.025
    self.manager:update(0)
    self:check(
        self.manager.frameGapMilliseconds >= 25,
        'Frame-gap diagnostics include waits outside scene drawing'
    )
    require('source.tests.versions.v106_2.text').run(self, scene)
    self:check(#self.manager.journal.entries == 0, 'No runtime journal errors')
    print('PASSED ' .. self.count .. ' v106.2 checks')
    love.event.quit()
end

return Tests
