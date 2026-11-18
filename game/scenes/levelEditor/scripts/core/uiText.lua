-- The text shown on a BillboardUI or SurfaceUI. Their UI tree is not part of the node snapshot,
-- so the text is kept in the `EditorText` attribute (saved with the level) and the label inside
-- the board is rebuilt from it whenever the node is created, loaded or edited.
local UiText = {}

local ATTRIBUTE = 'EditorText'
local FONT_SIZE = 28

function UiText.supports(node)
    return node ~= nil and (node:isA('BillboardUI') or node:isA('SurfaceUI'))
end

function UiText.get(node)
    return node:getAttribute(ATTRIBUTE) or ''
end

-- Makes the label inside `node` show the attribute's text (creating the label on first use).
function UiText.apply(node)
    local text = node:getAttribute(ATTRIBUTE)
    if text == nil or not node.ui then
        return
    end
    local label = node._editorLabel
    if not label or label.destroyed then
        label = node.ui:text({
            size = { 1, 0, 1, 0 },
            text = text,
            fontSize = FONT_SIZE,
            backgroundColor = { 0.04, 0.06, 0.1 },
            backgroundTransparency = 0.35,
        }, node.ui.content)
        node._editorLabel = label
    end
    label.text = text
end

function UiText.set(node, text)
    node:setAttribute(ATTRIBUTE, text)
    UiText.apply(node)
end

UiText.ATTRIBUTE = ATTRIBUTE

return UiText
