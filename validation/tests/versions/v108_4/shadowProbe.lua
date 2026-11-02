-- Diagnostic: captures consecutive frames of animationPhysicsLab (KATSA_SHOT=<dir>).
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    local self = setmetatable(Previous.new(manager), Tests)
    self.frame = 0
    return self
end

function Tests:update()
    self.frame = self.frame + 1
    if self.frame == 1 and os.getenv('KATSA_PROF') then
        require('jit.p').start('Fl1i1', os.getenv('KATSA_PROF'))
    end
    if self.frame == 1 then
        self.scene = assert(self.manager:switch(require('source.game.runtime.game').new, os.getenv('KATSA_SCENE') or 'animationPhysicsLab'))
    end
end

function Tests:draw()
    local dir = os.getenv('KATSA_SHOT')
    local scene = self.scene
    if self.frame >= 40 and os.getenv('KATSA_MOVE') and scene and scene.camera then
        -- Sweep the camera sideways, like a player dragging the view.
        local t = (self.frame - 40) * 0.05
        scene.camera.position = { math.sin(t) * 12, 65, -105 }
    end
    if self.frame == 30 and scene and scene.world then
        local sh = scene.world.environment.shadows
        for env, key in pairs({ KATSA_BIAS = 'bias', KATSA_NBIAS = 'normalBias', KATSA_RES = 'resolution', KATSA_DIST = 'distance', KATSA_SAMPLES = 'filterSamples' }) do
            if os.getenv(env) then sh[key] = tonumber(os.getenv(env)) end
        end
    end
    if self.frame == 40 and os.getenv('KATSA_NOSHADOW') and scene and scene.world then
        scene.world.environment.shadows.enabled = false
    end
    if os.getenv('KATSA_TOGGLE') and scene and scene.world then
        scene.world.environment.shadows.enabled = not (self.frame >= 68)
    end
    if self.frame == 30 and os.getenv('KATSA_SHADOWVIEW') and scene and scene.world then
        scene.world.lighting.debug.shadowView = true
    end
    if self.frame == 30 and os.getenv('KATSA_PATHDBG') and scene and scene.world then
        local debug = scene.world.environment.debug
        if debug.pathfinding then
            debug.pathfinding.enabled = true
        end
    end
    if self.frame == 40 and os.getenv('KATSA_NOCAST') and scene and scene.world then
        for _, o in ipairs(scene.world.objects) do
            if o.skin then o.castShadow = false end
        end
    end
    if self.frame == 40 and os.getenv('KATSA_NORECV') and scene and scene.world then
        for _, o in ipairs(scene.world.objects) do
            if o.skin then o.receiveShadow = false end
        end
    end
    if self.frame == 40 and os.getenv('KATSA_FREEZE') and scene and scene.world then
        scene.world.timeScale = 0
    end
    if (self.frame == 66 or self.frame == 72) and os.getenv('KATSA_SURF') and scene then
        for _, o in ipairs(scene.world.objects) do
            if o.skin then
                local sa = o._surfaceAppearance
                local parts = {}
                if sa then
                    for k, v in pairs(sa) do
                        parts[#parts + 1] = k .. '=' .. tostring(type(v) == 'table' and ('{' .. tostring(v[1]) .. ',' .. tostring(v[2]) .. '}') or v)
                    end
                    table.sort(parts)
                end
                print(('SURF f%d %s shadows=%s pending=%s color=%s | %s'):format(self.frame, tostring(o.name), tostring(scene.world.environment.shadows.enabled), tostring(o._appearancePending), tostring(o.color and (o.color[1] .. ',' .. o.color[2] .. ',' .. o.color[3])), table.concat(parts, ' ')))
            end
        end
    end
    if self.frame == 62 and os.getenv('KATSA_THEME') and scene then
        local function find(node)
            if node.text == 'Theme: dark' then
                return node
            end
            for _, child in ipairs(node.children) do
                local found = find(child)
                if found then
                    return found
                end
            end
        end
        local button = find(scene.ui.content)
        if button then
            button.onPress(button)
        end
    end
    if self.frame == 70 and os.getenv('KATSA_EXPORT') and scene then
        scene:keypressed('f6')
        local files = katsa.filesystem.getDirectoryItems('stats-logs')
        print('EXPORT files', #files, files[#files], 'showStats', tostring(scene.showStats))
    end
    if os.getenv('KATSA_DATA') and self.frame >= 60 and self.frame < 76 and scene and scene.world then
        local r = scene.world._activeRenderer
        local sh = r and r.shadows
        if sh then
            local out = {}
            for i = 1, 4 do
                local d = sh.lightData[i]
                out[#out + 1] = ('%s/%s'):format(tostring(d[1]), tostring(d[3]))
            end
            print(('DATA f%d gen=%s upd=%s pend=%s %s'):format(self.frame, tostring(sh.generation), tostring(sh.updatedFaces), tostring(sh.pendingFaces), table.concat(out, ' ')))
        end
    end
    if self.frame >= 60 and self.frame < 76 + (tonumber(os.getenv('KATSA_FRAMES')) or 0) and dir then
        katsa.graphics.captureScreenshot(('%s/f%02d.png'):format(dir, self.frame - 60))
    elseif self.frame == 70 and os.getenv('KATSA_LOADS') then
        local l = self.manager.profiler.loading
        for _, ph in ipairs(l.phases) do print(('LOAD %-40s %7.1f ms'):format(ph.name, ph.ms)) end
        print(('LOAD total %.1f ms'):format(l.total or 0))
    elseif self.frame == 75 and os.getenv('KATSA_PROF') then
        require('jit.p').stop()
    elseif self.frame >= 60 and self.frame < 70 and os.getenv('KATSA_UIMS') then
        local sc = self.scene
        print(('UIMS stats=%s ui=%.2f'):format(tostring(sc.showStats), sc.uiMilliseconds or -1))
    elseif self.frame == 76 and COUNTS then
        local list = {}
        for k, v in pairs(COUNTS) do list[#list + 1] = { k, v } end
        table.sort(list, function(a, b) return a[2] > b[2] end)
        for i = 1, 12 do if list[i] then print('COUNT', list[i][2], list[i][1]) end end
    elseif self.frame >= 80 + (tonumber(os.getenv('KATSA_FRAMES')) or 0) then
        print('PASSED probe')
        katsa.event.quit()
    end
end

return Tests
