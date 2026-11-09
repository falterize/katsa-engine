local ipairs = require('source.engine.math.array').ipairs
local Theme = require('source.engine.ui.theme')

local Interface = {}

function Interface.create(state)
    local ui, service = state.scene.ui, state.service
    -- Changing `count` in place updates the plural text: nodes with textParams re-translate.
    state.params = { count = state.items }
    local panel = ui:container({
        name = 'LocalizationPanel',
        position = { 0.5, 0, 0.5, 0 },
        anchorPoint = { 0.5, 0.5 },
        size = { 0, 520, 0, 360 },
        backgroundColor = Theme.panel,
    }, ui.content)
    require('source.engine.ui.widgets.collapsible').create(state.scene, panel, 'Localization')
    ui:text({
        position = { 0, 16, 0, 12 },
        size = { 1, -32, 0, 40 },
        textKey = 'lab.title',
        textScaled = true,
        maxTextSize = 28,
    }, panel)
    ui:text({
        position = { 0, 16, 0, 56 },
        size = { 1, -32, 0, 28 },
        textKey = 'lab.hint',
        textScaled = true,
        maxTextSize = 16,
    }, panel)
    ui:text({
        position = { 0, 16, 0, 96 },
        size = { 1, -32, 0, 30 },
        textKey = 'lab.greeting',
        textParams = { name = 'Katsa' },
        textScaled = true,
        maxTextSize = 20,
    }, panel)
    ui:text({
        position = { 0, 16, 0, 136 },
        size = { 1, -32, 0, 30 },
        textKey = 'lab.items',
        textParams = state.params,
        textScaled = true,
        maxTextSize = 20,
    }, panel)
    ui:button({
        position = { 0, 16, 0, 180 },
        size = { 0.5, -24, 0, 36 },
        textKey = 'lab.more',
        onPress = function()
            state.items = state.items + 1
            state.params.count = state.items
        end,
    }, panel)
    ui:button({
        position = { 0.5, 8, 0, 180 },
        size = { 0.5, -24, 0, 36 },
        textKey = 'lab.less',
        onPress = function()
            state.items = math.max(0, state.items - 1)
            state.params.count = state.items
        end,
    }, panel)
    ui:text({
        position = { 0, 16, 0, 232 },
        size = { 1, -32, 0, 24 },
        textKey = 'lab.language',
        textScaled = true,
        maxTextSize = 16,
    }, panel)
    local x = 16
    for _, code in ipairs(service:locales()) do
        ui:button({
            position = { 0, x, 0, 262 },
            size = { 0, 150, 0, 36 },
            text = service:getMeta(code).name or code,
            onPress = function()
                service:setLocale(code)
            end,
        }, panel)
        x = x + 160
    end
    -- A key found only in English shows the fallback text in other languages.
    ui:text({
        position = { 0, 16, 0, 312 },
        size = { 1, -32, 0, 28 },
        textKey = 'lab.missing',
        textScaled = true,
        maxTextSize = 14,
        textColor = { 1, 0.8, 0.4 },
    }, panel)
end

return Interface
