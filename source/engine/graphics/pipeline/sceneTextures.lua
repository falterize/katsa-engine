local SceneDepth = require('../post.sceneDepth')

-- Scene textures for spatial shaders: `hint_screen_texture` (the colour drawn so far) and
-- `hint_depth_texture` (the opaque depth). Both are made on first use in a frame, so a scene
-- without such a shader pays nothing; they are taken before the transparent pass, which is where
-- materials that read them are drawn.
local SceneTextures = {}

-- A copy of the opaque colour, refreshed once per frame.
function SceneTextures.screen(renderer)
    local g = katsa.graphics
    local copy = renderer._screenCopy
    local width, height = renderer.canvas:getPixelDimensions()
    if not copy or copy:getPixelWidth() ~= width or copy:getPixelHeight() ~= height then
        if copy then
            copy:release()
        end
        copy = g.newCanvas(
            renderer.width,
            renderer.height,
            { format = 'rgba8', dpiscale = renderer.density }
        )
        copy:setFilter('linear', 'linear')
        renderer._screenCopy, renderer._screenFrame = copy, nil
    end
    if renderer._screenFrame ~= renderer.frame then
        renderer._screenFrame = renderer.frame
        g.push('all')
        g.origin()
        g.setScissor()
        g.setStencilTest()
        g.setDepthMode()
        g.setCanvas(copy)
        g.setShader()
        g.setBlendMode('replace')
        g.setColor(1, 1, 1, 1)
        g.draw(renderer.canvas)
        g.pop()
    end
    return copy
end

-- Depth of the opaque scene, drawn once per frame (the early depth pass is reused when it ran).
function SceneTextures.depth(renderer)
    local g = katsa.graphics
    if renderer._depthFrame ~= renderer.frame then
        renderer._depthFrame = renderer.frame
        g.push('all')
        renderer._sceneDepth = SceneDepth.get(renderer)
        g.pop()
    end
    return renderer._sceneDepth
end

function SceneTextures.bind(renderer, material, shader)
    if material.screenUniform and shader:hasUniform(material.screenUniform) then
        shader:send(material.screenUniform, SceneTextures.screen(renderer))
    end
    if material.depthUniform and shader:hasUniform(material.depthUniform) then
        shader:send(material.depthUniform, SceneTextures.depth(renderer))
    end
end

function SceneTextures.release(renderer)
    if renderer._screenCopy then
        renderer._screenCopy:release()
        renderer._screenCopy, renderer._screenFrame = nil, nil
    end
    renderer._sceneDepth, renderer._depthFrame = nil, nil
end

return SceneTextures
