-- Bot route searches run on a worker thread and match the main-thread search; without a worker
-- the same call answers inline.
local Module = {}

local function wait(condition, seconds, pump)
    local deadline = katsa.timer.getTime() + seconds
    while not condition() and katsa.timer.getTime() < deadline do
        pump()
        katsa.timer.sleep(0.002)
    end
    return condition()
end

local function map(Layered)
    local nav = Layered.new(40, 40, { levels = 1, cellSize = 2, origin = { 0, 0 } })
    nav:bake(function(_, x, z)
        return x > 38 and x < 42 and z < 60
    end, function()
        return 0
    end)
    return nav
end

function Module.run(self)
    local Pathfinding = require('source.engine.plugins').require('pathfinding')
    local Bot = require('source.game.scenes.multiplayerCars.server.scripts.bot')
    local nav = map(Pathfinding.Layered)
    local planner = Pathfinding.RemotePlanner.new(nav, { size = 1, name = 'botTest' })
    self:check(planner:isThreaded(), 'The route planner starts a worker thread')

    local expected = nav:findPath(5, 0, 5, 75, 0, 5)
    local got
    planner:findPath(5, 0, 5, 75, 0, 5, function(path)
        got = path or false
    end)
    self:check(got == nil, 'A worker search answers later, not at once')
    wait(function()
        return got ~= nil
    end, 5, function()
        planner:update()
    end)
    local same = got and #got.points == #expected.points and math.abs(got.length - expected.length) < 1e-6
    self:check(same, 'The worker finds the same route as the main thread')

    -- A bot keeps driving without a route until the worker answers, then follows it.
    local car = { x = 5, y = 0.6, z = 5, heading = 0, speed = 0, nitro = 1, getDriver = function() return false end }
    local bot = Bot.new(car, { nav = nav, planner = planner })
    bot:plan(75, 0.6, 5)
    self:check(bot.path == nil and bot.searching == true, 'The bot plans without waiting for the worker')
    wait(function()
        return bot.path ~= nil
    end, 5, function()
        planner:update()
    end)
    self:check(bot.path ~= nil and not bot.searching, 'The worker route reaches the bot')

    -- A rebaked map is sent to the worker again.
    nav:bake(function()
        return false
    end, function()
        return 0
    end)
    local open
    planner:findPath(5, 0, 5, 75, 0, 5, function(path)
        open = path
    end)
    wait(function()
        return open ~= nil
    end, 5, function()
        planner:update()
    end)
    self:check(open and #open.points == 2, 'A changed map is resent: the straight route replaces the detour')

    -- A planner that lost its worker answers inline.
    planner.failure = 'test'
    local inline
    planner:findPath(5, 0, 5, 75, 0, 5, function(path)
        inline = path
    end)
    self:check(inline ~= nil, 'Without a worker the search runs inline and answers at once')
    planner:destroy()
end

return Module
