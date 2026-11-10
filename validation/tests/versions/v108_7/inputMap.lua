-- InputMap: named actions over keys, mouse, wheel, gamepad buttons and axes; edges, rebinding, data.
local Tests = {}

function Tests.run(tester)
    local InputMap = dofile('source/engine/input/inputMap.lua')
    local map = InputMap.new({ jump = { 'key:space', 'pad:a' }, left = { 'a', 'axis:leftx-' } })
    map:addAction('right', { InputMap.event.key('D'), InputMap.event.axis('leftx', '+') })

    map:setEventStrength('key:space', 1)
    tester:check(map:isDown('jump') and not map:justPressed('jump'), 'a press is down but published next update')
    map:update()
    tester:check(map:justPressed('jump') and map:isDown('jump'), 'pressed is true for the update after the press')
    map:update()
    tester:check(not map:justPressed('jump'), 'pressed lasts one update')
    map:setEventStrength('key:space', 0)
    map:setEventStrength('pad:a', 1)
    tester:check(map:isDown('jump'), 'a second bound device keeps the action down')
    map:setEventStrength('pad:a', 0)
    map:update()
    tester:check(map:justReleased('jump') and not map:isDown('jump'), 'released edge after the last event goes up')

    map:setEventStrength('key:space', 1)
    map:setEventStrength('key:space', 0)
    map:update()
    tester:check(map:justPressed('jump') and map:justReleased('jump'), 'a tap inside one frame is not lost')

    map:setAxisValue('leftx', 0.6)
    tester:check(map:isDown('right') and not map:isDown('left'), 'an axis drives the action of its direction')
    tester:check(math.abs(map:getStrength('right') - 0.5) < 1e-6, 'axis strength is rescaled past the deadzone')
    map:setAxisValue('leftx', 0.1)
    tester:check(not map:isDown('right'), 'an axis inside the deadzone is up')
    map:setAxisValue('leftx', -1)
    map:setEventStrength('key:d', 1)
    tester:check(map:getAxis('left', 'right') == 0, 'getAxis() is positive minus negative')

    local calls = {}
    local connection = map:onPressed('jump', function(name) calls[#calls + 1] = name end)
    map:setEventStrength('key:space', 1)
    map:update()
    connection:disconnect()
    map:setEventStrength('key:space', 0)
    map:setEventStrength('key:space', 1)
    map:update()
    tester:check(#calls == 1, 'onPressed runs on a press and :disconnect() removes it')

    map:tapEvent('wheel:up')
    map:addEvent('jump', 'wheel:up')
    map:removeEvent('jump', 'pad:a')
    tester:check(#map:getEvents('jump') == 2, 'bind adds an event and unbind removes one')

    local captured
    map:listenForEvent(function(event) captured = event end)
    map:setEventStrength('mouse:2', 1)
    tester:check(captured == 'mouse:2', 'listenForEvent takes the next event for rebinding')

    local stick = InputMap.new({ left = 'key:a', right = 'key:d', up = 'key:w', down = 'key:s' })
    stick:pressVector('left', 'right', 'up', 'down', { -0.3, -0.7 })
    local v = stick:getVector('left', 'right', 'up', 'down', {})
    tester:check(v[1] < 0 and v[2] < 0 and math.abs(v[2]) > math.abs(v[1]), 'pressVector gives getVector a short vector pointing left and up')
    stick:pressVector('left', 'right', 'up', 'down', { 0.1, 0.1 })
    local inside = stick:getVector('left', 'right', 'up', 'down', {})
    tester:check(inside[1] == 0 and inside[2] == 0, 'getVector cuts a small push with a round deadzone')
    stick:pressVector('left', 'right', 'up', 'down', { 1, 1 })
    local full = stick:getVector('left', 'right', 'up', 'down', {})
    tester:check(math.abs(math.sqrt(full[1] ^ 2 + full[2] ^ 2) - 1) < 1e-6, 'getVector never exceeds length 1')

    local virtual = InputMap.new({ fire = { 'key:f' } })
    virtual:pressAction('fire')
    virtual:update()
    tester:check(virtual:isDown('fire') and virtual:justPressed('fire'), 'pressAction() from code acts like a bound event')
    virtual:releaseAction('fire')
    tester:check(not virtual:isDown('fire'), 'releaseAction() lets the action go')
    virtual:triggerAction('fire')
    virtual:update()
    tester:check(virtual:justPressed('fire') and virtual:justReleased('fire') and not virtual:isDown('fire'), 'triggerAction() is a press and release')

    local copy = InputMap.new(map:toData())
    tester:check(table.concat(copy:getEvents('jump'), ',') == table.concat(map:getEvents('jump'), ','), 'toData and loadData round-trip')
    local Detector = require('source.engine.nodes.core.baseNode').getClass('ClickDetector3D')
    local fired = {}
    local fake = { enabled = true, getTarget = function() end, emit = function(_, name) fired[#fired + 1] = name end }
    tester:check(Detector.activate(fake, 'code', true) and fired[1] == 'clicked', 'activate(force) fires clicked from code')
    tester:check(not pcall(map.isDown, map, 'jmup'), 'an unknown action name is an error')
    tester:check(not pcall(InputMap.normalize, 'pad:nope'), 'a bad event is an error')
end

return Tests
