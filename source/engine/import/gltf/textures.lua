local Textures = {}

function Textures.create(document, binary, path, resources)
    local images = {}
    local directory = path:match('^(.*[/])') or ''

    local function texture(index)
        local definition = assert(document.textures[index + 1], 'Missing GLB texture')
        local source = definition.source
        local image = images[index]
        if not image then
            local sourceImage = assert(document.images[source + 1], 'Missing GLB image')
            if sourceImage.bufferView then
                assert(
                    sourceImage.mimeType == 'image/png' or sourceImage.mimeType == 'image/jpeg',
                    'GLB texture must be PNG or JPEG'
                )
                local view = document.bufferViews[sourceImage.bufferView + 1]
                local bytes =
                    binary:sub((view.byteOffset or 0) + 1, (view.byteOffset or 0) + view.byteLength)
                local file = katsa.filesystem.newFileData(
                    bytes,
                    'embedded.' .. (sourceImage.mimeType == 'image/png' and 'png' or 'jpg')
                )
                image = resources:loadImage(file, path .. '#image' .. tostring(definition.source))
                file:release()
            else
                assert(
                    sourceImage.uri and not sourceImage.uri:match('^data:'),
                    'Embedded data URI images require conversion to GLB bufferViews'
                )
                image = resources:image(directory .. sourceImage.uri)
            end
            local sampler = definition.sampler and document.samplers[definition.sampler + 1] or {}
            image:setFilter(
                (
                    sampler.minFilter == 9728
                    or sampler.minFilter == 9984
                    or sampler.minFilter == 9986
                )
                        and 'nearest'
                    or 'linear',
                sampler.magFilter == 9728 and 'nearest' or 'linear'
            )
            local wraps = { [33071] = 'clamp', [33648] = 'mirroredrepeat', [10497] = 'repeat' }
            image:setWrap(wraps[sampler.wrapS] or 'repeat', wraps[sampler.wrapT] or 'repeat')
            images[index] = image
        end
        return image
    end
    return texture
end

return Textures
