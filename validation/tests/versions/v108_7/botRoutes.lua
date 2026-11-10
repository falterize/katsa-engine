-- A bot searches a route to a car on another floor once per replan period, not every tick.
local Module = {}

function Module.run(self)
    local Bot = require('source.game.scenes.multiplayerCars.server.scripts.bot')
    local searches = 0
    local nav = {
        levels = {},
        levelAt = function(_, _, y)
            return y > 3 and 2 or 1
        end,
        toCell = function(_, x, z)
            return x, z
        end,
        findPath = function()
            searches = searches + 1
            return { length = 10, target = function() end, isFinished = function() return false end }
        end,
        isBlocked = function() return false end,
    }
    local me = { x = 0, y = 1, z = 0, getDriver = function() return false end }
    local other = { x = 5, y = 6, z = 0, getDriver = function() return true end }
    local bot = Bot.new(me, { nav = nav, replan = 0.5 })
    for _ = 1, 20 do
        bot.clock = bot.clock + 0.01
        bot:findTarget({ me, other })
    end
    self:check(searches == 1, 'Twenty ticks within one period run a single floor route search')
    bot.clock = bot.clock + 0.6
    local target = bot:findTarget({ me, other })
    self:check(searches == 2 and target == other, 'A new search runs after the replan period')
end

return Module
