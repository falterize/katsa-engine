-- A dedicated server: the scene runs with no window content, a ServerHost serves the players and
-- commands come from the process's standard input.
--
--   katsa . --scene multiplayerCars --server [port] [--name "My server"] [--max-players 8]
--           [--no-bot] [--sim-latency ms] [--sim-jitter ms] [--sim-loss percent]
--
-- Console commands: help, status, players, kick, say, bots, cars, net, quit.
local Net = require('source.engine.net')
local ServerHost = require('./serverHost')
local StdinConsole = require('source.engine.debug.stdinConsole')

local Dedicated = {}
Dedicated.__index = Dedicated

local DEFAULT_PORT = 7777

-- Parses the launch arguments. Returns the options table, or nil when --server was not given.
function Dedicated.parse(arguments)
    local options
    for index, argument in ipairs(arguments or {}) do
        local value = arguments[index + 1]
        if argument == '--server' then
            options = options or {}
            options.port = tonumber(value) or options.port
        elseif options then
            if argument == '--name' and value then
                options.name = value
            elseif argument == '--max-players' and tonumber(value) then
                options.maxPlayers = tonumber(value)
            elseif argument == '--no-bot' then
                options.bot = false
            elseif argument == '--port' and tonumber(value) then
                options.port = tonumber(value)
            elseif argument == '--admin-token' and value then
                options.adminToken = value
            elseif argument == '--close-with-host' then
                options.closeWithHost = true
            end
        end
    end
    if options then
        options.port = options.port or DEFAULT_PORT
        options.name = options.name or 'Katsa cars server'
        options.maxPlayers = options.maxPlayers or 8
        options.simulate = Net.Conditions.fromArguments(arguments)
    end
    return options
end

-- A server a hosting player started writes this file into the save directory once it listens, so
-- the game that started it knows when to connect.
function Dedicated.getReadyFile(port)
    return ('server-%d.ready'):format(port)
end

function Dedicated.new(scene, options)
    local self = setmetatable({ scene = scene, options = options, uptime = 0 }, Dedicated)
    katsa.process.attachConsole() -- a runtime built without a console gets one (Windows)
    self.host = ServerHost.new(scene.world.resources, {
        port = options.port,
        name = options.name,
        maxPlayers = options.maxPlayers,
        bot = options.bot,
        simulate = options.simulate,
        adminToken = options.adminToken,
        closeWithHost = options.closeWithHost,
        onShutdown = function()
            katsa.event.quit()
        end,
        profiler = scene.manager.profiler,
    })
    self.host:start()
    self.game = self.host.game
    self.server = self.host:getServer()
    print(
        ('[server] "%s" listening on UDP port %d (%d players max). Type "help" for commands.'):format(
            options.name,
            options.port,
            options.maxPlayers
        )
    )
    self.readyFile = Dedicated.getReadyFile(options.port)
    katsa.filesystem.write(self.readyFile, tostring(katsa.process.getId()))
    local console, reason = StdinConsole.new(function(line)
        self:command(line)
    end)
    if console then
        self.console = console
    else
        print('[server] no console input: ' .. tostring(reason))
    end
    return self
end

local function words(line)
    local list = {}
    for word in line:gmatch('%S+') do
        list[#list + 1] = word
    end
    return list
end

local function findPlayer(self, query)
    for _, player in ipairs(self.server:getPlayers()) do
        if tostring(player.id) == query or player.name:lower() == query:lower() then
            return player
        end
    end
end

local HELP = [[
help                      this list
status                    players, cars, uptime and network conditions
players                   id, name and ping of every player
kick <id|name> [reason]   disconnect a player
say <text>                message to every player's chat
bots add [n] | bots clear add or remove bot cars
cars clear                remove every car (players get new ones when they sit in one)
net                       show the simulated network conditions
net <off|good|mobile|poor|terrible>   apply a preset
net <latency ms> [jitter ms] [loss %] [duplicate %]   explicit values
quit                      stop the server]]

local commands = {}

function commands.help()
    print(HELP)
end

function commands.status(self)
    local cars, bots = 0, 0
    for netId in pairs(self.game.cars) do
        cars = cars + 1
        bots = bots + (self.game.bots[netId] and 1 or 0)
    end
    print(
        ('[server] %d/%d players, %d cars (%d bots), up %d s, network: %s'):format(
            self.server:getPlayerCount(),
            self.options.maxPlayers,
            cars,
            bots,
            self.uptime,
            self.server:getConditions():describe()
        )
    )
end

function commands.players(self)
    local players = self.server:getPlayers()
    if #players == 0 then
        print('[server] no players')
    end
    for _, player in ipairs(players) do
        print(('[server] %2d  %-20s %4.0f ms'):format(player.id, player.name, player:getPing()))
    end
end

function commands.kick(self, args)
    local target = args[2] and findPlayer(self, args[2])
    if not target then
        print('[server] usage: kick <id|name> [reason]')
        return
    end
    self.game:kickPlayer(nil, target.id, table.concat(args, ' ', 3))
end

function commands.say(self, args, line)
    local text = line:match('^%S+%s+(.*)$')
    if text then
        self.game:say(text)
    end
end

function commands.bots(self, args)
    if args[2] == 'add' then
        for _ = 1, tonumber(args[3]) or 1 do
            self.game:hostCommand(nil, 'spawnBot')
        end
    elseif args[2] == 'clear' then
        self.game:hostCommand(nil, 'clearBots')
    else
        print('[server] usage: bots add [n] | bots clear')
    end
end

function commands.cars(self, args)
    if args[2] == 'clear' then
        self.game:hostCommand(nil, 'clearCars')
    else
        print('[server] usage: cars clear')
    end
end

function commands.net(self, args)
    local conditions = self.server:getConditions()
    if args[2] then
        local ok, problem
        if tonumber(args[2]) then
            ok, problem = pcall(conditions.set, conditions, {
                latency = tonumber(args[2]) / 1000,
                jitter = (tonumber(args[3]) or 0) / 1000,
                loss = (tonumber(args[4]) or 0) / 100,
                duplicate = (tonumber(args[5]) or 0) / 100,
            })
        else
            ok, problem = pcall(conditions.set, conditions, args[2])
        end
        if not ok then
            print('[server] ' .. tostring(problem))
            return
        end
    end
    print('[server] network: ' .. conditions:describe())
end

function commands.quit()
    katsa.event.quit()
end
commands.exit, commands.stop = commands.quit, commands.quit

function Dedicated:command(line)
    local args = words(line)
    local run = args[1] and commands[args[1]:lower()]
    if run then
        run(self, args, line)
    elseif args[1] then
        print('[server] unknown command "' .. args[1] .. '", try "help"')
    end
end

function Dedicated:update(dt)
    self.uptime = self.uptime + dt
    if self.console then
        self.console:update()
        if self.console:isClosed() and not self.consoleNoticed then
            self.consoleNoticed = true
            print('[server] standard input closed; the server keeps running')
        end
    end
    self.host:update(dt)
end

function Dedicated:release()
    if self.readyFile then
        katsa.filesystem.remove(self.readyFile)
    end
    if self.console then
        self.console:close()
    end
    self.host:stop()
end

return Dedicated
