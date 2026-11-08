-- Diagnostic helper: searches the Lua heap from the registry the way LuaJIT's collector marks it
-- (weak keys / values are not followed).
local Walk = {}

-- Finds reachable tables for which predicate(t) is true; returns count and the reference chain of
-- the first one found (breadth first, so the chain is a shortest one).
function Walk.find(predicate)
    local seen, parent, label = {}, {}, {}
    local root = debug.getregistry()
    local queue, head = { root }, 1
    seen[root] = true
    seen[queue] = true
    local found, first = 0, nil
    local kinds = {}
    local function push(value, from, name)
        local t = type(value)
        if (t == 'table' or t == 'function' or t == 'userdata' or t == 'thread') and not seen[value] then
            seen[value] = true
            parent[value], label[value] = from, name
            queue[#queue + 1] = value
        end
    end
    while head <= #queue do
        local value = queue[head]
        queue[head] = false
        head = head + 1
        local t = type(value)
        if t == 'table' then
            if predicate(value) then
                found = found + 1
                first = first or value
                local kind = type(rawget(value, 'name')) == 'string' and rawget(value, 'name') or '?'
                kinds[kind] = (kinds[kind] or 0) + 1
            end
            local mt = debug.getmetatable(value)
            local mode = mt and type(mt) == 'table' and rawget(mt, '__mode') or ''
            if type(mode) ~= 'string' then
                mode = ''
            end
            if mt then
                push(mt, value, '<mt>')
            end
            for k, v in next, value do
                if not mode:find('k') then
                    push(k, value, '<key>')
                end
                if not mode:find('v') then
                    push(v, value, type(k) == 'string' and k or ('[' .. type(k) .. ']'))
                end
            end
        elseif t == 'function' then
            local i = 1
            while true do
                local name, up = debug.getupvalue(value, i)
                if not name then
                    break
                end
                local info = debug.getinfo(value, 'S')
                push(up, value, '^' .. name .. '@' .. info.short_src .. ':' .. info.linedefined)
                i = i + 1
            end
        elseif t == 'userdata' then
            local mt = debug.getmetatable(value)
            if mt then
                push(mt, value, '<mt>')
            end
            local env = debug.getfenv and debug.getfenv(value)
            if env then
                push(env, value, '<env>')
            end
        end
    end
    local chain = {}
    local node = first
    while node and node ~= root do
        table.insert(chain, 1, tostring(label[node]))
        node = parent[node]
    end
    return found, table.concat(chain, ' -> '), kinds
end

return Walk
