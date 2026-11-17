-- Scene control panels as ImGui windows. A scene builds its control panel once as engine UI
-- (a scroll frame of buttons, sliders and labels registered through `ui/widgets/collapsible`);
-- with ImGui the window below mirrors it: each Button becomes an `ig.button` that fires the same
-- `press` handlers, each Slider an `ig.sliderFloat`, each Label a line of text, nested frames
-- are walked in order. The engine nodes stay the single source of behaviour (their handlers
-- also rewrite button texts), so nothing is duplicated and the legacy panel still works
-- without the native library.
local ControlPanels = {}

local function walk(ig, node, counter)
    for _, child in ipairs(node.children or {}) do
        if child.visible ~= false and not child.destroyed then
            counter.n = counter.n + 1
            ig.pushID(counter.n)
            if child:isA('Slider') then
                -- A slider is named by the label above it; only a deliberate name is shown.
                if child.name and child.name ~= '' and child.name ~= child.className then
                    ig.text(child.name)
                    ig.sameLine()
                end
                ig.setNextItemWidth(-1)
                local changed, value = ig.sliderFloat('##slider', child.value, child.min, child.max)
                if changed then
                    child.value = value
                    child:emit('changed', value, child)
                end
            elseif child:isA('TextBox') then
                local changed, text = ig.inputText('##text', child.text or '')
                if changed then
                    child.text = text
                    if child.onTextChanged then
                        child.onTextChanged(child)
                    end
                end
            elseif child:isA('Button') then
                local text = tostring(child.text or '')
                if text ~= '' then
                    if child.enabled == false then
                        ig.textDisabled(text)
                    elseif ig.button(text .. '##button') then
                        child:emit('press', child, 0, 0, 'imgui')
                    end
                end
            elseif child:isA('Label') then
                local text = tostring(child.text or '')
                if text ~= '' then
                    ig.textWrapped(text)
                end
            else
                walk(ig, child, counter)
            end
            ig.popID()
        end
    end
end

-- `entries` are { title, panel, destroyed? } records of scene.controlPanels.
function ControlPanels.draw(ig, scene, host)
    local index = 0
    for _, entry in ipairs(scene.controlPanels or {}) do
        if entry.adopted and not entry.destroyed and not entry.panel.destroyed then
            index = index + 1
            ig.setNextWindowPos(10, 50 + (index - 1) * 30)
            ig.setNextWindowSize(300, 420)
            -- Panels the scene starts hidden start collapsed.
            ig.C.igSetNextWindowCollapsed(not entry.startOpen, ig.C.ImGuiCond_FirstUseEver)
            if ig.begin(entry.title .. '##panel' .. index) then
                walk(ig, entry.panel, { n = 0 })
            end
            ig.finish()
        end
    end
end

return ControlPanels
