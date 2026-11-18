-- Most-recently-used file list (newest first, no duplicates, capped). Pure Lua; the editor
-- stores it with LuaText next to the autosave.
local Recent = {}

Recent.LIMIT = 8

function Recent.push(list, path)
    local result = { path }
    for _, item in ipairs(list or {}) do
        if item ~= path and #result < Recent.LIMIT then
            result[#result + 1] = item
        end
    end
    return result
end

function Recent.remove(list, path)
    local result = {}
    for _, item in ipairs(list or {}) do
        if item ~= path then
            result[#result + 1] = item
        end
    end
    return result
end

return Recent
