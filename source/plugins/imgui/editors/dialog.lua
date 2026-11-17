-- Shared helpers of the property dialogs (sequence, goals, uniforms, gradient, groups ...). A
-- dialog is { key, title, status, draw(ig, scene, host, dialog) } shown in its own window.
local Dialog = {}

-- Runs a mutation; a failure becomes the dialog's status line instead of an error.
function Dialog.attempt(dialog, fn, ...)
    local ok, err = pcall(fn, ...)
    dialog.status = ok and '' or tostring(err)
    return ok
end

function Dialog.status(ig, dialog)
    if dialog.status and dialog.status ~= '' then
        ig.textColored(1, 0.55, 0.45, 1, '%s', dialog.status)
    end
end

-- Repaints the engine UI after a data edit (the edited tables are read live).
function Dialog.touch(scene)
    local ui = scene.root and scene.root:find('World3D/World2D')
    if ui then
        ui:invalidate()
    end
end

-- A number field that applies on every change; `step` is the drag speed.
function Dialog.number(ig, label, value, step, min, max, format)
    return ig.dragFloat(label, value, step or 0.01, min or 0, max or 0, format or '%.4g')
end

return Dialog
