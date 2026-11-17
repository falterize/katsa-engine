-- The bone mask of an AnimationTrack: an empty mask means all bones; a nonempty one excludes the
-- unlisted bones, and each included bone has a weight 0..1.
local Editor = { key = 'boneMask' }

function Editor.new(request)
    return {
        key = Editor.key,
        title = 'Bone mask / ' .. tostring(request.target.name),
        target = request.target,
        status = '',
        draw = Editor.draw,
    }
end

function Editor.draw(ig, _, _, dialog)
    local target = dialog.target
    if target.destroyed then
        dialog.closed = true
        return
    end
    if ig.button('Clear mask (all bones)') then
        target.boneMask = {}
    end
    ig.textWrapped('Empty mask: all bones. A nonempty mask excludes unlisted bones. Set each included weight from 0 to 1.')
    ig.separator()
    for _, node in ipairs(target._animator.model.nodes) do
        if node.isBone then
            local name = node.name
            local weight = target.boneMask[name]
            ig.pushID(name)
            local included = weight ~= nil
            local changed, picked = ig.checkbox(name, included)
            if changed then
                target.boneMask[name] = picked and 1 or nil
            end
            if included then
                ig.sameLine(260)
                ig.setNextItemWidth(-1)
                local moved, value = ig.sliderFloat('##weight', weight, 0, 1)
                if moved then
                    target.boneMask[name] = value
                end
            end
            ig.popID()
        end
    end
end

return Editor
