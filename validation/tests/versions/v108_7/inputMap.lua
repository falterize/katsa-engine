-- InputMap: named actions over keys, mouse, wheel, gamepad buttons and axes; chords, edges,
-- rebinding, data, code-driven input and the shared project map.
local Tests = {}

function Tests.run(tester)
    local InputMap = dofile('source/engine/input/inputMap.lua')
    local map = InputMap.new({ jump = { 'key:space', 'pad:a' }, left = { 'a', 'axis:leftx.left' } })
    map:addAction('right', { InputMap.event.key('D'), InputMap.event.axis('leftx', 'right') })

    map:setEventStrength('key:space', 1)
    tester:check(map:isDown('jump') and not map:justPressed('jump'), 'a press is down but published next update')
    map:update()
    tester:check(map:justPressed('jump') and map:isDown('jump'), 'justPressed is true for the update after the press')
    map:update()
    tester:check(not map:justPressed('jump'), 'justPressed lasts one update')
    map:setEventStrength('key:space', 0)
    map:setEventStrength('pad:a', 1)
    tester:check(map:isDown('jump'), 'a second bound device keeps the action down')
    map:setEventStrength('pad:a', 0)
    map:update()
    tester:check(map:justReleased('jump') and not map:isDown('jump'), 'justReleased after the last event goes up')

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
    tester:check(#map:getEvents('jump') == 2, 'addEvent adds a binding and removeEvent removes one')

    local captured
    map:listenForEvent(function(event) captured = event end)
    map:setEventStrength('mouse:2', 1)
    tester:check(captured == 'mouse:2', 'listenForEvent takes the next event for rebinding')

    -- chords and alternatives
    local chord = InputMap.new({
        save = { 'key:ctrl+key:s', 'pad:start+pad:back' },
        dodge = { 'key:a+axis:leftx.left+key:c' },
    })
    chord:setEventStrength('key:s', 1)
    tester:check(not chord:isDown('save'), 'a chord needs every part held')
    chord:setEventStrength('key:ctrl', 1)
    tester:check(chord:isDown('save'), 'a chord is down once all its parts are')
    chord:setEventStrength('key:ctrl', 0)
    chord:setEventStrength('pad:start', 1, 1)
    chord:setEventStrength('pad:back', 1, 1)
    tester:check(chord:isDown('save'), 'any alternative binding triggers the action')
    chord:setEventStrength('pad:start', 0, 1)
    chord:setEventStrength('pad:back', 0, 1)
    chord:setEventStrength('key:a', 1)
    chord:setEventStrength('key:c', 1)
    chord:setAxisValue('leftx', -0.8)
    tester:check(math.abs(chord:getStrength('dodge') - 0.75) < 1e-6, 'a chord is as strong as its weakest part')
    tester:check(chord:getEvents('dodge')[1] == 'key:a+axis:leftx.left+key:c', 'chord text is canonical')

    -- a gamepad number and a per-binding deadzone
    local pads = InputMap.new({
        p2 = { 'pad:a@2' },
        aim = { 'key:space', { 'axis:leftx.left', deadzone = 0.5 }, { 'axis:rightx.left', deadzone = 0.1 } },
    })
    pads:setEventStrength('pad:a', 1, 1)
    tester:check(not pads:isDown('p2'), 'pad:a@2 ignores pad 1')
    pads:setEventStrength('pad:a', 1, 2)
    tester:check(pads:isDown('p2'), 'pad:a@2 follows pad 2')
    pads:setAxisValue('leftx', -0.4)
    pads:setAxisValue('rightx', -0.4)
    tester:check(math.abs(pads:getStrength('aim') - (0.3 / 0.9)) < 1e-6, 'each binding uses its own deadzone')
    local data = pads:toData()
    tester:check(data.aim[2].deadzone == 0.5 and InputMap.new(data):getEvents('aim')[2] == 'axis:leftx.left', 'binding deadzones survive toData and loadData')

    -- the old signed axis syntax is an error that names the new one
    local ok, message = pcall(InputMap.normalize, 'axis:leftx-')
    tester:check(not ok and message:find('axis:leftx.left', 1, true) or message:find('words', 1, true), 'the old axis:leftx- form is rejected with a hint')

    -- polling every pad
    local fakePads = {
        { getAxis = function() return -0.5 end },
        { getAxis = function() return 0 end },
    }
    local gamepads = { getCount = function() return #fakePads end, byIndex = function(n) return fakePads[n] end }
    local polled = InputMap.new({ walk = { 'axis:leftx.left@1' }, other = { 'axis:leftx.left@2' } })
    polled:pollGamepads(gamepads)
    tester:check(polled:isDown('walk') and not polled:isDown('other'), 'pollGamepads reads each pad on its own number')
    fakePads[1] = nil
    polled:pollGamepads({ getCount = function() return 0 end, byIndex = function() end })
    tester:check(not polled:isDown('walk'), 'a pad that disappears reads zero')

    -- shared project map: scene defaults never overwrite a rebinding
    local shared = InputMap.new({ jump = { 'key:j' } })
    local added = shared:addMissing({ jump = { 'key:space' }, fire = { 'mouse:1' } })
    tester:check(#added == 1 and shared:getEvents('jump')[1] == 'key:j', 'addMissing adds only the actions that do not exist')

    -- code-driven input and vectors
    local stick = InputMap.new({ left = 'key:a', right = 'key:d', up = 'key:w', down = 'key:s' })
    stick:pressVector('left', 'right', 'up', 'down', { -0.3, -0.7 })
    local v = stick:getVector('left', 'right', 'up', 'down', {})
    tester:check(v[1] < 0 and v[2] < 0 and math.abs(v[2]) > math.abs(v[1]), 'pressVector gives getVector a short vector pointing left and up')
    local world = stick:getWorldVector('left', 'right', 'up', 'down', {})
    tester:check(world[1] == v[1] and world[2] == -v[2], 'getWorldVector is getVector with Y up')
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

    -- ClickDetector3D: one detector on a Node3D covers every mesh below it; press, release, click
    local World = require('source.engine.world.world')
    local world = World.new(tester.manager.resources:scope())
    local car = world:create('Node3D', { name = 'Car' })
    local wheel = world:create('Mesh3D', { name = 'Wheel', shape = 'Cube' }, car)
    local other = world:create('Mesh3D', { name = 'Other', shape = 'Cube' })
    local whole = world:create('ClickDetector3D', {}, car)
    local part = world:create('ClickDetector3D', {}, wheel)
    tester:check(whole:contains(wheel) and part:contains(wheel) and not whole:contains(other), 'a detector on a Node3D covers the meshes below it')
    local log = {}
    for _, name in ipairs({ 'press', 'release', 'click', 'cancel' }) do
        whole:connect(name, function(id) log[#log + 1] = name .. ':' .. tostring(id) end)
    end
    whole:click()
    tester:check(table.concat(log, ',') == 'press:code,release:code,click:code', 'click() emits press, release and click for the pointer "code"')
    log = {}
    whole:press('finger')
    whole:cancel('finger')
    tester:check(table.concat(log, ',') == 'press:finger,cancel:finger' and not whole:release('finger'), 'a cancelled press never clicks')

    local copy = InputMap.new(map:toData())
    tester:check(table.concat(copy:getEvents('jump'), ',') == table.concat(map:getEvents('jump'), ','), 'toData and loadData round-trip')
    tester:check(not pcall(map.isDown, map, 'jmup'), 'an unknown action name is an error')
    tester:check(not pcall(InputMap.normalize, 'pad:nope'), 'a bad event is an error')
    tester:check(not pcall(InputMap.normalize, 'ctrl+s'), 'a chord without prefixes is an error')
end

return Tests
