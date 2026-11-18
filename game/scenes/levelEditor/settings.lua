-- Every editor control is an InputMap action (docs/guides/input/inputMap.md). The scene code
-- reads actions only, so each key can be rebound in the shared map. Fly keys are chords with the
-- look button, so W/A/S/D/Q/E move the camera only while the right mouse button is held and
-- stay free for the tool hotkeys otherwise.
local function ctrl(key)
    return { 'key:lctrl+key:' .. key, 'key:rctrl+key:' .. key }
end

local function look(key)
    return { 'mouse:2+key:' .. key }
end

local Settings = {
    layoutVersion = 3,
    plugins = { 'uiStyler' },
    physics = { backend = 'auto' },
    presentation = { navigation = false },
    cameraButtons = false,
    input = {
        editorLook = { 'mouse:2' },
        editorForward = look('w'),
        editorBack = look('s'),
        editorLeft = look('a'),
        editorRight = look('d'),
        editorUp = look('e'),
        editorDown = look('q'),
        editorFast = { 'key:lshift', 'key:rshift' },
        editorSpeedUp = { 'wheel:up' },
        editorSpeedDown = { 'wheel:down' },
        editorPick = { 'mouse:1' },
        editorAdd = { 'key:lctrl', 'key:rctrl' },
        editorRange = { 'key:lshift', 'key:rshift' },
        editorFocus = { 'key:f' },
        editorFrameAll = { 'key:home' },
        editorToolSelect = { 'key:q' },
        editorToolMove = { 'key:w' },
        editorToolRotate = { 'key:e' },
        editorToolScale = { 'key:r' },
        editorToggleGrid = { 'key:g' },
        editorToggleSpace = { 'key:x' },
        editorUndo = ctrl('z'),
        editorRedo = ctrl('y'),
        editorDuplicate = ctrl('d'),
        editorCut = ctrl('x'),
        editorCopy = ctrl('c'),
        editorPaste = ctrl('v'),
        editorSelectAll = ctrl('a'),
        editorCreate = { 'key:lshift+key:a', 'key:rshift+key:a' },
        editorDelete = { 'key:delete' },
        editorSave = ctrl('s'),
        editorOpen = ctrl('o'),
    },
    editor = {
        autosaveSeconds = 60,
        flySpeed = 10,
        flyFastFactor = 4,
        flySpeedMin = 0.5,
        flySpeedMax = 400,
        sensitivity = 0.15,
        fov = 70,
        grid = { cell = 1, major = 10, count = 60, visible = true },
        snap = { move = 0.5, rotate = 15, scale = 0.1 },
    },
}

return Settings
