-- Reuse the existing rendering/physics regression suite; add only affected integration paths.
local T = {}

local function smoke(test)
    local function syntax(directory)
        for _, name in ipairs(katsa.filesystem.getDirectoryItems(directory)) do
            local path = directory .. '/' .. name
            if katsa.filesystem.getInfo(path, 'directory') then
                syntax(path)
            elseif name:match('%.lua$') then
                assert(loadstring(katsa.filesystem.read(path), path))
            end
        end
    end
    syntax('source')
    test:check(true, 'All first-party Lua files compile after module extraction')
    local scene = test.manager:switch(require('source.game.runtime.game').new, 'original')
    local mesh = scene.world:create(
        'Mesh3D',
        { name = 'InspectorProbe', position = { 0, 0, 30 }, size = { 4, 4, 4 } }
    )
    local Properties = require('source.engine.editor.inspectors.properties')
    local fields = {}
    for _, field in ipairs(Properties.list(mesh)) do
        fields[field.key] = field
    end
    test:check(
        Properties.set(scene, mesh, fields.position, '12', 1) and mesh.position[1] == 12,
        'Inspector typed-vector editing still updates authored values'
    )
    test:check(
        not Properties.set(scene, mesh, fields.position, 'nan', 1) and mesh.position[1] == 12,
        'Inspector rejects invalid input without changing the node'
    )
    scene.workspace:select(mesh)
    local popup = require('source.engine.editor.panels.popup').new(scene.workspace, fields.color)
    popup:colorEditor()
    local red = mesh.color[1]
    popup:setRGB({ 0.3, 0.4, 0.5 })
    popup:close(false)
    test:check(mesh.color[1] == red, 'Color popup cancellation restores its original value')
    scene.workspace:toggle(false)
    scene.ui:layout()
    local j, c = scene.controls.joystick, scene.controls.camera
    local scale, ox, oy = scene.ui.scale, scene.ui.offsetX, scene.ui.offsetY
    local jx, jy = ox + j.x * scale, oy + j.y * scale
    local cx, cy = ox + (c.x + c.width * 0.8) * scale, oy + (c.y + c.height * 0.7) * scale
    scene.input:press('move-finger', jx, jy)
    scene.input:press('look-finger', cx, cy)
    test:check(
        scene.input.joystickId == 'move-finger' and scene.input.cameraId == 'look-finger',
        'Independent joystick and camera touches can be captured together'
    )
    scene.input:release('look-finger', cx, cy)
    test:check(
        scene.input.joystickId == 'move-finger' and scene.input.cameraId == nil,
        'Releasing camera touch preserves the movement touch'
    )
    scene.input:cancel('move-finger')
    test:check(scene.input.joystickId == nil, 'Cancelled movement touch clears its capture')
    local voice = scene.audio:play('assets/audio/effects/click.wav', { group = 'ui' })
    scene.audio:apply(voice)
    voice:pause()
    voice:resume()
    voice:release()
    test:check(voice.released, 'Audio playback, application and lifetime remain compatible')
    for _, zone in ipairs({ 'uiGallery', 'animationLab', 'shaderLab', 'audioNodes', 'particles' }) do
        scene = test.manager:switch(require('source.game.runtime.game').new, zone)
        scene:update(1 / 60, 1 / 60)
        scene.renderer:draw(scene.world, scene.camera, 1, true)
        scene.ui:draw()
    end
    test:check(
        #test.manager.journal.entries == 0,
        'UI, Ramp, shaders, audio and particle scenes run without journal errors'
    )
    print('PASSED ' .. test.count .. ' v84 regression/integration checks')
    katsa.event.quit()
end

function T.new(manager)
    local base = require('source.tests.versions.v83.runtime').new(manager)
    base.finish = smoke
    return base
end

return T
