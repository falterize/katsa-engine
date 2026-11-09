-- Draws one source texture over a whole target with a post shader.
local Fullscreen = {}

-- Sends a uniform only when the shader kept it (the compiler drops unused ones).
function Fullscreen.send(shader, name, ...)
    if shader:hasUniform(name) then
        shader:send(name, ...)
    end
end

-- `target` nil means the screen. `blend` defaults to 'replace' for canvases; the screen keeps
-- the renderer's premultiplied alpha blit.
function Fullscreen.draw(source, shader, target, blend)
    local g = katsa.graphics
    g.push('all')
    g.origin()
    g.setScissor()
    g.setStencilTest()
    g.setDepthMode()
    g.setMeshCullMode('none')
    g.setWireframe(false)
    g.setCanvas(target)
    g.setShader(shader)
    g.setColor(1, 1, 1, 1)
    if blend then
        g.setBlendMode(blend)
    elseif target then
        g.setBlendMode('replace')
    else
        g.setBlendMode('alpha', 'premultiplied')
    end
    g.draw(source)
    g.pop()
end

-- Loads (once) and caches a post shader by file name from assets/shaders/engine/post.
function Fullscreen.shader(post, renderer, name)
    local shader = post.shaders[name]
    if not shader then
        shader = renderer.resources:own(
            katsa.graphics.newShader(
                require('source.engine.graphics.shaders.shaderSource').read(
                    'assets/shaders/engine/post/' .. name .. '.glsl'
                )
            )
        )
        post.shaders[name] = shader
    end
    return shader
end

return Fullscreen
