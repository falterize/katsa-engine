local Flipbook = {}
Flipbook.__index = Flipbook

function Flipbook.new(target, clips)
    assert(target and clips, 'Flipbook requires an atlas target and named clips')
    for _, clip in pairs(clips) do
        assert(#clip.frames > 0 and clip.fps > 0, 'A clip requires frames and positive fps')
    end
    return setmetatable({ target = target, clips = clips, time = 0, playing = true }, Flipbook)
end

function Flipbook:play(name, restart)
    local clip = assert(self.clips[name], 'Unknown flipbook clip: ' .. tostring(name))
    if self.name ~= name or restart then
        self.name, self.time, self.frame = name, 0, 1
        self.target.atlasFrame = clip.frames[1]
    end
    self.playing = true
end

function Flipbook:pause()
    self.playing = false
end

function Flipbook:update(dt)
    assert(dt >= 0 and dt < math.huge, 'Invalid flipbook delta')
    if not self.playing or not self.name or self.target.destroyed then
        return
    end
    local clip = self.clips[self.name]
    self.time = self.time + dt
    local frame = math.floor(self.time * clip.fps)
    if clip.loop ~= false then
        frame = frame % #clip.frames
        self.time = self.time % (#clip.frames / clip.fps)
    else
        frame = math.min(frame, #clip.frames - 1)
    end
    if self.frame ~= frame + 1 then
        self.frame = frame + 1
        self.target.atlasFrame = clip.frames[self.frame]
    end
end

return Flipbook
