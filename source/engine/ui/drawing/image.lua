local Image = {}

function Image.rect(mode, w, h, iw, ih)
    assert(
        mode == 'Fit' or mode == 'Crop' or mode == 'Stretch' or mode == 'Tile',
        'Invalid FitMode'
    )
    if mode == 'Stretch' then
        return 0, 0, w, h
    end
    local s = (mode == 'Fit' and math.min or math.max)(w / iw, h / ih)
    return (w - iw * s) * 0.5, (h - ih * s) * 0.5, iw * s, ih * s
end

function Image.draw(ui, node)
    local g = katsa.graphics
    local component = require('../../components.image')
    local world = ui._sceneWorld or ui.owner and ui.owner._world
    local image = component.resolve(ui.resources, node, node.image, world and world.environment)
    local iw, ih = image:getDimensions()
    local w, h = node._width, node._height
    if w <= 0 or h <= 0 then
        return
    end
    g.push('all')
    require('./modifiers').bindGradient(ui, node, 'Image')
    local style = require('../style')
    local c = style.color(node, 'image')
    g.setColor(c[1], c[2], c[3], style.alpha(node, 'image', c))
    local mode = node.fitMode or 'Stretch'
    if node.imageMode == 'Tiles' or node.imageMode == 'Texture' then
        mode = 'Tile'
    end
    local ax, ay, aw, ah = component.region(node, iw, ih)
    if mode == 'Tile' then
        local u, v, uw, vh = component.uv(node, iw, ih, w, h)
        node._imageQuad = node._imageQuad or node:own(g.newQuad(0, 0, iw, ih, iw, ih))
        node._imageQuad:setViewport(u * iw, v * ih, uw * iw, vh * ih, iw, ih)
        g.draw(image, node._imageQuad, node._x, node._y, 0, w / (uw * iw), h / (vh * ih))
    elseif node.imageMode == 'Atlas' or node.imageMode == 'XML' then
        local x, y, dw, dh = Image.rect(mode, w, h, aw, ah)
        node._imageQuad = node._imageQuad or node:own(g.newQuad(ax, ay, aw, ah, iw, ih))
        if mode == 'Crop' then
            local vw, vh = w / dw * aw, h / dh * ah
            node._imageQuad:setViewport(ax + (aw - vw) * 0.5, ay + (ah - vh) * 0.5, vw, vh, iw, ih)
            g.draw(image, node._imageQuad, node._x, node._y, 0, w / vw, h / vh)
        else
            node._imageQuad:setViewport(ax, ay, aw, ah, iw, ih)
            g.draw(image, node._imageQuad, node._x + x, node._y + y, 0, dw / aw, dh / ah)
        end
    elseif mode == 'Crop' then
        local _, _, dw, dh = Image.rect(mode, w, h, iw, ih)
        local vw, vh = w / dw * iw, h / dh * ih
        node._imageQuad = node._imageQuad or node:own(g.newQuad(0, 0, iw, ih, iw, ih))
        node._imageQuad:setViewport((iw - vw) * 0.5, (ih - vh) * 0.5, vw, vh, iw, ih)
        g.draw(image, node._imageQuad, node._x, node._y, 0, w / vw, h / vh)
    else
        local x, y, dw, dh = Image.rect(mode, w, h, iw, ih)
        g.draw(image, node._x + x, node._y + y, 0, dw / iw, dh / ih)
    end
    g.pop()
end

return Image
