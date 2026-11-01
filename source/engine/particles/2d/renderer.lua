local M = require('source.engine.math.math3d')
local Sequence = require('source.engine.animation.sequence')
local Visibility = require('source.engine.particles.2d.visibility')
local Renderer = {}
local blendModes = { Alpha = 'alpha', Add = 'add', Multiply = 'multiply' }
local function sample(e, key, t, out)
    return Sequence.evaluate(e.lifetimeRamp.bindings[key], t, e.lifetimeRamp.interpolation, out)
end

function Renderer.draw(system)
    local g, ui = katsa.graphics, system.world
    local started = katsa.timer.getTime()
    system.stats.rendered, system.stats.drawCalls = 0, 0
    system.shader = system.shader
        or ui.resources:cached('shader', 'particles2D', function(owner)
            return owner:own(g.newShader('assets/shaders/particles/sprite2d.glsl'))
        end)
    for _, e in ipairs(system.emitters) do
        if Visibility.relevant(e, ui.currentCamera, true) then
            local image =
                require('source.engine.components.image').resolve(ui.resources, e, e.texture)
            local count, capacity = #e.particles, e._batchCapacity or 0
            if count > capacity then
                if e._spriteBatch then
                    e._spriteBatch:release()
                end
                capacity = math.max(16, capacity)
                while capacity < count do
                    capacity = capacity * 2
                end
                e._spriteBatch = g.newSpriteBatch(image, capacity, 'stream')
                e._batchCapacity = capacity
            end
            local batch = e._spriteBatch
            if batch then
                batch:clear()
                batch:setTexture(image)
                local iw, ih = image:getDimensions()
                e._particleQuad = e._particleQuad or g.newQuad(0, 0, iw, ih, iw, ih)
                local qw, qh = iw, ih
                local m, opacity = e:getRenderWorldMatrix(), e:getEffectiveOpacity()
                for _, p in ipairs(e.particles) do
                    local t = math.min(1, p.age / p.life)
                    local size = p.size * sample(e, 'size', t)
                    local x, y = p.x, p.y
                    if p.space == 'Local' then
                        x, y = M.transform(m, x, y, 0)
                    end
                    if size > 0 and Visibility.point(e, ui.currentCamera, x, y, 0, size) then
                        p.renderColor = sample(e, 'color', t, p.renderColor)
                        local color = p.renderColor
                        local alpha = math.max(0, math.min(1, 1 - sample(e, 'transparency', t)))
                            * opacity
                        local brightness = e.brightness
                        if not e.unlit then
                            local environment = ui.environment
                            local ambient = environment and environment.ambient or { 255, 255, 255 }
                            brightness = brightness
                                * (environment and environment.brightness or 1)
                                * (ambient[1] + ambient[2] + ambient[3])
                                / (3 * 255)
                        end
                        batch:setColor(
                            color[1] * brightness,
                            color[2] * brightness,
                            color[3] * brightness,
                            alpha
                        )
                        local angle = p.rotation + math.rad(sample(e, 'rotation', t))
                        if e.orientation == 'Velocity' then
                            angle = angle + math.atan2(p.vy, p.vx)
                        end
                        local co, si = math.cos(angle), math.sin(angle)
                        local a, b, c, d = co, si, -si, co
                        if e.orientation == 'Axes' then
                            a, b, c, d =
                                e.axisRight[1] * co + e.axisUp[1] * si,
                                e.axisRight[2] * co + e.axisUp[2] * si,
                                -e.axisRight[1] * si + e.axisUp[1] * co,
                                -e.axisRight[2] * si + e.axisUp[2] * co
                        end
                        if p.space == 'Local' or e.orientation == 'Axes' then
                            a, b, c, d =
                                m[1] * a + m[2] * b,
                                m[5] * a + m[6] * b,
                                m[1] * c + m[2] * d,
                                m[5] * c + m[6] * d
                        end
                        a, b, c, d = a * size / qw, b * size / qw, -c * size / qh, -d * size / qh
                        local sx = math.sqrt(a * a + b * b)
                        if sx > 0.000001 then
                            local sy, shear = (a * d - b * c) / sx, (a * c + b * d) / (sx * sx)
                            local u, v, uw, vh =
                                require('source.engine.particles.image').uv(e, p, image, size)
                            e._particleQuad:setViewport(u * iw, v * ih, uw * iw, vh * ih, iw, ih)
                            -- Keep geometry size independent of the UV repeat/atlas rectangle.
                            local repeatX, repeatY = uw, vh
                            batch:add(
                                e._particleQuad,
                                x,
                                y,
                                math.atan2(b, a),
                                sx / repeatX,
                                sy / repeatY,
                                qw * repeatX / 2,
                                qh * repeatY / 2,
                                shear * repeatX / repeatY,
                                0
                            )
                            system.stats.rendered = system.stats.rendered + 1
                        end
                    end
                end
                g.push('all')
                g.setShader(system.shader)
                system.shader:send('multiplyMode', e.blendMode == 'Multiply')
                g.setColor(1, 1, 1, 1)
                g.setBlendMode(
                    blendModes[e.blendMode],
                    e.blendMode == 'Multiply' and 'premultiplied' or 'alphamultiply'
                )
                g.draw(batch)
                system.stats.drawCalls = system.stats.drawCalls + 1
                g.pop()
            end
        end
    end
    system.stats.drawMilliseconds = (katsa.timer.getTime() - started) * 1000
end
return Renderer
