-- InputMap: named actions over keys, mouse, wheel, gamepad buttons and axes; edges, rebinding, data.
local Tests = {}

function Tests.run(tester)
    local InputMap = dofile('source/engine/input/inputMap.lua')
    local map = InputMap.new({ jump = { 'key:space', 'pad:a' }, left = { 'a', 'axis:leftx-' } })
    map:action('right', { InputMap.event.key('D'), InputMap.event.axis('leftx', '+') })

    map:setEvent('key:space', 1)
    tester:check(map:isDown('jump') and not map:pressed('jump'), 'a press is down but published next update')
    map:update()
    tester:check(map:pressed('jump') and map:isDown('jump'), 'pressed is true for the update after the press')
    map:update()
    tester:check(not map:pressed('jump'), 'pressed lasts one update')
    map:setEvent('key:space', 0)
    map:setEvent('pad:a', 1)
    tester:check(map:isDown('jump'), 'a second bound device keeps the action down')
    map:setEvent('pad:a', 0)
    map:update()
    tester:check(map:released('jump') and not map:isDown('jump'), 'released edge after the last event goes up')

    map:setEvent('key:space', 1)
    map:setEvent('key:space', 0)
    map:update()
    tester:check(map:pressed('jump') and map:released('jump'), 'a tap inside one frame is not lost')

    map:setAxis('leftx', 0.6)
    tester:check(map:isDown('right') and not map:isDown('left'), 'an axis drives the action of its direction')
    tester:check(math.abs(map:strength('right') - 0.5) < 1e-6, 'axis strength is rescaled past the deadzone')
    map:setAxis('leftx', 0.1)
    tester:check(not map:isDown('right'), 'an axis inside the deadzone is up')
    map:setAxis('leftx', -1)
    map:setEvent('key:d', 1)
    tester:check(map:axis('left', 'right') == 0, 'axis() is positive minus negative')

    local calls = {}
    local off = map:on('jump', function(name) calls[#calls + 1] = name end)
    map:setEvent('key:space', 1)
    map:update()
    off()
    map:setEvent('key:space', 0)
    map:setEvent('key:space', 1)
    map:update()
    tester:check(#calls == 1, 'on() runs on a press and the returned function removes it')

    map:tap('wheel:up')
    map:bind('jump', 'wheel:up')
    map:unbind('jump', 'pad:a')
    tester:check(#map:events('jump') == 2, 'bind adds an event and unbind removes one')

    local captured
    map:listen(function(event) captured = event end)
    map:setEvent('mouse:2', 1)
    tester:check(captured == 'mouse:2', 'listen takes the next event for rebinding')

    local virtual = InputMap.new({ fire = { 'key:f' } })
    virtual:press('fire')
    virtual:update()
    tester:check(virtual:isDown('fire') and virtual:pressed('fire'), 'press() from code acts like a bound event')
    virtual:release('fire')
    tester:check(not virtual:isDown('fire'), 'release() lets the action go')
    virtual:trigger('fire')
    virtual:update()
    tester:check(virtual:pressed('fire') and virtual:released('fire') and not virtual:isDown('fire'), 'trigger() is a press and release')

    local copy = InputMap.new(map:toData())
    tester:check(table.concat(copy:events('jump'), ',') == table.concat(map:events('jump'), ','), 'toData and load round-trip')
    local Detector = require('source.engine.nodes.core.baseNode').getClass('ClickDetector3D')
    local fired = {}
    local fake = { enabled = true, getTarget = function() end, emit = function(_, name) fired[#fired + 1] = name end }
    tester:check(Detector.activate(fake, 'code', true) and fired[1] == 'clicked', 'activate(force) fires clicked from code')
    tester:check(not pcall(map.isDown, map, 'jmup'), 'an unknown action name is an error')
    tester:check(not pcall(InputMap.normalize, 'pad:nope'), 'a bad event is an error')
end

return Tests
