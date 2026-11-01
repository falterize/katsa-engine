# TextBox

TextBox is a reusable TextLabel-derived input node. The collection runtime and
standalone scene Host route keyboard/text events to its focused instance and
suspend gameplay movement while typing. Workspace and popup fields use this node.

```lua
local input = scene.ui:create('TextBox', {
    name = 'PlayerNameInput',
    text = '',
    placeholderText = 'Player name',
    position = { 0, 20, 0, 100 },
    size = { 0, 300, 0, 36 },
    fontSize = 16,
    backgroundColor = { 0.08, 0.13, 0.19 },
    backgroundTransparency = 0,
    maxLength = 40,
    onTextChanged = function(node, text)
        print('Current value:', text)
    end,
    onSubmit = function(node, text)
        print('Submitted:', text)
    end,
}, scene.ui.content)

input:focus(true) -- Focus and select all; false/nil retains selection.
-- input.text holds the current value, including programmatic assignments.
-- input:blur() releases keyboard focus.
```

Use `multiline = true` for explicit line breaks: Enter inserts a line and
Ctrl+Enter submits. Lines scroll horizontally and vertically to reveal the caret;
this version does not wrap long lines automatically. Single-line Enter submits.
`readOnly = true` permits selection/copy but prevents edits. `maxLength = 0`
means unlimited; positive values count UTF-8 characters rather than bytes.

Click to position the caret; drag or Shift+click to select; double-click selects
a word. Arrow keys move the caret; Shift extends selection. Ctrl+Left/Right moves
by words; Home/End moves to line boundaries and Ctrl+Home/End to text boundaries.
Backspace/Delete remove backward/forward. Ctrl+A/C/X/V selects/copies/cuts/pastes;
Ctrl+Z undoes, Ctrl+Y or Ctrl+Shift+Z redoes. Standard key repeat is enabled only
while focused. Escape blurs the field. Clicking elsewhere also releases focus.
Focus is unique across the application and is released when the node is destroyed.

Signals: `textChanged(node, text)`, `submitted(node, text)`, `focused(node)` and
`focusLost(node)`. Callback properties `onTextChanged`, `onSubmit`, `onFocusLost`
are available. Workspace retains its Apply/Cancel workflow; editing does not
write the inspected property until Apply or Enter.

Custom application hosts can route `input:keypressed(key)` and
`input:textinput(text)` to the common Input service; a true return means consumed.
Do not forward consumed keys to gameplay shortcuts.

## Runtime error reports

Normal Lua errors stop scene execution and retain a dedicated error window.
Escape does not close it; close the window explicitly to exit. Ctrl+C copies
the traceback, and the mouse wheel scrolls long reports. A copy is saved as
`crashes/crash-01.txt` inside the LÖVE save directory. Slots 01 through 10 retain
the latest ten reports, newest first; `last-error.txt` remains a compatibility copy. The handler releases captured
mouse input and resets graphics state before displaying the report.
Automated test/smoke commands still exit on failure so validation cannot hang.

UI Gallery includes single-line/multiline inputs and a Test world TextBoxes button.
It reveals editable BillboardUI and SurfaceUI examples. Both use the same input
node and shared focus/clipboard routing as screen-space fields.
