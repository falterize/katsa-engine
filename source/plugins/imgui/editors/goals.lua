local pairs = require('source.engine.math.array').pairs
local Copy = require('source.engine.animation.bindings').copy
local Dialog = require('./dialog')
local Goals = require('source.engine.animation.rampGoals')
local Sequence = require('source.engine.animation.sequence')

-- The goal properties of a Ramp: the animated properties, each with its own keyframe track.
local Editor = { key = 'goals' }

function Editor.new(request)
    return {
        key = Editor.key,
        title = 'Goals',
        target = request.target,
        mode = 'list',
        status = '',
        draw = Editor.draw,
    }
end

local function choose(ig, host, dialog)
    local target = dialog.target
    if ig.button('Back to goals') then
        dialog.mode = 'list'
        return
    end
    local count = 0
    for _, field in ipairs(Goals.candidates(target)) do
        if not target.goals[field.key] and not target.bindings[field.key] then
            count = count + 1
            if ig.button(field.key .. '##candidate') then
                if Dialog.attempt(dialog, target.addGoal, target, field.key, field.value) then
                    host:openDialog('sequence', { target = target, property = field.key })
                    return
                end
            end
        end
    end
    if count == 0 then
        ig.textDisabled('All available numeric properties are already listed.')
    end
end

function Editor.draw(ig, scene, host, dialog)
    local target = dialog.target
    if target.destroyed then
        dialog.closed = true
        return
    end
    dialog.title = 'Goals / ' .. (target:getTarget() and target:getTarget().name or 'No target')
    if dialog.mode == 'choose' then
        choose(ig, host, dialog)
        Dialog.status(ig, dialog)
        return
    end
    if ig.button('+ Add goal') then
        dialog.mode = 'choose'
    end
    local keys, seen = {}, {}
    for key in pairs(target.goals) do
        keys[#keys + 1], seen[key] = key, true
    end
    for key in pairs(target.bindings) do
        if not seen[key] then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    if #keys == 0 then
        ig.textWrapped('No animated properties yet. Add one, then place its points in time.')
    end
    for _, key in ipairs(keys) do
        -- A goal is a keyframe track; one made from code with only a destination gets its track.
        if not target.bindings[key] then
            target.bindings[key] = Sequence.linear(Goals.value(target, key), Copy(target.goals[key]))
        end
        ig.pushID(key)
        if ig.button(key .. '  (edit points)') then
            host:openDialog('sequence', { target = target, property = key })
        end
        ig.sameLine()
        if ig.button('Remove') then
            target:removeGoal(key)
        end
        ig.popID()
    end
    Dialog.status(ig, dialog)
end

return Editor
