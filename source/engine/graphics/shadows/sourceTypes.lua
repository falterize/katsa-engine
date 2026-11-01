local pointDirections = {
    { 1, 0, 0 },
    { -1, 0, 0 },
    { 0, 1, 0 },
    { 0, -1, 0 },
    { 0, 0, 1 },
    { 0, 0, -1 },
}

local function kind(light)
    return light.type == 'DirectionalLight3D' and 2 or light.type == 'PointLight3D' and 1 or 0
end

local function faces(record)
    return record.kind == 2 and 3 or record.kind == 1 and 6 or 1
end
return { kind = kind, faces = faces, pointDirections = pointDirections }
