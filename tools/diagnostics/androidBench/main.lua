-- Katsa device benchmark. Runs automatically; a tap re-runs it. Every figure is also logged.
-- Phases (each prints one row): Lua CPU cold/warm, shader compile, window-size calls, then frame
-- loops that vary one thing at a time (nothing, 200 rects, 20 full-screen overdraws, 2000 rects,
-- text) and a touch drag counter.
local graphics = katsa.graphics

local rows, phase, phaseStarted, frames, cpuDraw = {}, 0, nil, 0, 0
local touchMoves, touchMax, dragging = 0, 0, false

local function add(label, value)
    rows[#rows + 1] = { label, value }
    katsa.log.write('log', ('bench: %s = %s'):format(label, value), 'bench')
end

local function time(fn)
    local started = katsa.timer.getTime()
    fn()
    return (katsa.timer.getTime() - started) * 1000
end

local function luaWork()
    local sum, t = 0, {}
    for i = 1, 2000000 do
        sum = sum + math.sin(i) * math.sqrt(i)
        t[i % 512 + 1] = sum
    end
    return sum
end

local function stringWork()
    local parts = {}
    for i = 1, 40000 do
        parts[#parts + 1] = ('%d:%s'):format(i, tostring(i * 0.5))
    end
    return #table.concat(parts, ',')
end

local SHADER = [[
vec4 effect(vec4 color, Image image, vec2 uv, vec2 screenPosition) {
    vec4 c = Texel(image, uv) * color;
    float v = %s;
    return vec4(c.rgb * v, c.a);
}
]]

local function compileShaders()
    local expressions = {
        '1.0',
        'sin(uv.x * 10.0) * 0.5 + 0.5',
        'dot(normalize(vec3(uv, 1.0)), vec3(0.3, 0.5, 0.8))',
        'pow(max(uv.x, 0.0), 2.2) + fract(uv.y * 7.0)',
    }
    local total, worst = 0, 0
    for _, expression in ipairs(expressions) do
        local ms = time(function()
            local shader = graphics.newShader(SHADER:format(expression))
            graphics.setShader(shader)
            graphics.rectangle('fill', 0, 0, 1, 1)
            graphics.setShader()
        end)
        total, worst = total + ms, math.max(worst, ms)
    end
    add('shader compile, 4 programs', ('%.0f ms total, %.0f worst'):format(total, worst))
end

local function sizeCalls()
    local ms = time(function()
        for _ = 1, 20000 do
            katsa.platform:getRawMode()
        end
    end)
    add('window size x20000 (cached)', ('%.1f ms'):format(ms))
    local direct = time(function()
        for _ = 1, 2000 do
            katsa.platform.rawSize = nil
            katsa.platform:getRawMode()
        end
    end)
    add('window size x2000 (SDL call)', ('%.1f ms'):format(direct))
end

local LOADS = {
    { 'idle (clear + swap)', function() end },
    {
        '200 small rects',
        function(w, h)
            for i = 1, 200 do
                graphics.setColor(0.2 + i % 5 * 0.1, 0.4, 0.7, 1)
                graphics.rectangle('fill', (i * 37) % w, (i * 53) % h, 40, 40)
            end
        end,
    },
    {
        '20 full-screen overdraws',
        function(w, h)
            for _ = 1, 20 do
                graphics.setColor(0.05, 0.05, 0.05, 0.3)
                graphics.rectangle('fill', 0, 0, w, h)
            end
        end,
    },
    {
        '2000 small rects',
        function(w, h)
            for i = 1, 2000 do
                graphics.setColor(0.5, 0.3 + i % 7 * 0.1, 0.2, 1)
                graphics.rectangle('fill', (i * 31) % w, (i * 47) % h, 12, 12)
            end
        end,
    },
    {
        '120 text lines',
        function(w)
            graphics.setColor(1, 1, 1, 1)
            for i = 1, 120 do
                graphics.print('The quick brown fox jumps over the lazy dog 0123456789', 8, (i % 30) * 14, 0)
            end
        end,
    },
}

local PHASE_SECONDS = 2.5
local function frameStats()
    local seconds = katsa.timer.getTime() - phaseStarted
    return ('%.0f fps, draw %.1f ms'):format(frames / seconds, cpuDraw / math.max(frames, 1) * 1000)
end

local function start()
    rows, phase, phaseStarted, frames, cpuDraw = {}, 0, nil, 0, 0
    katsa.log.write('log', 'bench: ' .. katsa.system.getOS() .. ', JIT ' .. (jit.status() and 'on' or 'off'), 'bench')
    add('device', ('%s, %dx%d'):format(katsa.system.getOS(), katsa.graphics.getPixelDimensions()))
    add('Lua math, cold', ('%.0f ms'):format(time(luaWork)))
    add('Lua math, warm', ('%.0f ms'):format(time(luaWork)))
    add('Lua strings', ('%.0f ms'):format(time(stringWork)))
    compileShaders()
    sizeCalls()
    phase = 1
end

function katsa.load()
    start()
end

function katsa.update()
    if phase >= 1 and phase <= #LOADS then
        phaseStarted = phaseStarted or katsa.timer.getTime()
        if katsa.timer.getTime() - phaseStarted > PHASE_SECONDS then
            add(LOADS[phase][1], frameStats())
            phase, phaseStarted, frames, cpuDraw = phase + 1, nil, 0, 0
        end
    end
end

function katsa.draw()
    local w, h = graphics.getDimensions()
    graphics.setColor(0.07, 0.08, 0.1, 1)
    graphics.rectangle('fill', 0, 0, w, h)
    local started = katsa.timer.getTime()
    if phase >= 1 and phase <= #LOADS then
        LOADS[phase][2](w, h)
        frames = frames + 1
    end
    cpuDraw = cpuDraw + (katsa.timer.getTime() - started)
    graphics.setColor(0, 0, 0, 0.75)
    graphics.rectangle('fill', 0, 0, w, 40 + (#rows + 2) * 22)
    graphics.setColor(1, 1, 1, 1)
    graphics.print('Katsa bench - tap to run again', 12, 8, 0)
    for index, row in ipairs(rows) do
        graphics.print(row[1] .. ': ' .. row[2], 12, 36 + index * 22, 0)
    end
    local line = 36 + (#rows + 1) * 22
    if phase <= #LOADS then
        graphics.print('running: ' .. LOADS[phase][1], 12, line, 0)
    else
        graphics.print(('drag test: %d moves, most in one frame %d'):format(touchMoves, touchMax), 12, line, 0)
    end
end

local movesThisFrame = 0
function katsa.touchpressed()
    if phase > #LOADS then
        if dragging then
            return
        end
        touchMoves, touchMax, dragging = 0, 0, true
    end
end

function katsa.touchmoved()
    touchMoves, movesThisFrame = touchMoves + 1, movesThisFrame + 1
    touchMax = math.max(touchMax, movesThisFrame)
end

function katsa.touchreleased()
    dragging = false
    if phase > #LOADS and touchMoves == 0 then
        start()
    end
end

local update = katsa.update
function katsa.update(...)
    movesThisFrame = 0
    return update(...)
end
