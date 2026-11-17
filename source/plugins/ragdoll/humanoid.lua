-- Finds the bones of a humanoid skeleton by name and describes the ragdoll segments.
-- Name matching is case-insensitive and understands the usual spellings (Mixamo, Blender, Unity).
local Humanoid = {}

local function words(name)
    return name:lower():gsub('[^%w]+', '_')
end

-- Side of a bone name: 'l', 'r' or nil.
local function side(name)
    local n = '_' .. words(name) .. '_'
    if n:find('_l_', 1, true) or n:find('left', 1, true) then
        return 'l'
    end
    if n:find('_r_', 1, true) or n:find('right', 1, true) then
        return 'r'
    end
end

-- The first bone whose name contains one of `tokens` and none of `exclude`, on `wanted` side.
local function find(model, tokens, exclude, wanted)
    for _, node in ipairs(model.nodes) do
        if node.isBone then
            local name = words(node.name)
            local matched = false
            for _, token in ipairs(tokens) do
                if name:find(token, 1, true) then
                    matched = true
                    break
                end
            end
            for _, token in ipairs(exclude or {}) do
                if name:find(token, 1, true) then
                    matched = false
                    break
                end
            end
            if matched and (wanted == nil or side(node.name) == wanted) then
                return node
            end
        end
    end
end

-- Segment descriptions, top-down (a parent always comes before its children). A segment spans from
-- its own bone to the next one (`to`); `limit` scales the joint limits to its parent segment.
local SPEC = {
    { name = 'Hips', bone = { 'pelvis', 'hips' }, exclude = { 'hip_l', 'hip_r' }, to = 'Chest', reach = 0.5, girth = 1.7 },
    { name = 'Chest', bone = { 'chest', 'spine2', 'spine_002' }, parent = 'Hips', limit = 0.5, to = 'Head', chain = true, girth = 1.7 },
    { name = 'Head', bone = { 'head' }, exclude = { 'end', 'top' }, parent = 'Chest', limit = 0.6, girth = 1.3 },
}
-- Arms and legs are the same chain on both sides: upper part (hangs on `anchor`), lower part, tip.
local LIMBS = {
    {
        upper = { name = 'UpperArm', bone = { 'upper_arm', 'upperarm', 'arm' }, exclude = { 'fore', 'lower', 'twist' }, limit = 1.2 },
        lower = { name = 'Forearm', bone = { 'forearm', 'lowerarm' }, limit = 0.9 },
        tip = { name = 'Hand', bone = { 'hand' }, exclude = { 'index', 'thumb', 'finger' }, limit = 0.5, girth = 1.2 },
        anchor = 'Chest',
    },
    {
        upper = { name = 'Thigh', bone = { 'thigh', 'upleg', 'upperleg' }, limit = 1.0 },
        lower = { name = 'Shin', bone = { 'shin', 'calf', 'lowerleg' }, limit = 0.8 },
        tip = { name = 'Foot', bone = { 'foot', 'ankle' }, exclude = { '_001', 'end', 'toe' }, limit = 0.4, girth = 1.1 },
        anchor = 'Hips',
    },
}
for _, limb in ipairs(LIMBS) do
    for _, side in ipairs({ { 'L', 'l' }, { 'R', 'r' } }) do
        local suffix, key = side[1], side[2]
        local upper, lower, tip = limb.upper, limb.lower, limb.tip
        SPEC[#SPEC + 1] = {
            name = upper.name .. suffix, bone = upper.bone, exclude = upper.exclude, side = key,
            parent = limb.anchor, limit = upper.limit, to = lower.name .. suffix,
        }
        SPEC[#SPEC + 1] = {
            name = lower.name .. suffix, bone = lower.bone, side = key,
            parent = upper.name .. suffix, limit = lower.limit, to = tip.name .. suffix,
        }
        -- Hands and feet are segments too: without them the foot mesh hangs below the shin
        -- capsule and sinks into the floor.
        SPEC[#SPEC + 1] = {
            name = tip.name .. suffix, bone = tip.bone, exclude = tip.exclude, side = key,
            parent = lower.name .. suffix, limit = tip.limit, girth = tip.girth, optional = true,
        }
    end
end

-- Resolves the bones of `model`. Returns { segments = {...}, byName = {...} } or nil and a
-- message listing what is missing.
function Humanoid.resolve(model)
    local missing = {}
    local segments, byName = {}, {}
    for _, spec in ipairs(SPEC) do
        local bone = find(model, spec.bone, spec.exclude, spec.side)
        if not bone then
            -- A rig without hand or foot bones still gets its limbs (they just end at the wrist/ankle).
            if not spec.optional then
                missing[#missing + 1] = spec.name
            end
        else
            local segment = {
                name = spec.name,
                bone = bone,
                parent = spec.parent and byName[spec.parent],
                limit = spec.limit or 1,
                to = spec.to,
                reach = spec.reach or 1, -- fraction of the way from the bone to the next one
                chain = spec.chain, -- starts where the parent segment ends
                girth = spec.girth or 1,
            }
            segments[#segments + 1] = segment
            byName[spec.name] = segment
        end
    end
    if #missing > 0 then
        return nil, 'Humanoid bones not found: ' .. table.concat(missing, ', ')
    end
    for _, segment in ipairs(segments) do
        if segment.to then
            -- The end of a limb segment is the next limb segment's bone (else its first child bone).
            local nextSegment = byName[segment.to]
            segment.endBone = nextSegment and nextSegment.bone
        end
    end
    return { segments = segments, byName = byName }
end

return Humanoid
