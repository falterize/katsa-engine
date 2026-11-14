local bit = require('bit')
local ffi = require('ffi')

-- The Lua face of cimgui: `ig.button('Run')`, `ig.checkbox('On', value)`, `ig.text('%d', n)`.
-- Widgets that edit a value take it and return `changed, newValue` instead of a pointer. Any
-- cimgui function without a wrapper here is reachable by its C name through the same table:
-- `ig.C.igSetCursorPosX(10)`, and the enums are `ig.C.ImGuiWindowFlags_NoTitleBar`.
local Api = {}

local function create(library)
    local C = library.C
    local ig = { C = C, ffi = ffi }

    local function vec2(x, y)
        return ffi.new('ImVec2_c', x or 0, y or 0)
    end
    local function vec4(x, y, z, w)
        return ffi.new('ImVec4_c', x or 0, y or 0, z or 0, w or 0)
    end
    ig.vec2, ig.vec4 = vec2, vec4

    -- Scratch cells for pointer arguments; safe because every call completes before the next.
    local flag, number, integer = ffi.new('bool[1]'), ffi.new('float[1]'), ffi.new('int[1]')
    local rgb = ffi.new('float[4]')

    -- Windows ----------------------------------------------------------------------------
    -- begin(name, open, flags) -> visible, open. `open` nil draws no close button.
    function ig.begin(name, open, flags)
        local pointer
        if open ~= nil then
            flag[0] = open
            pointer = flag
        end
        local visible = C.igBegin(name, pointer, flags or 0)
        return visible, pointer and flag[0] or nil
    end
    function ig.finish()
        C.igEnd()
    end
    function ig.setNextWindowPos(x, y, condition, pivotX, pivotY)
        C.igSetNextWindowPos(vec2(x, y), condition or C.ImGuiCond_FirstUseEver, vec2(pivotX, pivotY))
    end
    function ig.setNextWindowSize(w, h, condition)
        C.igSetNextWindowSize(vec2(w, h), condition or C.ImGuiCond_FirstUseEver)
    end
    function ig.setNextWindowBgAlpha(alpha)
        C.igSetNextWindowBgAlpha(alpha)
    end
    function ig.beginChild(id, w, h, border, flags)
        return C.igBeginChild_Str(id, vec2(w, h), border and 1 or 0, flags or 0)
    end
    function ig.endChild()
        C.igEndChild()
    end

    -- Text -------------------------------------------------------------------------------
    function ig.text(format, ...)
        C.igText('%s', select('#', ...) > 0 and format:format(...) or format)
    end
    function ig.textDisabled(format, ...)
        C.igTextDisabled('%s', select('#', ...) > 0 and format:format(...) or format)
    end
    function ig.textWrapped(format, ...)
        C.igTextWrapped('%s', select('#', ...) > 0 and format:format(...) or format)
    end
    function ig.textColored(r, g, b, a, format, ...)
        C.igTextColored(vec4(r, g, b, a), '%s', select('#', ...) > 0 and format:format(...) or format)
    end

    -- Layout -----------------------------------------------------------------------------
    function ig.separator()
        C.igSeparator()
    end
    function ig.sameLine(offset, spacing)
        C.igSameLine(offset or 0, spacing or -1)
    end
    function ig.spacing()
        C.igSpacing()
    end
    function ig.indent(width)
        C.igIndent(width or 0)
    end
    function ig.unindent(width)
        C.igUnindent(width or 0)
    end
    function ig.pushID(id)
        if type(id) == 'number' then
            C.igPushID_Int(id)
        else
            C.igPushID_Str(tostring(id))
        end
    end
    function ig.popID()
        C.igPopID()
    end
    function ig.setNextItemWidth(width)
        C.igSetNextItemWidth(width)
    end

    -- Widgets ----------------------------------------------------------------------------
    function ig.button(label, w, h)
        return C.igButton(label, vec2(w, h))
    end
    function ig.checkbox(label, value)
        flag[0] = value == true
        local changed = C.igCheckbox(label, flag)
        return changed, flag[0]
    end
    function ig.sliderFloat(label, value, min, max, format)
        number[0] = value
        local changed = C.igSliderFloat(label, number, min, max, format or '%.3f', 0)
        return changed, number[0]
    end
    function ig.sliderInt(label, value, min, max, format)
        integer[0] = value
        local changed = C.igSliderInt(label, integer, min, max, format or '%d', 0)
        return changed, integer[0]
    end
    function ig.dragFloat(label, value, speed, min, max, format)
        number[0] = value
        local changed = C.igDragFloat(label, number, speed or 1, min or 0, max or 0, format or '%.3f', 0)
        return changed, number[0]
    end
    -- combo(label, index (1-based), { 'A', 'B' }) -> changed, index
    function ig.combo(label, index, items)
        local changed, picked = false, index
        if C.igBeginCombo(label, items[index] or '', 0) then
            for i, item in ipairs(items) do
                if C.igSelectable_Bool(item, i == index, 0, vec2()) then
                    changed, picked = i ~= index, i
                end
            end
            C.igEndCombo()
        end
        return changed, picked
    end
    -- colorEdit3(label, { r, g, b }) -> changed, { r, g, b } (0..1)
    function ig.colorEdit3(label, color)
        rgb[0], rgb[1], rgb[2] = color[1], color[2], color[3]
        local changed = C.igColorEdit3(label, rgb, 0)
        return changed, { rgb[0], rgb[1], rgb[2] }
    end
    -- inputText(label, text) -> changed, text (up to 255 bytes)
    local textBuffer = ffi.new('char[256]')
    function ig.inputText(label, text)
        ffi.copy(textBuffer, text or '', math.min(#(text or ''), 255))
        textBuffer[math.min(#(text or ''), 255)] = 0
        local changed = C.igInputText(label, textBuffer, 256, 0, nil, nil)
        return changed, ffi.string(textBuffer)
    end
    function ig.selectable(label, selected)
        return C.igSelectable_Bool(label, selected == true, 0, vec2())
    end
    function ig.progressBar(fraction, w, h, overlay)
        C.igProgressBar(fraction, vec2(w or -1, h or 0), overlay)
    end
    function ig.collapsingHeader(label, open)
        return C.igCollapsingHeader_TreeNodeFlags(
            label,
            open and C.ImGuiTreeNodeFlags_DefaultOpen or 0
        )
    end
    function ig.treeNode(label)
        return C.igTreeNode_Str(label)
    end
    function ig.treePop()
        C.igTreePop()
    end
    -- plotLines(label, values, overlay, min, max, w, h): `values` is a Lua array or a float cdata
    -- array (then pass `count`).
    function ig.plotLines(label, values, overlay, min, max, w, h, count)
        local cdata = values
        local size = count
        if type(values) == 'table' then
            size = #values
            cdata = ffi.new('float[?]', math.max(size, 1))
            for i = 1, size do
                cdata[i - 1] = values[i]
            end
        end
        C.igPlotLines_FloatPtr(
            label,
            cdata,
            size,
            0,
            overlay,
            min or C.igGET_FLT_MAX(),
            max or C.igGET_FLT_MAX(),
            vec2(w, h),
            ffi.sizeof('float')
        )
    end

    -- Tables -----------------------------------------------------------------------------
    function ig.beginTable(id, columns, flags, w, h)
        -- Fixed-fit columns by default: sized columns need an explicit policy (ImGui asserts otherwise).
        flags = flags
            or bit.bor(
                C.ImGuiTableFlags_RowBg,
                C.ImGuiTableFlags_SizingFixedFit,
                C.ImGuiTableFlags_ScrollY
            )
        return C.igBeginTable(id, columns, flags, vec2(w, h), 0)
    end
    function ig.endTable()
        C.igEndTable()
    end
    function ig.tableSetupColumn(label, flags, width)
        C.igTableSetupColumn(label, flags or 0, width or 0, 0)
    end
    function ig.tableHeadersRow()
        C.igTableHeadersRow()
    end
    function ig.tableNextRow()
        C.igTableNextRow(0, 0)
    end
    function ig.tableNextColumn()
        return C.igTableNextColumn()
    end

    -- Menus ------------------------------------------------------------------------------
    function ig.beginMainMenuBar()
        return C.igBeginMainMenuBar()
    end
    function ig.endMainMenuBar()
        C.igEndMainMenuBar()
    end
    function ig.beginMenu(label)
        return C.igBeginMenu(label, true)
    end
    function ig.endMenu()
        C.igEndMenu()
    end
    -- menuItem(label, shortcut, selected) -> activated
    function ig.menuItem(label, shortcut, selected)
        return C.igMenuItem_Bool(label, shortcut, selected == true, true)
    end

    return setmetatable(ig, {
        -- `ig.Foo` is the C function `igFoo`.
        __index = function(_, name)
            return C['ig' .. name]
        end,
    })
end

function Api.new(library)
    return create(library)
end

return Api
