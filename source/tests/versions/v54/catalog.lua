local Test = {}
Test.__index = Test

function Test.new(manager)
    return setmetatable({ manager = manager }, Test)
end

function Test:update()
    if self.done then
        return
    end
    self.done = true
    local samples = require('source.game.scenes.nodeCatalog.scripts.catalog.samples')
    local groups = {}
    local count = 0
    for _, name in ipairs(samples.names()) do
        local zone = samples.zone(name)
        groups[zone] = groups[zone] or {}
        table.insert(groups[zone], name)
    end
    for zone, names in pairs(groups) do
        local scene, err = self.manager:switch(require('source.game.runtime.game').new, zone)
        assert(scene, err)
        for _, kind in ipairs(names) do
            local node = samples.prepare(scene, kind)
            assert(node.className == kind, 'Catalog class mismatch: ' .. kind)
            count = count + 1
            print('PASS live node catalog ' .. kind .. ' / ' .. zone)
        end
        scene.ui:layout()
    end
    print('PASSED ' .. count .. ' live node catalog samples')
    katsa.event.quit()
end

function Test:draw() end
return Test
