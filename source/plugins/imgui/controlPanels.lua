-- Scene control panels as one ImGui window. A scene builds its controls once as engine UI (frames
-- of buttons, sliders and labels registered through `ui/widgets/collapsible`); with ImGui this
-- window mirrors them, so the engine nodes stay the single source of behaviour (their handlers
-- also rewrite button texts) and the legacy panels still work without the native library.
--
-- The window is laid out for reading, not copied node by node:
--   * every panel is a section of the one "Controls" window (no header when there is only one);
--     a panel with nothing to show adds nothing, and the window is as tall as its content;
--   * a Label that sits right above a Slider names that slider ("Gravity: 0.50" -> "Gravity");
--   * buttons that share a row in the engine layout (same top) share a row here;
--   * a button whose text ends in ": ON" / ": OFF" (any case) is a checkbox.
local ControlPanels = {}

local WIDTH = 360
local AUTO_RESIZE = 64

-- Flattens visible widgets of a panel in order: Button, Slider, TextBox, Label.
local function collect(node, list)
    for _, child in ipairs(node.children or {}) do
        if child.visible ~= false and not child.destroyed then
            if child:isA('Slider') or child:isA('TextBox') then
                list[#list + 1] = child
            elseif child:isA('Button') then
                if tostring(child.text or '') ~= '' then
                    list[#list + 1] = child
                end
            elseif child:isA('Label') then
                if tostring(child.text or '') ~= '' then
                    list[#list + 1] = child
                end
            else
                collect(child, list)
            end
        end
    end
    return list
end

local function top(node)
    local position = node.position
    return position and position[4] or 0
end

-- "Gravity multiplier: 0.50" -> "Gravity multiplier": the slider shows its own value.
local function title(text)
    return (text:gsub(':%s*[%-%d%.%s%%a-z]*$', ''))
end

local function slider(ig, node, name)
    ig.pushID(name or '')
    ig.setNextItemWidth(WIDTH * 0.5)
    local changed, value =
        ig.sliderFloat(name or '##slider', node.value, node.min, node.max, '%.2f')
    if changed then
        node.value = value
        node:emit('changed', value, node)
    end
    ig.popID()
end

local function press(node)
    node:emit('press', node, 0, 0, 'imgui')
end

-- Draws one row of buttons as wide as their engine columns (1/3 of the row -> three per row), but
-- never wider than four to a row, and never so narrow that a text is cut: a crowded group
-- wraps onto more rows of equal buttons.
local function drawButtons(ig, group)
    local spacing = 6
    local avail = WIDTH - 16
    local fraction = group[1].size and group[1].size[1] or 0
    local columns = fraction > 0 and fraction < 1 and math.floor(1 / fraction + 0.5) or #group
    columns = math.min(math.max(columns, math.min(#group, columns)), 4)
    local widest = 0
    for _, node in ipairs(group) do
        widest = math.max(widest, ig.textWidth(tostring(node.text)) + 20)
    end
    while columns > 1 and (avail - spacing * (columns - 1)) / columns < widest do
        columns = columns - 1
    end
    local width = (avail - spacing * (columns - 1)) / columns
    for i, node in ipairs(group) do
        local text = tostring(node.text)
        if (i - 1) % columns > 0 then
            ig.sameLine(0, spacing)
        end
        ig.pushID(i)
        if node.enabled == false then
            ig.button(text .. '##off', width, 0)
        elseif ig.button(text, width, 0) then
            press(node)
        end
        ig.popID()
    end
end

local function toggleParts(node)
    local name, state = tostring(node.text):match('^(.*):%s*([OoNnFf]+)$')
    state = state and state:upper()
    if state == 'ON' or state == 'OFF' then
        return name, state == 'ON'
    end
end

local function drawChecks(ig, node)
    local name, on = toggleParts(node)
    if ig.checkbox(name .. '##check', on) then
        press(node)
    end
end

local function isToggle(node)
    return toggleParts(node) ~= nil
end

local function drawList(ig, list)
    local i = 1
    while i <= #list do
        local node = list[i]
        ig.pushID(i)
        if node:isA('Slider') then
            local previous = list[i - 1]
            local name = previous and previous:isA('Label') and title(tostring(previous.text))
            slider(ig, node, name)
        elseif node:isA('TextBox') then
            local changed, text = ig.inputText('##text' .. i, node.text or '')
            if changed then
                node.text = text
                if node.onTextChanged then
                    node.onTextChanged(node)
                end
            end
        elseif node:isA('Button') and not node:isA('TextBox') then
            if isToggle(node) then
                drawChecks(ig, node)
            else
                -- Buttons that share a row (same top) and are not toggles.
                local group = { node }
                while
                    list[i + 1]
                    and list[i + 1]:isA('Button')
                    and not isToggle(list[i + 1])
                    and top(list[i + 1]) == top(node)
                do
                    i = i + 1
                    group[#group + 1] = list[i]
                end
                drawButtons(ig, group)
            end
        elseif node:isA('Label') then
            -- A label above a slider is that slider's name; it is drawn with the slider.
            local following = list[i + 1]
            if not (following and following:isA('Slider')) then
                ig.textWrapped(tostring(node.text))
            end
        end
        ig.popID()
        i = i + 1
    end
end

-- `scene.controlPanels` entries are { title, panel, startOpen, adopted, destroyed? } records.
function ControlPanels.draw(ig, scene, host)
    local sections = {}
    for _, entry in ipairs(scene.controlPanels or {}) do
        if entry.adopted and not entry.destroyed and not entry.panel.destroyed then
            local list = collect(entry.panel, {})
            if #list > 0 then
                sections[#sections + 1] = { entry = entry, list = list }
            end
        end
    end
    if #sections == 0 then
        return
    end
    local _, height = katsa.graphics.getDimensions()
    ig.setNextWindowPos(10, 50)
    if #sections == 1 then
        -- A scene that starts its only panel hidden starts the window collapsed.
        ig.C.igSetNextWindowCollapsed(not sections[1].entry.startOpen, ig.C.ImGuiCond_FirstUseEver)
    end
    ig.setNextWindowConstraints(WIDTH, 0, WIDTH, math.max(160, height - 120))
    if ig.begin('Controls##scenePanels', nil, AUTO_RESIZE) then
        for index, section in ipairs(sections) do
            ig.pushID(index)
            local open = #sections == 1 or ig.collapsingHeader(section.entry.title, section.entry.startOpen)
            if open then
                drawList(ig, section.list)
            end
            ig.popID()
        end
    end
    ig.finish()
end

return ControlPanels
