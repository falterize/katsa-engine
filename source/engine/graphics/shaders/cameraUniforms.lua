-- Camera uniforms every spatial program may declare (see docs/guides/rendering/shaders.md).
local CameraUniforms = {}

local size = {}

-- viewProjection, viewMatrix, projectionMatrix, cameraPosition and viewportSize (pixels).
function CameraUniforms.send(shader, camera, width, height)
    if shader:hasUniform('viewProjection') then
        shader:send('viewProjection', 'row', camera.viewProjection)
    end
    if shader:hasUniform('viewMatrix') then
        shader:send('viewMatrix', 'row', camera.view)
    end
    if shader:hasUniform('projectionMatrix') then
        shader:send('projectionMatrix', 'row', camera.projection)
    end
    if shader:hasUniform('cameraPosition') then
        shader:send('cameraPosition', camera.worldPosition or camera.position)
    end
    if shader:hasUniform('viewportSize') then
        size[1], size[2] = width, height
        shader:send('viewportSize', size)
    end
end

return CameraUniforms
