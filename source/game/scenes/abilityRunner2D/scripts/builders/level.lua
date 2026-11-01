local Level = {}

function Level.create(state)
    local ui = state.scene.ui
    local function box(name, x, y, w, h, color, trigger)
        local body = ui:create('Body2D', {
            name = name,
            position = { x, y },
            bodyType = 'Static',
            isTrigger = trigger == true,
        })
        local collider = ui:create('Collider2D', { name = 'Collider', size = { w, h } }, body)
        local visual = ui:create('Frame', {
            name = 'Visual',
            size = { 1, 0, 1, 0 },
            backgroundColor = color,
            backgroundTransparency = trigger and 0.3 or 0,
        }, collider)
        return body, visual
    end
    state.platforms = {}
    for i, platform in ipairs({
        { 180, -20, 360, 40 },
        { 600, -20, 280, 40 },
        { 1040, -20, 300, 40 },
        { 1630, -20, 500, 40 },
        { 390, 45, 100, 18 },
        { 590, 90, 140, 18 },
        { 800, 130, 100, 18 },
        { 1020, 155, 140, 18 },
        { 1220, 200, 100, 18 },
        { 1410, 120, 140, 18 },
    }) do
        local body = box(
            'Platform' .. i,
            platform[1],
            platform[2],
            platform[3],
            platform[4],
            { 0.18, 0.32, 0.4 }
        )
        state.platforms[#state.platforms + 1] = body
    end
    local kill = box('KillZone2D', 940, -100, 2100, 28, { 1, 0.18, 0.12 }, true)
    kill.runnerKillZone = true
    for i, point in ipairs({ { 590, 125 }, { 1020, 190 }, { 1530, 35 } }) do
        local node, visual =
            box('Checkpoint' .. i, point[1], point[2], 24, 40, { 1, 0.75, 0.2 }, true)
        node.runnerCheckpoint = i
        state.checkpoints[i] = { node = node, visual = visual, spawn = { point[1], point[2] } }
    end
    local finish = box('Finish2D', 1820, 45, 32, 90, { 0.3, 1, 0.55 }, true)
    finish.runnerFinish = true
end

return Level
