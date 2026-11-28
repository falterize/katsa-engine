local Node = require('../../nodes')
local ImageDraw = require('../drawing.image')

-- Plays a video file (any format FFmpeg reads: MP4, MOV, MKV, WebM, AVI, OGV ...) with its sound.
-- Decoding runs on a worker thread; the node shows the frame that is due, so it works on screen UI,
-- BillboardUI and SurfaceUI alike. Playback pauses by itself while the node is not drawn.
local Class = Node.define('VideoFrame', 'Frame')

local function player(self)
    return rawget(self, '_player')
end

-- Live playback state, read and written through the node (`video.time = 12`).
Class.computed = {
    time = {
        get = function(self)
            local current = player(self)
            return current and current.slots and current:getTime() or rawget(self, '_pendingTime') or 0
        end,
        set = function(self, value)
            local current = player(self)
            if current then
                current:seek(value)
            else
                rawset(self, '_pendingTime', value)
            end
        end,
    },
    duration = {
        get = function(self)
            local current = player(self)
            return current and current.duration or 0
        end,
    },
    status = {
        get = function(self)
            local current = player(self)
            if current then
                return current.state == 'error' and ('Error: ' .. tostring(current.error)) or current.state
            end
            return rawget(self, '_failure') and ('Error: ' .. rawget(self, '_failure'))
                or (self.source == '' and 'Empty' or 'Loading')
        end,
    },
}

Class.propertySchema = {
    source = {},
    playing = {},
    looped = {},
    volume = { min = 0, max = 1 },
    speed = { min = 0.1, max = 4 },
    time = { get = Class.computed.time.get },
    duration = { readOnly = true, get = Class.computed.duration.get },
    status = { readOnly = true, get = Class.computed.status.get },
    fitMode = { options = { 'Fit', 'Crop', 'Stretch' } },
    pixelate = {},
    imageColor = {},
    imageTransparency = { min = 0, max = 1 },
    maxResolution = { min = 0, max = 4320 },
}

local function unload(self)
    local current = player(self)
    if current then
        current:release()
    end
    rawset(self, '_player', nil)
    rawset(self, '_failure', nil)
    self._animating = false
end

function Class.initialize(self)
    self.source = self.source or ''
    self.playing = self.playing == true
    self.looped = self.looped == true
    self.volume = self.volume or 1
    self.speed = self.speed or 1
    self.fitMode = self.fitMode or 'Fit'
    self.pixelate = self.pixelate == true
    self.maxResolution = self.maxResolution or 0
    -- The decoder thread, audio source and GPU image go with the node.
    self:onDestroy(function()
        unload(self)
    end)
end

function Class:play()
    self.playing = true
end

function Class:pause()
    self.playing = false
end

-- Pauses and rewinds to the first frame.
function Class:stop()
    self.playing = false
    self.time = 0
end

local function load(self, ui)
    unload(self)
    local source = self.source
    rawset(self, '_loaded', source)
    if source == '' then
        return
    end
    local created, message = require('source.engine.video.player').new({
        path = ui.resources:canonical(source),
        loop = self.looped,
        volume = self.volume,
        speed = self.speed,
        pixelate = self.pixelate,
        maxHeight = self.maxResolution,
        onFinished = function()
            self.playing = false
            self:emit('finished', self)
        end,
        onLooped = function()
            self:emit('looped', self)
        end,
    })
    if not created then
        rawset(self, '_failure', message)
        local journal = ui.resources.store and ui.resources.store.journal
        if journal then
            journal:record('Resources', 'Video: ' .. tostring(message), self, source)
        end
        return
    end
    rawset(self, '_player', created)
    if rawget(self, '_pendingTime') then
        created:seek(rawget(self, '_pendingTime'))
        rawset(self, '_pendingTime', nil)
    end
    self._wantPlay = nil
end

-- Called every frame from UI:update and from drawSelf: picks up property edits, steps the player.
function Class:tickVideo(ui)
    local now = katsa.timer.getTime()
    local last = rawget(self, '_lastTick')
    if last and now - last < 0.0001 then
        return
    end
    rawset(self, '_lastTick', now)
    local dt = last and math.min(now - last, 0.25) or 0
    if rawget(self, '_loaded') ~= self.source then
        load(self, ui)
    end
    local current = player(self)
    if not current then
        return
    end
    current.loop = self.looped == true
    if current.volume ~= self.volume then
        current:setVolume(self.volume)
    end
    if current.speed ~= self.speed then
        current:setSpeed(self.speed)
    end
    -- Not drawn for a moment (hidden, off screen, behind another UI): playback holds still.
    local seen = now - (rawget(self, '_drawnAt') or now) < 0.25
    local want = self.playing == true and seen
    if want ~= self._wantPlay then
        self._wantPlay = want
        if want then
            current:play()
        else
            current:pause()
        end
    end
    current:update(dt)
    self._animating = current.state == 'playing'
end

function Class:drawSelf(ui)
    Class.base.drawSelf(self, ui)
    rawset(self, '_drawnAt', katsa.timer.getTime())
    ui._videos = ui._videos or {}
    ui._videos[self] = true
    self:tickVideo(ui)
    local w, h = self._width, self._height
    if w <= 0 or h <= 0 then
        return
    end
    local g = katsa.graphics
    local current = player(self)
    local image = current and current.image
    if not image then
        if rawget(self, '_failure') or current and current.state == 'error' then
            -- A video that cannot play shows the engine's diagnostic checker, like a missing image.
            g.push('all')
            g.setColor(1, 1, 1, 1)
            local missing = ui.resources:image(nil)
            local iw, ih = missing:getDimensions()
            g.draw(missing, self._x, self._y, 0, w / iw, h / ih)
            g.pop()
        end
        return
    end
    local iw, ih = image:getDimensions()
    local style = require('source.engine.ui.style')
    local color = style.color(self, 'image')
    g.push('all')
    g.setColor(color[1], color[2], color[3], style.alpha(self, 'image', color))
    local mode = self.fitMode
    if mode == 'Crop' then
        local _, _, dw, dh = ImageDraw.rect(mode, w, h, iw, ih)
        local vw, vh = w / dw * iw, h / dh * ih
        self._quad = self._quad or self:own(g.newQuad(0, 0, iw, ih, iw, ih))
        self._quad:setViewport((iw - vw) * 0.5, (ih - vh) * 0.5, vw, vh, iw, ih)
        g.draw(image, self._quad, self._x, self._y, 0, w / vw, h / vh)
    else
        local x, y, dw, dh = ImageDraw.rect(mode == 'Stretch' and 'Stretch' or 'Fit', w, h, iw, ih)
        g.draw(image, self._x + x, self._y + y, 0, dw / iw, dh / ih)
    end
    g.pop()
end

return Class
