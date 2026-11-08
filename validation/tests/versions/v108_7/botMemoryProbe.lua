-- multiplayerCars memory across spawn / clear cycles (bots by default; KATSA_SPAWN=spawnCar
-- KATSA_CLEAR=clearCars for plain cars). Prints live Lua memory after full collections per phase
-- and checks that no destroyed node stays reachable afterwards (the leak fixed in v108.7: the
-- renderer's batch membership and the particle draw list kept every removed car alive).
local Previous = require('validation.tests.versions.v107.physics2D')
local Walk = require('validation.tests.versions.v108_7.heapWalk')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

local COUNT = tonumber(os.getenv('KATSA_BOTS') or '8')
local CYCLES = tonumber(os.getenv('KATSA_CYCLES') or '2')
local SPAWN = os.getenv('KATSA_SPAWN') or 'spawnBot'
local CLEAR = os.getenv('KATSA_CLEAR') or 'clearBots'
local PERIOD = 400

function Tests.new(manager)
    local self = setmetatable(Previous.new(manager), Tests)
    self.frame = 0
    return self
end

function Tests:update() end

local function live()
    collectgarbage('collect')
    collectgarbage('collect')
    return collectgarbage('count') / 1024
end

function Tests:report(label)
    local server = self.session.server
    local bots = 0
    for _ in pairs(server.bots) do
        bots = bots + 1
    end
    print(('MEM %-14s live %.1f MB  bots %d  cars %d  nodes %d'):format(
        label, live(), bots, #server.order, #self.host.world.root:getDescendants()))
end

function Tests:finish()
    self:report('end')
    local dead, chain = Walk.find(function(t)
        return rawget(t, 'destroyed') == true and rawget(t, 'className') ~= nil
    end)
    if dead > 0 then
        print('CHAIN ' .. chain)
    end
    self:check(dead == 0, 'No destroyed node stays reachable after clearing (' .. dead .. ' found)')
    print('PASSED ' .. self.count .. ' v108.7 car memory checks')
    katsa.event.quit()
end

function Tests:draw()
    self.frame = self.frame + 1
    if self.frame == 1 then
        self.host = require('source.game.runtime.application').new(self.manager, 'multiplayerCars')
        self.host:load()
        self.session = self.host.demo
        self.session:host('Tester', 47980 + math.floor(os.clock() * 100) % 9)
    end
    self.host:update(1 / 60, 1 / 60)
    self.host:draw()
    local server = self.session.server
    local requester = server and server.hostPlayer
    if not requester then
        return
    end
    self.start = self.start or self.frame
    local t = self.frame - self.start
    local cycle, phase = math.floor(t / PERIOD), t % PERIOD
    if cycle >= CYCLES then
        if phase == 60 then
            self:finish()
        end
        return
    end
    if t == 30 then
        self:report('baseline')
    end
    if phase == 40 then
        for _ = 1, COUNT do
            server:hostCommand(requester, SPAWN)
        end
    elseif phase == 250 then
        self:report('cycle' .. cycle .. ' spawned')
        server:hostCommand(requester, CLEAR)
    elseif phase == 380 then
        self:report('cycle' .. cycle .. ' cleared')
    end
end

return Tests
