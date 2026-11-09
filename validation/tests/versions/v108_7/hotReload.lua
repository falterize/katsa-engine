-- Hot reload: change detection, classification, texture replacement and locale reload.
local HotReload = require('source.engine.debug.hotReload')
local Localization = require('source.engine.localization')

local Tests = {}

function Tests.run(tester)
    local classify = HotReload.classify
    tester:check(
        classify('assets/locales/ru.lua') == 'locale'
            and classify('assets/tilesets/a.lua') == 'tileset'
            and classify('assets/textures/a.png') == 'image'
            and classify('source/game/scenes/x/main.lua') == 'restart'
            and classify('assets/shaders/engine/world.glsl') == 'restart'
            and classify('source/engine/ui/init.lua') == 'engine',
        'changes are classified by what they need'
    )

    local fs = katsa.filesystem
    fs.createDirectory('hotreload')
    local function write(path, text)
        assert(fs.write(path, text))
    end
    write('hotreload/scene.lua', 'return 1')
    write('hotreload/en.lua', "return { strings = { hi = 'Hi' } }")
    local restarts, logged = 0, {}
    local manager = tester.manager
    local watcher = HotReload.new(manager, {
        roots = { 'hotreload' },
        interval = 0,
        settle = 0,
        restart = function()
            restarts = restarts + 1
        end,
        log = function(text)
            logged[#logged + 1] = text
        end,
    })
    watcher:update(0.1)
    tester:check(restarts == 0 and #logged == 0, 'untouched files cause nothing')
    write('hotreload/scene.lua', 'return 22')
    watcher:update(0.1)
    watcher:update(0.1)
    tester:check(restarts == 1, 'an edited scene file re-creates the scene once')

    -- A locale file read through resources is reloaded in place.
    local service = Localization.new()
    local resources = manager.resources:scope()
    service:loadFile(resources, 'hotreload/en.lua', 'en')
    tester:check(service:t('hi') == 'Hi', 'locale loaded from a file')
    write('hotreload/en.lua', "return { strings = { hi = 'Hello there' } }")
    tester:check(service:reloadPath(resources:canonical('hotreload/en.lua')) and service:t('hi') == 'Hello there', 'a changed locale file is read again')

    -- Textures: same size is replaced in place, a different size asks for a new texture.
    local data = katsa.image.newImageData(4, 4)
    data:encode('png', 'hotreload/tex.png')
    local image = resources:image('hotreload/tex.png')
    local path = resources:canonical('hotreload/tex.png')
    tester:check(image ~= nil and resources:reloadImage(path) >= 1, 'a loaded texture is reloaded in place')
    katsa.image.newImageData(8, 8):encode('png', 'hotreload/tex.png')
    tester:check(resources:reloadImage(path) == false, 'a texture of another size needs a new texture')
    resources:release()
    fs.remove('hotreload/scene.lua')
    fs.remove('hotreload/en.lua')
    fs.remove('hotreload/tex.png')
    fs.remove('hotreload')
end

return Tests
