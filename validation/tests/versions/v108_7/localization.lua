-- Localization: tables, fallback, plurals, parameters, locale switch and Label binding.
local Localization = require('source.engine.localization')
local Plurals = require('source.engine.localization.plurals')

local Tests = {}

function Tests.run(tester)
    local service = Localization.new({ fallback = 'en' })
    service:addStrings('en', {
        menu = { play = 'Play' },
        hello = 'Hello, {name}!',
        items = { one = '{count} item', other = '{count} items' },
        onlyEnglish = 'English only',
    })
    service:addStrings('ru', {
        menu = { play = 'Играть' },
        items = { one = '{count} предмет', few = '{count} предмета', many = '{count} предметов', other = '{count} предмета' },
    })
    tester:check(service:t('menu.play') == 'Play' and service:t('hello', { name = 'Ann' }) == 'Hello, Ann!', 'nested keys and parameters')
    tester:check(service:setLocale('ru') and service:t('menu.play') == 'Играть', 'switching the locale changes the text')
    tester:check(service:t('onlyEnglish') == 'English only', 'a missing key falls back to the fallback locale')
    tester:check(service:t('nothing.here') == 'nothing.here' and service:getMissing()[1] == 'nothing.here', 'unknown keys return the key and are recorded')
    local forms = {}
    for _, n in ipairs({ 1, 2, 5, 11, 21, 22, 25 }) do
        forms[#forms + 1] = service:t('items', { count = n })
    end
    tester:check(
        forms[1] == '1 предмет' and forms[2] == '2 предмета' and forms[3] == '5 предметов' and forms[4] == '11 предметов' and forms[5] == '21 предмет' and forms[7] == '25 предметов',
        'Russian plural forms follow the language rule'
    )
    tester:check(Plurals.category('en', 1) == 'one' and Plurals.category('ja', 1) == 'other' and Plurals.category('fr', 0) == 'one', 'plural rules differ per language')
    tester:check(service:setLocale('ru_RU.UTF-8') and not service:setLocale('xx') and service:getLocale() == 'ru', 'locale codes match by language and unknown ones are refused')
    local changed = 0
    local stop = service:onChange(function()
        changed = changed + 1
    end)
    service:setLocale('en')
    stop()
    service:setLocale('ru')
    tester:check(changed == 1, 'onChange reports switches until it is disconnected')

    -- Labels translate themselves through the shared service.
    Localization.reset(service)
    local world = require('source.engine.world.world').new(tester.manager.resources:scope())
    local ui = world:create('World2D', { width = 320, height = 240 })
    local params = { count = 2 }
    local label = ui:create('Label', { textKey = 'items', textParams = params, size = { 0, 200, 0, 30 } }, ui.content)
    local button = ui:create('Button', { textKey = 'menu.play', size = { 0, 100, 0, 30 } }, ui.content)
    ui:draw()
    tester:check(label.text == '2 предмета' and button.text == 'Играть', 'Label and Button follow textKey')
    params.count = 5
    service:setLocale('en')
    ui:draw()
    tester:check(label.text == '5 items' and button.text == 'Play', 'text updates with the locale and the parameters')
    Localization.reset(nil)
    ui:destroy()

    local real = Localization.new()
    local codes = real:loadDirectory(tester.manager.resources:scope(), 'shared://locales')
    tester:check(#codes >= 3 and real:setLocale('de') and real:t('lab.items', { count = 3 }) == '3 Gegenstände im Beutel', 'locale files load from a folder')
end

return Tests
