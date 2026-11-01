local Editor = require('source.engine.ui.widgets.textEditor')
local Tests = {}

function Tests.run(tester)
    local editor, copied = Editor.new('hello world'), ''
    local clipboard = {
        get = function()
            return copied
        end,
        set = function(value)
            copied = value
        end,
    }
    editor:key('a', { ctrl = true }, clipboard)
    editor:key('c', { ctrl = true }, clipboard)
    tester:check(copied == 'hello world', 'Text editor selects and copies all text')
    editor:replace('new')
    editor:key('z', { ctrl = true }, clipboard)
    tester:check(editor.text == 'hello world', 'Text editor undo restores replaced selection')
    editor:key('y', { ctrl = true }, clipboard)
    editor:key('home', {}, clipboard)
    editor:replace('A')
    tester:check(editor.text == 'Anew', 'Text editor supports redo and insertion at the caret')
    editor:set('A' .. require('utf8').char(0x1F642) .. 'B')
    editor:key('left', {}, clipboard)
    editor:key('backspace', {}, clipboard)
    tester:check(
        editor.text == 'AB',
        'Text editor navigation and deletion preserve UTF-8 boundaries'
    )
    editor:set('abc', true)
    copied = 'paste'
    editor:key('v', { ctrl = true }, clipboard)
    tester:check(editor.text == 'paste', 'Clipboard paste replaces the current selection')
    editor:key('a', { ctrl = true }, clipboard)
    editor:replace('blocked', { readOnly = true })
    tester:check(
        editor.text == 'paste',
        'Read-only TextBox preserves selection without accepting edits'
    )
    editor:set('')
    editor:replace('abcdef', { maxLength = 3 })
    tester:check(editor.text == 'abc', 'TextBox maximum length limits inserted characters')
    local world, ui, physics, body, release = tester:environment()
    local box = ui:create('TextBox', {
        text = 'first\nsecond',
        multiline = true,
        size = { 0, 180, 0, 60 },
        backgroundTransparency = 0,
    }, ui.content)
    box:focus(true)
    box:insertText('edited')
    tester:check(
        box.text == 'edited',
        'Reusable TextBox replaces selected text and exposes its value'
    )
    ui:draw()
    box:blur()
    release()
    local scene = require('source.game.runtime.application').new(tester.manager, 'abilityRunner2D')
    scene:load()
    local ws = scene.workspace
    ws:toggle(true)
    ws:select(scene.demo.sprite)
    ws:beginEdit({ key = 'image', kind = 'string', value = scene.demo.sprite.image })
    ws:textinput('scene://textures/player.png')
    ws:keypressed('home')
    ws:keypressed('delete')
    tester:check(
        ws.buffer == 'cene://textures/player.png',
        'Workspace uses a movable cursor instead of append-only text'
    )
    ws:cancelEdit()
    scene:release()
    local queue, saved, report = {}, '', 'Diagnostic traceback'
    local api = {
        filesystem = {
            write = function(_, text)
                saved = text
            end,
        },
        event = {
            clear = function()
                queue = {}
            end,
            pump = function() end,
            poll = function()
                local events = queue
                queue = {}
                local i = 0
                return function()
                    i = i + 1
                    if events[i] then
                        return unpack(events[i])
                    end
                end
            end,
        },
        keyboard = {
            setTextInput = function() end,
            setKeyRepeat = function() end,
            isDown = function()
                return true
            end,
        },
        system = {
            setClipboardText = function(value)
                copied = value
            end,
        },
    }
    local screen = require('source.engine.debug.errorScreen').create(report, api)
    queue = { { 'keypressed', 'escape' }, { 'keypressed', 'c' } }
    tester:check(
        screen() == nil and copied == report and saved:find(report, 1, true) ~= nil,
        'Error screen stays open on Escape, saves the report and supports clipboard copying'
    )
    queue = { { 'quit' } }
    tester:check(screen() == 1, 'Only an explicit close request exits the error screen')
end

return Tests
