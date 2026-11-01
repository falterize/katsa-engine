-- New RGB/transparency channels override legacy RGBA properties independently.
local Style = {}
local white = { 1, 1, 1 }

function Style.color(node, channel)
    if channel == 'background' then
        return node.backgroundColor or node.color
    end
    if channel == 'image' then
        return node.imageColor or node.tint or white
    end
    return node.textColor or white
end

function Style.alpha(node, channel, color)
    local value = node[channel .. 'Transparency']
    local legacy = value == nil and (color and color[4] or 1) or 1
    value = value or 0
    if not (value >= 0 and value <= 1) then
        error(channel .. 'Transparency must be within 0..1')
    end
    local group = node:isA('CanvasGroup') and 1 or (1 - (node.transparency or 0))
    return (1 - value) * legacy * group
end

return Style
