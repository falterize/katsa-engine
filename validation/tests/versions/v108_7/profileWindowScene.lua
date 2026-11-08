-- A scene in its own window records profiler frames like the main one.
local Module = {}

function Module.run(self)
    local window = katsa.window.create(320, 200, { title = 'Profiled' })
    local handle = window:runScene('platformer', { fps = 1000 })
    local manager = handle.manager
    manager.profiler:startRecording({ scene = 'platformer' })
    for _ = 1, 4 do
        handle:step(0.05)
    end
    local recording = manager.profiler.recording
    self:check(recording and #recording.rows >= 2, 'The window scene fills the profiler recording')
    handle:close()
end

return Module
