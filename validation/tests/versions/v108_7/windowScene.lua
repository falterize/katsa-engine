-- Every extra window has the main window's controls, and can host a whole scene of its own.
local Module = {}

function Module.run(self)
    local win = katsa.window
    local width, height = win.getDesktopSize()
    self:check(width > 0 and height > 0 and win.getDisplayCount() >= 1, 'The desktop size is known')
    local window = assert(win.create(320, 200, { title = 'Probe', resizable = true }))
    window:setSize(400, 260)
    local w, h = window:getSize()
    self:check(w == 400 and h == 260, 'A window can be resized in pixels')
    window:setBorderless(true)
    self:check(window:isBorderless(), 'A window can hide its title bar')
    window:setResizable(false)
    self:check(not window:isResizable(), 'A window can stop being resizable')
    window:setMinimumSize(200, 100)
    local mw = window:getMinimumSize()
    self:check(mw == 200, 'A window has its own minimum size')
    self:check(window:getFullscreen() == false and window:isFullscreen() == false, 'A window starts windowed')
    for _, name in ipairs({ 'setFullscreen', 'toggleFullscreen', 'setAlwaysOnTop', 'center', 'minimize', 'maximize', 'restore', 'focus', 'getDisplay' }) do
        self:check(type(window[name]) == 'function', 'Window method ' .. name)
    end
    window:close()

    -- A scene in its own window, next to the main scene.
    local second = assert(win.create(480, 300, { title = 'Scene window', resizable = true }))
    local scene = second:runScene('objects', { fps = 1000 })
    self:check(scene:isOpen() and scene:getScene() ~= nil, 'A scene loads into its own window')
    local hosted = scene:getScene()
    local before = hosted.time
    for _ = 1, 5 do
        scene:step(0.02)
    end
    self:check(hosted.time > before, 'The window scene is updated by its own manager')
    self:check(hosted ~= self.manager.stack[#self.manager.stack], 'It is not the main scene')
    second:setSize(520, 340)
    scene:step(0.02)
    scene:step(0.02)
    self:check(scene.width == 520 and scene.height == 340, 'The scene is re-fitted when its window is resized')
    scene:receive('mousemoved', 10, 10, 1, 1)
    scene:receive('keypressed', 'a', 'a', false)
    scene:receive('keyreleased', 'a', 'a')
    scene:close()
    self:check(not second:isOpen() and not scene:isOpen(), 'Closing the scene closes its window')
end

return Module
