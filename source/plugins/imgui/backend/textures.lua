local ffi = require('ffi')

-- Textures ImGui asks the backend for (the font atlas; `ImGuiBackendFlags_RendererHasTextures`).
-- ImGui keeps the pixels and a status per texture; this module turns requests into katsa images
-- and hands back their ids. Images are rebuilt whole on every update: atlases change rarely.
local Textures = {}
Textures.__index = Textures

function Textures.new(C)
    return setmetatable({ C = C, images = {}, nextId = 1 }, Textures)
end

local function build(texture)
    local ImageModule = require('source.katsa.image')
    local width, height = texture.Width, texture.Height
    local data = ImageModule.newImageData(width, height, 'rgba8')
    local target = ffi.cast('uint8_t*', data:getPointer())
    local source = texture.Pixels
    if texture.Format == ffi.C.ImTextureFormat_Alpha8 then
        -- Coverage becomes white with that alpha, so vertex colours tint the glyphs.
        for i = 0, width * height - 1 do
            target[i * 4], target[i * 4 + 1], target[i * 4 + 2] = 255, 255, 255
            target[i * 4 + 3] = source[i]
        end
    else
        ffi.copy(target, source, width * height * 4)
    end
    local image = katsa.graphics.newImage(data)
    image:setFilter('linear', 'linear')
    data:release()
    return image
end

-- Applies every pending request of this frame's draw data.
function Textures:update(drawData)
    local C = self.C
    local list = drawData.Textures
    if list == nil then
        return
    end
    for i = 0, list.Size - 1 do
        local texture = list.Data[i]
        local status = texture.Status
        if status == C.ImTextureStatus_WantCreate or status == C.ImTextureStatus_WantUpdates then
            local id = tonumber(texture.TexID)
            if id == 0 then
                id = self.nextId
                self.nextId = id + 1
                texture.TexID = id
            elseif self.images[id] then
                self.images[id]:release()
            end
            self.images[id] = build(texture)
            texture.Status = C.ImTextureStatus_OK
        elseif status == C.ImTextureStatus_WantDestroy then
            local id = tonumber(texture.TexID)
            if self.images[id] then
                self.images[id]:release()
                self.images[id] = nil
            end
            texture.TexID = 0
            texture.Status = C.ImTextureStatus_Destroyed
        end
    end
end

function Textures:get(id)
    return self.images[id]
end

function Textures:release()
    for id, image in pairs(self.images) do
        image:release()
        self.images[id] = nil
    end
end

return Textures
