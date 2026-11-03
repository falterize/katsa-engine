-- The menu shows its own loading label before building a scene; Ctrl+C is not a crash.
local Menu = require('source.game.scenes.menu.scripts.ui.controller')
local Boot = require('source.katsa.host.boot')

local Module = {}

function Module.run(self)
    local switched = {}
    local menu = setmetatable({
        loadingLabel = {},
        ui = { invalidate = function() end },
        manager = {
            switch = function(_, _, id)
                switched[#switched + 1] = id
            end,
        },
    }, { __index = Menu })

    menu:choose('Cars', 'multiplayerCars')
    self:check(menu.loadingLabel.visible == true, 'choosing a scene shows the menu loading label')
    self:check(menu.loadingLabel.text == 'Loading Cars...', 'the label names the scene')
    menu:update()
    self:check(#switched == 0, 'the scene is not built during the frame that shows the label')
    menu:update()
    self:check(switched[1] == 'multiplayerCars', 'the scene starts on the next frame')

    self:check(Boot.isInterrupt('source/x.lua:27: interrupted!'), 'LuaJIT interrupt is recognised')
    self:check(not Boot.isInterrupt('source/x.lua:27: attempt to index nil'), 'errors are not')
end

return Module
