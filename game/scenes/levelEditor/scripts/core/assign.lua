-- Writes a vector or a value to a node only when it changed. Assigning a node property every
-- frame makes the engine invalidate transforms and render caches even when nothing moved, so
-- everything the editor updates per frame (outlines, gizmo, light markers) goes through here.
-- Pure Lua.
local Assign = {}

function Assign.vec(node, key, a, b, c)
    local current = node[key]
    if current and current[1] == a and current[2] == b and current[3] == c then
        return false
    end
    node[key] = { a, b, c }
    return true
end

function Assign.color(node, color)
    local current = node.color
    if current and current[1] == color[1] and current[2] == color[2] and current[3] == color[3] and current[4] == color[4] then
        return false
    end
    node.color = { color[1], color[2], color[3], color[4] }
    return true
end

return Assign
