-- Immutable resource images are classified once while their CPU pixels exist.
local Opacity = {}
local images = setmetatable({}, { __mode = 'k' })
local blockBytes = 65536
local opaqueBlock = '^' .. ('...\255'):rep(blockBytes / 4)
-- Structural proof from the same successfully decoded bytes, never a filename hint.
local function encodedOpaque(encoded, ffi)
    local size = encoded:getSize()
    local bytes = ffi.cast('const uint8_t*', encoded:getFFIPointer())
    if size >= 3 and ffi.string(bytes, 3) == '\255\216\255' then
        return true
    end
    if
        size < 33
        or ffi.string(bytes, 8) ~= '\137PNG\13\10\26\10'
        or ffi.string(bytes + 12, 4) ~= 'IHDR'
    then
        return false
    end
    local kind = bytes[25]
    if kind ~= 0 and kind ~= 2 then
        return false
    end
    local offset = 8
    while offset + 12 <= size do
        local length = bytes[offset] * 16777216
            + bytes[offset + 1] * 65536
            + bytes[offset + 2] * 256
            + bytes[offset + 3]
        if length > size - offset - 12 then
            return false
        end
        local chunk = ffi.string(bytes + offset + 4, 4)
        if chunk == 'tRNS' then
            return false
        end
        if chunk == 'IEND' then
            return true
        end
        offset = offset + length + 12
    end
    return false
end

function Opacity.register(image, data, encoded)
    local ok, ffi = pcall(require, 'ffi')
    if ok and encoded and encodedOpaque(encoded, ffi) then
        images[image] = true
        return
    end
    local opaque = true
    local format = data:getFormat()
    if ok and (format == 'rgba8' or format == 'srgba8') then
        local pixels = ffi.cast('const uint8_t*', data:getFFIPointer())
        local size = data:getSize()
        if jit and jit.status() then
            -- Compiled FFI scans avoid string copies when JIT is available.
            for i = 3, size - 1, 4 do
                if pixels[i] ~= 255 then
                    opaque = false
                    break
                end
            end
        else
            -- An anchored native pattern checks alpha bytes at their exact offsets.
            -- Each temporary string is bounded; RGB, including zeros, is ignored.
            for offset = 0, size - 1, blockBytes do
                local bytes = math.min(blockBytes, size - offset)
                local pattern = bytes == blockBytes and opaqueBlock or opaqueBlock:sub(1, bytes + 1)
                if not ffi.string(pixels + offset, bytes):find(pattern) then
                    opaque = false
                    break
                end
            end
        end
    else
        local w, h = data:getDimensions()
        for y = 0, h - 1 do
            for x = 0, w - 1 do
                local _, _, _, alpha = data:getPixel(x, y)
                if alpha ~= 1 then
                    opaque = false
                    break
                end
            end
            if not opaque then
                break
            end
        end
    end
    images[image] = opaque
end

function Opacity.image(image)
    return images[image] == true
end

function Opacity.object(object)
    local surface = object._surfaceAppearance
    return object._renderOpacity == 1
        and (object.color[4] or 1) == 1
        and not object.blend
        and not object._surfaceBlend
        and (object._effectiveCutoff or object.alphaCutoff or 0) < 1
        and (surface and surface.alphaMode == 'Opaque' or Opacity.image(object.image))
end

return Opacity
