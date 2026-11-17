-- HUD of the voxel world: crosshair, the nine-slot hotbar with block icons, the status line and
-- the block picker (E) that assigns any block to the selected slot.
local Interface = {}

local ATLAS = 'scene://textures/blocks.png'
local SLOT, GAP = 56, 4

local function icon(ui, parent, tile, size)
    return ui:create('ImageRect', {
        position = { 0.5, 0, 0.5, 0 },
        anchorPoint = { 0.5, 0.5 },
        size = { 0, size, 0, size },
        image = ATLAS,
        imageMode = 'Atlas',
        atlasGrid = { 4, 4 },
        atlasFrame = tile,
        pixelate = true,
        backgroundTransparency = 1,
        interactable = false,
    }, parent)
end

local function crosshair(ui)
    for _, size in ipairs({ { 20, 2 }, { 2, 20 } }) do
        ui:container({
            position = { 0.5, 0, 0.5, 0 },
            anchorPoint = { 0.5, 0.5 },
            size = { 0, size[1], 0, size[2] },
            backgroundColor = { 1, 1, 1 },
            backgroundTransparency = 0.25,
            interactable = false,
        }, ui.content)
    end
end

local function hotbar(state, ui)
    local blocks, hotbar = state.blocks, state.hotbar
    local bar = ui:container({
        name = 'Hotbar',
        position = { 0.5, 0, 1, -14 },
        anchorPoint = { 0.5, 1 },
        size = { 0, 9 * (SLOT + GAP) + GAP, 0, SLOT + 2 * GAP },
        backgroundColor = { 0.06, 0.06, 0.07 },
        backgroundTransparency = 0.35,
    }, ui.content)
    local name = ui:create('Label', {
        position = { 0.5, 0, 1, -(SLOT + 2 * GAP + 34) },
        anchorPoint = { 0.5, 0 },
        size = { 0, 240, 0, 24 },
        fontSize = 18,
        interactable = false,
    }, ui.content)
    local cells = {}
    for i = 1, 9 do
        local cell = ui:container({
            position = { 0, GAP + (i - 1) * (SLOT + GAP), 0, GAP },
            size = { 0, SLOT, 0, SLOT },
            backgroundColor = { 0.2, 0.2, 0.22 },
            backgroundTransparency = 0.3,
            interactable = false,
        }, bar)
        cells[i] = { cell = cell, icon = icon(ui, cell, 0, SLOT - 14) }
    end
    local function refresh()
        for i, entry in ipairs(cells) do
            entry.icon.atlasFrame = blocks.list[hotbar.slots[i]].icon
            local selected = i == hotbar.selected
            entry.cell.backgroundColor = selected and { 1, 1, 1 } or { 0.2, 0.2, 0.22 }
            entry.cell.backgroundTransparency = selected and 0.1 or 0.3
        end
        name.text = blocks.list[hotbar:current()].name
    end
    hotbar:onChange(refresh)
    refresh()
end

local function picker(state, ui)
    local blocks, hotbar = state.blocks, state.hotbar
    local columns = 7
    local rows = math.ceil(#blocks.list / columns)
    local panel = ui:container({
        name = 'BlockPicker',
        position = { 0.5, 0, 0.5, 0 },
        anchorPoint = { 0.5, 0.5 },
        size = { 0, columns * (SLOT + GAP) + GAP, 0, rows * (SLOT + GAP) + GAP + 30 },
        backgroundColor = { 0.08, 0.08, 0.1 },
        backgroundTransparency = 0.15,
        visible = false,
        zIndex = 50,
    }, ui.content)
    ui:create('Label', {
        position = { 0, 8, 0, 4 },
        size = { 1, -16, 0, 22 },
        fontSize = 16,
        text = 'Click a block to put it in the selected slot (E closes)',
    }, panel)
    for index, block in ipairs(blocks.list) do
        local button = ui:button({
            position = {
                0, GAP + ((index - 1) % columns) * (SLOT + GAP),
                0, 30 + math.floor((index - 1) / columns) * (SLOT + GAP),
            },
            size = { 0, SLOT, 0, SLOT },
            text = '',
            backgroundColor = { 0.2, 0.2, 0.22 },
        }, panel)
        icon(ui, button, block.icon, SLOT - 14)
        button:connect('press', function()
            hotbar:set(index)
        end)
    end
    local function input()
        return state.scene.input
    end
    hotbar.pickerOpen = false
    hotbar.picker = {
        toggle = function()
            input():toggleMenu()
            if not hotbar.pickerOpen then
                hotbar.pickerOpen, panel.visible = true, true
            end
        end,
        hide = function()
            hotbar.pickerOpen, panel.visible = false, false
        end,
    }
end

function Interface.create(state)
    local ui = state.scene.root:find('World3D/World2D')
    crosshair(ui)
    hotbar(state, ui)
    picker(state, ui)
    state.status = ui:create('Label', {
        position = { 0, 12, 0, 10 },
        size = { 0, 520, 0, 80 },
        fontSize = 14,
        interactable = false,
    }, ui.content)
end

return Interface
