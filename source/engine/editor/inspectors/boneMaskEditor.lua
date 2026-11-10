local ipairs = require('../../math.array').ipairs

local Editor = {}

function Editor.open(popup)
    popup.workspace:cancelEdit()
    while #popup.body.children > 0 do
        popup.body.children[#popup.body.children]:destroy()
    end
    popup.title.text = 'Bone mask / ' .. popup.target.name
    local nodes = popup.target._animator.model.nodes
    local y = 0
    do
        local node = popup.ui:button({
            size = { 1, 0, 0, 32 },
            text = 'Clear mask (all bones)',
            fontSize = 13,
        }, popup.body)
        node:connect('press', function()
            popup.target.boneMask = {}
            Editor.open(popup)
        end)
    end
    y = 38
    popup.ui:text({
        position = { 0, 4, 0, y },
        size = { 1, -8, 0, 44 },
        text = 'Empty mask: all bones. A nonempty mask excludes unlisted bones. Set each '
            .. 'included weight from 0 to 1.',
        fontSize = 12,
    }, popup.body)
    y = y + 48
    for _, node in ipairs(nodes) do
        if node.isBone then
            local name = node.name
            local weight = popup.target.boneMask[name]
            do
                local node = popup.ui:button({
                    position = { 0, 0, 0, y },
                    size = { 0.7, -4, 0, 32 },
                    text = (weight ~= nil and '- ' or '+ ') .. name,
                    fontSize = 11,
                }, popup.body)
                node:connect('press', function()
                    if popup.workspace.editing and not popup:commitInput() then
                        return
                    end
                    if weight ~= nil then
                        popup.target.boneMask[name] = nil
                    else
                        popup.target.boneMask[name] = 1
                    end
                    Editor.open(popup)
                end)
            end
            if weight ~= nil then
                do
                    local node = popup.ui:slider({
                        position = { 0.7, 0, 0, y },
                        size = { 0.3, 0, 0, 32 },
                        min = 0,
                        max = 1,
                        value = weight,
                    }, popup.body)
                    node:connect('changed', function(value)
                        popup.target.boneMask[name] = value
                    end)
                end
            end
            y = y + 36
        end
    end
    popup.body.length = y
end

return Editor
