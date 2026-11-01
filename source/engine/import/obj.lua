local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs
local Geometry = require('source.engine.graphics.geometry.primitives')

local OBJ = {}

local function words(s)
    local t = {}
    for w in s:gmatch('%S+') do
        t[#t + 1] = w
    end
    return t
end

local function numberList(s)
    local t = {}
    for w in s:gmatch('%S+') do
        t[#t + 1] = assert(tonumber(w), 'Invalid OBJ number')
    end
    return t
end

local function resolve(i, list)
    i = assert(tonumber(i), 'Invalid OBJ index')
    if i < 0 then
        i = #list + i + 1
    end
    return assert(list[i], 'OBJ index out of range')
end

local function materials(path, resources)
    local text = assert(katsa.filesystem.read(path), 'Missing MTL: ' .. path)
    local dir = path:match('^(.*[/])') or ''
    local result, current = {}, nil
    for line in text:gmatch('[^\r\n]+') do
        local key, value = line:match('^%s*(%S+)%s+(.-)%s*$')
        if key == 'newmtl' then
            current = { color = { 1, 1, 1, 1 } }
            result[value] = current
        elseif current and key == 'Kd' then
            local c = numberList(value)
            current.color[1], current.color[2], current.color[3] = c[1], c[2], c[3]
        elseif current and key == 'd' then
            current.color[4] = assert(tonumber(value))
        elseif current and key == 'Tr' then
            current.color[4] = 1 - assert(tonumber(value))
        elseif current and key == 'map_Kd' then
            assert(value:sub(1, 1) ~= '-', 'MTL texture options require conversion')
            current.image = resources:image(dir .. value)
        end
    end
    return result
end

function OBJ.load(path, resources)
    local text = assert(katsa.filesystem.read(path), 'Missing OBJ: ' .. path)
    local dir = path:match('^(.*[/])') or ''
    local positions, uvs, normals = {}, {}, {}
    local groups, group, mtl = {}, nil, {}

    local function newGroup(name)
        group = { name = name, vertices = {}, material = { color = { 1, 1, 1, 1 } } }
        groups[#groups + 1] = group
    end
    newGroup('default')
    for line in text:gmatch('[^\r\n]+') do
        local key, value = line:match('^%s*(%S+)%s+(.-)%s*$')
        if key == 'v' then
            positions[#positions + 1] = numberList(value)
        elseif key == 'vt' then
            uvs[#uvs + 1] = numberList(value)
        elseif key == 'vn' then
            normals[#normals + 1] = numberList(value)
        elseif key == 'mtllib' then
            for k, v in pairs(materials(dir .. value, resources)) do
                mtl[k] = v
            end
        elseif key == 'o' or key == 'g' then
            newGroup(value)
        elseif key == 'usemtl' then
            if #group.vertices > 0 then
                newGroup(group.name)
            end
            group.material = assert(mtl[value], 'Missing OBJ material: ' .. value)
        elseif key == 'f' then
            local face = words(value)
            assert(#face >= 3, 'OBJ face requires at least 3 vertices')

            local function vertex(token)
                local p, t, n = token:match('^([^/]+)/?([^/]*)/?([^/]*)$')
                local position = resolve(p, positions)
                local uv = t ~= '' and resolve(t, uvs) or { 0, 0 }
                local normal = n ~= '' and resolve(n, normals)
                return {
                    position[1],
                    position[2],
                    position[3],
                    uv[1],
                    1 - (uv[2] or 0),
                    normal and normal[1],
                    normal and normal[2],
                    normal and normal[3],
                }
            end
            for i = 2, #face - 1 do
                group.vertices[#group.vertices + 1] = vertex(face[1])
                group.vertices[#group.vertices + 1] = vertex(face[i])
                group.vertices[#group.vertices + 1] = vertex(face[i + 1])
            end
        elseif key == 'curv' or key == 'surf' then
            error('OBJ curves/surfaces must be triangulated before import')
        end
    end
    local parts = {}
    for _, part in ipairs(groups) do
        if #part.vertices > 0 then
            part.geometry = Geometry.mesh(Geometry.normals(part.vertices))
            resources:own(part.geometry.mesh)
            parts[#parts + 1] = part
        end
    end
    assert(#parts > 0, 'OBJ has no triangle geometry: ' .. path)
    return { parts = parts }
end

return OBJ
