local Casters = require('./shadowCasters')
local Types = require('./sourceTypes')
local kind, faces, pointDirections = Types.kind, Types.faces, Types.pointDirections
local viewProjection = require('./shadowProjection')
local Directional = require('./directionalShadows')

local Task = {}

function Task.draw(self, task, world, settings, time, clock)
    self.currentLight = task.light
    -- One conservative source-range pass replaces repeated full
    -- scene scans on the six cubemap faces. Unknown deformation is
    -- retained; offscreen blockers are never excluded by main culling.
    task.candidates, self.sourceTests =
        Casters.collect(world, task.light, settings.layers, task.kind ~= 2, task.candidates)
    self.sourceCasters = task.candidates
    self.casterTests = self.casterTests + self.sourceTests
    local far = task.light.range
    -- Publish a coherent projection generation: obsolete hidden
    -- faces cannot remain addressable after a moving-source refresh.
    if task.republish then
        for face = 1, faces(task) do
            task.facesValid[face] = false
        end
        task.republish = false
    end
    self.updatedLights = self.updatedLights + 1
    if task.kind == 2 then
        Directional.draw(self, task, world, time)
    elseif task.kind == 1 then
        for face = 1, 6 do
            if task.faceVisible[face] and task.facesDirty[face] then
                viewProjection.install(
                    task.light.worldPosition,
                    pointDirections[face],
                    1,
                    settings.near,
                    far,
                    false,
                    self.matrices[task.base + face],
                    self.view,
                    self.projection
                )
                self:drawFace(world, self.matrices[task.base + face], task.base + face - 1, time)
                task.facesDirty[face], task.facesValid[face] = false, true
            end
        end
    else
        viewProjection.install(
            task.light.worldPosition,
            task.light.worldDirection,
            math.max(0.001, task.light.radius / far),
            settings.near,
            far,
            false,
            self.matrices[task.base + 1],
            self.view,
            self.projection
        )
        self:drawFace(world, self.matrices[task.base + 1], task.base, time)
        task.facesDirty[1], task.facesValid[1] = false, true
    end
    if task.fadeIn and not task.publishedAt then
        task.publishedAt = clock
    end
    task.projectionPosition = {
        task.light.worldPosition[1],
        task.light.worldPosition[2],
        task.light.worldPosition[3],
        far,
    }
    task.projectionDirection = {
        task.light.worldDirection[1],
        task.light.worldDirection[2],
        task.light.worldDirection[3],
        settings.near,
    }
    task.projectionExtent = task.kind == 2 and 0
        or task.kind == 1 and 1
        or math.max(0.001, task.light.radius / far)
    task.valid, task.since = true, nil
    for i = #task.candidates, 1, -1 do
        task.candidates[i] = nil
    end
end

return Task
