local Examples = {}
local function input(ui, parent, name, y, text, multiline)
    return ui:create('TextBox', {
        name = name,
        position = { 0, 12, 0, y },
        size = { 1, -24, 0, multiline and 100 or 40 },
        text = text,
        placeholderText = 'Type here',
        fontSize = 17,
        multiline = multiline,
        backgroundColor = { 0.08, 0.16, 0.24 },
        backgroundTransparency = 0,
    }, parent)
end
function Examples.create(state, left)
    local scene, ui = state.scene, state.scene.ui
    ui:text({
        position = { 0, 12, 0, 810 },
        size = { 1, -24, 0, 32 },
        text = 'TextBox / selection + clipboard',
        fontSize = 19,
    }, left)
    state.textBox =
        input(ui, left, 'GalleryTextBox', 850, 'Select, copy, paste and edit this text', false)
    state.multilineTextBox = input(
        ui,
        left,
        'GalleryMultiline',
        900,
        'Multiline input\nEnter adds a line; Ctrl+Enter submits.',
        true
    )
    local world = scene.world
    local board = require('source.engine.ui').newBillboard(world, {
        name = 'TextBoxBillboard',
        position = { -28, 30, 50 },
        size = { 42, 25 },
        sizeMode = 'World3D',
        onTop = true,
        canvasSize = { 0, 420, 0, 250 },
    })
    local mesh = world:create('Mesh3D', {
        name = 'TextBoxSurfaceHost',
        position = { 28, 30, 50 },
        size = { 42, 25, 3 },
        color = {
            0.1,
            0.2,
            0.3,
        },
    })
    local surface = world:create(
        'SurfaceUI',
        { name = 'TextBoxSurface', face = 'Front', canvasSize = { 0, 420, 0, 250 }, onTop = true },
        mesh
    )
    state.billboardTextBox =
        input(board.ui, board.ui.content, 'BillboardTextBox', 70, 'Editable BillboardUI', false)
    state.surfaceTextBox =
        input(surface.ui, surface.ui.content, 'SurfaceTextBox', 70, 'Editable SurfaceUI', false)
    board.visible, mesh.visible = false, false
    ui:button({
        name = 'WorldTextBoxExamples',
        position = { 0, 12, 0, 84 },
        size = { 0, 280, 0, 36 },
        text = 'Test world TextBoxes',
        fontSize = 17,
        onPress = function(button)
            local show = not board.visible
            board.visible, mesh.visible, state.root.visible = show, show, not show
            button.text = show and 'Return to UI Gallery' or 'Test world TextBoxes'
        end,
    }, ui.content)
end
return Examples
