local Application = require('source.game.runtime.application')
local Game = require('source.game.runtime.game')
local Runtime = require('source.engine.core.runtime')
local Json = require('vendor.json')

local Soak = {}
Soak.__index = Soak

local function entries(store)
    local count = 0
    for _ in pairs(store.entries) do
        count = count + 1
    end
    return count
end

function Soak.new(manager)
    io.stdout:setvbuf('no')
    local self = setmetatable({
        manager = manager,
        allowWindowFrameReuse = true,
        idleSeconds = tonumber(os.getenv('KATSA_SOAK_IDLE') or 60),
        cycles = tonumber(os.getenv('KATSA_SOAK_CYCLES') or 50),
        holdSeconds = tonumber(os.getenv('KATSA_SOAK_HOLD') or 0.5),
        elapsed = 0,
        phase = 0,
        reused = 0,
        snapshots = {},
        retired = setmetatable({}, { __mode = 'v' }),
    }, Soak)
    assert(
        self.idleSeconds >= 1
            and self.cycles >= 1
            and self.cycles % 1 == 0
            and self.holdSeconds >= 0.05,
        'Invalid soak options'
    )
    self.scene = assert(manager:switch(Application.new, 'menu'))
    print('SOAK START', self.idleSeconds, 'idle seconds;', self.cycles, 'cycles')
    return self
end

function Soak:update(dt)
    if self.done then
        return
    end
    self.elapsed = self.elapsed + dt
    if self.phase == 0 and Runtime.timings and Runtime.timings.frameReused then
        self.reused = self.reused + 1
    end
    if self.elapsed < (self.phase == 0 and self.idleSeconds or self.holdSeconds) then
        return
    end
    if self.phase == 0 then
        assert(self.reused > 0, 'Idle Menu did not reuse the window frame')
    end
    local old = self.scene
    if self.phase > 0 and self.phase % 2 == 0 then
        -- One collection runs userdata finalizers; the second clears objects
        -- that became unreachable through those finalized resources.
        collectgarbage('collect')
        collectgarbage('collect')
        local retained = 0
        for _ in pairs(self.retired) do
            retained = retained + 1
        end
        local snapshot = {
            cycle = self.phase / 2,
            luaKiB = collectgarbage('count'),
            resources = entries(self.manager.resources.store),
            menuOwned = #self.scene.resources.owned,
            retainedScenes = retained,
        }
        self.snapshots[#self.snapshots + 1] = snapshot
        print('SOAK CYCLE ' .. Json.encode(snapshot))
        if snapshot.cycle >= 3 then
            local baseline = self.snapshots[2]
            assert(
                snapshot.resources == baseline.resources,
                'Retained resource entries grew across cycles'
            )
            assert(
                snapshot.menuOwned == baseline.menuOwned,
                'Menu resource ownership grew across cycles'
            )
            assert(
                snapshot.luaKiB < baseline.luaKiB + 8192,
                'Lua retention grew by more than 8 MiB after both backends warmed'
            )
            assert(retained == 0, 'A retired scene remains reachable after teardown')
        end
        assert(#self.manager.journal.entries == 0, 'Runtime journal contains errors')
    end
    self.phase = self.phase + 1
    self.elapsed = 0
    if self.phase > self.cycles * 2 then
        local report = {
            schema = 1,
            engine = require('source.engine.core.version').value,
            idleSeconds = self.idleSeconds,
            reusedMenuFrames = self.reused,
            cycles = self.cycles,
            snapshots = self.snapshots,
        }
        love.filesystem.createDirectory('validation-logs')
        local path = 'validation-logs/soak-' .. os.date('!%Y%m%dT%H%M%SZ') .. '.json'
        assert(love.filesystem.write(path, Json.encode(report)))
        print('PASSED SOAK ' .. love.filesystem.getSaveDirectory() .. '/' .. path)
        self.done = true
        love.event.quit()
        return
    end
    if self.phase % 2 == 1 then
        local backend = self.phase % 4 == 1 and 'jolt' or 'oimo'
        self.scene = assert(
            self.manager:switch(Game.new, 'animationPhysicsLab', { physicsBackend = backend })
        )
        self.scene.showStats = true
        self.scene.statistics.panel:select(3)
    else
        self.scene = assert(self.manager:switch(Application.new, 'menu'))
    end
    assert(old.resources.released, 'Previous scene resource scope was not released')
    self.retired[self.phase] = old
end

function Soak:draw() end

return Soak
