local ipairs = require('../../math.array').ipairs

local Tree = {}
local materials = setmetatable({}, { __mode = 'kv' })
local bodies = setmetatable({}, { __mode = 'kv' })

-- Explorer order under a World: its Environment, then nested World2D nodes, then everything
-- else in authored order. Only this view is reordered; `children` stays authoritative.
local function worldRank(child)
    if child:isA('Environment') then
        return 1
    end
    return child:isA('World2D') and 2 or 3
end

local function orderWorldChildren(result)
    local ordered = {}
    for rank = 1, 3 do
        for _, child in ipairs(result) do
            if worldRank(child) == rank then
                ordered[#ordered + 1] = child
            end
        end
    end
    return ordered
end

local function children(node)
    local result = {}
    -- World-space UI keeps its internal settings Environment on the host; it is plumbing, not content.
    local hostsUI = node.ui ~= nil and (node:isA('BillboardUI') or node:isA('SurfaceUI'))
    local isWorld = node.isA ~= nil and (node:isA('World3D') or node:isA('World2D'))
    for _, child in ipairs(node.children or {}) do
        if not (hostsUI and child._environmentOwner and child:isA('Environment')) then
            result[#result + 1] = child
        end
    end
    if isWorld then
        result = orderWorldChildren(result)
    end
    if node.material and node.material.uniforms then
        local child = materials[node]
        if not child or child._editorTarget ~= node.material then
            child = {
                name = 'Material',
                className = 'Material',
                _editorTarget = node.material,
                children = {},
                parent = node,
            }
            materials[node] = child
        end
        result[#result + 1] = child
    end
    if node._node and node.body and not node:isA('Body3D') and not node:isA('Body2D') then
        local child = bodies[node]
        if not child or child.body ~= node.body then
            local body = node.body
            local defaults = {
                density = 1,
                friction = 0.5,
                restitution = 0,
                linearDamping = 0.05,
                angularDamping = 0.05,
                gravityScale = 1,
                autoSleep = true,
                canCollide = true,
                canQuery = true,
                isTrigger = false,
                collisionGroup = 'Default',
            }
            local target = setmetatable({ _body = body }, {
                __index = function(_, key)
                    local v = body.settings[key]
                    if v ~= nil then
                        return v
                    end
                    return key == 'type' and body.type or defaults[key]
                end,
            })
            child = {
                name = 'Body3D',
                className = 'Body3D',
                _editorTarget = target,
                body = body,
                children = {},
                parent = node,
            }
            bodies[node] = child
        end
        result[#result + 1] = child
    end
    if node._node and node:isA('Environment') then
        node._settingRows = node._settingRows or {}
        local dimension = node._dimension
        local entries = {
            { 'Debug', node.debug, dimension == 2 and 'World2DDebug' or 'Debug' },
            { dimension == 2 and 'Particles2D' or 'Particles3D', node.particles, 'Particles' },
        }
        if dimension == 2 then
            entries[#entries + 1] = { 'Adjustments', node.adjustments }
        else
            for _, entry in ipairs({
                { 'Shadows', node.shadows, 'Shadows' },
                { 'Lighting', node.lightSettings },
                { 'Sky', node.sky, 'Sky' },
                { 'Fog', node.fog, 'Fog' },
                { 'Rendering', node.render },
                { 'Glow', node.glow },
                { 'SSAO', node.ssao },
                { 'DepthOfField', node.depthOfField },
                { 'Adjustments', node.adjustments },
            }) do
                entries[#entries + 1] = entry
            end
        end
        for _, entry in ipairs(entries) do
            if entry[2] then
                local row = node._settingRows[entry[1]]
                    or { name = entry[1], className = 'Settings', children = {}, parent = node }
                node._settingRows[entry[1]] = row
                row._editorTarget = entry[2]
                if entry[3] then
                    row._editorTarget._settingsKind = entry[3]
                end
                if entry[1] == 'Debug' then
                    row._categoryRows = row._categoryRows or {}
                    local debugEntries = dimension == 2
                            and { { 'Physics2D', node.debug.physics, 'Physics2DDebug' } }
                        or {
                            { 'Physics3D', node.debug.physics, 'PhysicsDebug' },
                            { 'Gizmos', node.debug.gizmos },
                        }
                    for _, section in ipairs(rawget(node, '_pluginDebug') or {}) do
                        debugEntries[#debugEntries + 1] = { section.title, section.settings }
                    end
                    for index, child in ipairs(debugEntries) do
                        local item = row._categoryRows[child[1]]
                            or {
                                name = child[1],
                                className = 'Settings',
                                children = {},
                                parent = row,
                            }
                        row._categoryRows[child[1]] = item
                        item._editorTarget = child[2]
                        if child[3] then
                            item._editorTarget._settingsKind = child[3]
                        end
                        row.children[index] = item
                    end
                end
                result[#result + 1] = row
            end
        end
    end
    return result
end
Tree.children = children

function Tree.rows(roots, collapsed, excluded, query)
    local rows, matches = {}, {}
    query = (query or ''):lower()
    local seen, stack, order = {}, {}, {}
    for i = #roots, 1, -1 do
        stack[#stack + 1] = { node = roots[i], depth = 0 }
    end
    while #stack > 0 do
        local item = table.remove(stack)
        local node = item.node
        if not seen[node] and not node.destroyed and node ~= excluded then
            seen[node] = true
            order[#order + 1] = item
            item.children = children(node)
            for i = #item.children, 1, -1 do
                stack[#stack + 1] =
                    { node = item.children[i], depth = item.depth + 1, owner = item }
            end
        end
    end
    if query ~= '' then
        for i = #order, 1, -1 do
            local item = order[i]
            local node = item.node
            local own = ((node.name or '') .. ' ' .. (node.className or ''))
                :lower()
                :find(query, 1, true) ~= nil
            matches[node] = own or matches[node] or false
            if item.owner and matches[node] then
                matches[item.owner.node] = true
            end
        end
    end
    local hiddenDepth
    for _, item in ipairs(order) do
        if hiddenDepth and item.depth <= hiddenDepth then
            hiddenDepth = nil
        end
        if not hiddenDepth and (query == '' or matches[item.node]) then
            rows[#rows + 1] = { node = item.node, depth = item.depth }
            if query == '' and collapsed[item.node] then
                hiddenDepth = item.depth
            end
        end
    end
    return rows
end

return Tree
