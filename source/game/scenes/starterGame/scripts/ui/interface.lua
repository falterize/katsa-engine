local Interface = {}

function Interface.create(state)
    local ui = state.scene.ui
    local label = ui:text({
        position = { 0, 20, 0, 20 },
        size = { 1, -40, 0, 44 },
        text = 'Your game starts here. F3: Stats',
        fontSize = 22,
    }, ui.content)
    ui:button({
        position = { 0, 20, 0, 80 },
        size = { 0, 220, 0, 44 },
        text = 'Save score +1',
        fontSize = 18,
        onPress = function()
            if not state.saved then
                label.text = tostring(state.saveError)
                return
            end
            local score = state.saved.score + 1
            local ok, failure = state.data:write('progress.json', { score = score })
            if ok then
                state.saved.score = score
            end
            label.text = ok and ('Saved score: ' .. score) or tostring(failure)
        end,
    }, ui.content)
    ui:button({
        position = { 0, 20, 0, 136 },
        size = { 0, 220, 0, 44 },
        text = 'Toggle rotation',
        fontSize = 18,
        onPress = function()
            local preferences = state.preferences
            preferences.rotationEnabled = not preferences.rotationEnabled
            local ok, failure = state.data:write('settings.json', preferences)
            label.text = ok and 'Rotation preference saved' or tostring(failure)
        end,
    }, ui.content)
end

return Interface
