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
