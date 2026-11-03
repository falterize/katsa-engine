local Array = require('../math.array')
local ipairs = require('../math.array').ipairs
local pairs = require('../math.array').pairs
local Sequence = require('./sequence')
local RampLayout = {}

function RampLayout.install(Ramp)
    local colorKeys = {
        Background = 'backgroundColor',
        Text = 'textColor',
        Image = 'imageColor',
        Stroke = 'color',
    }

    function Ramp:getTarget()
        return self.adornee or self.parent
    end

    function Ramp:isLifetime()
        local target = self:getTarget()
        return target
            and (target:isA('ParticleEmitter3D') or target:isA('Beam3D') or target:isA('Trail3D'))
            and self == target.lifetimeRamp
    end

    function Ramp:isSpatialGradient()
        local target = self:getTarget()
        if self.mode ~= 'Static' or not target or not target:isA('UINode') then
            return false
        end
        for channel, key in pairs(colorKeys) do
            local alpha = key == 'color' and 'transparency' or key:gsub('Color$', 'Transparency')
            if
                (channel ~= 'Stroke' or target:isA('UIStroke'))
                and (
                    self.bindings[key]
                    or self.goals[key]
                    or self.bindings[alpha]
                    or self.goals[alpha]
                )
            then
                return true
            end
        end
        return Array.is(self.points[1].value) and #self.points[1].value >= 3
    end

    function Ramp:addGoal(key, value)
        return require('source.engine.animation.rampGoals').add(self, key, value)
    end

    function Ramp:removeGoal(key)
        self.goals[key] = nil
        self.bindings[key] = nil
        if self.ui then
            self.ui:invalidate()
        end
    end

    function Ramp:applyLayout(parent)
        if not self:isSpatialGradient() then
            return
        end
        for channel, key in pairs(colorKeys) do
            local alpha = key == 'color' and 'transparency' or key:gsub('Color$', 'Transparency')
            if
                (channel ~= 'Stroke' or parent:isA('UIStroke'))
                and (
                    self.bindings[key]
                    or self.goals[key]
                    or self.bindings[alpha]
                    or self.goals[alpha]
                )
            then
                self._gradientViews = self._gradientViews or {}
                local view = self._gradientViews[key]
                if not view then
                    view = {
                        offset = self.offset,
                        rotation = self.rotation,
                        transparency = self.transparency,
                    }

                    function view:gradientStops()
                        return self.ramp:gradientStops(self.key)
                    end
                    view.ramp, view.key = self, key
                    self._gradientViews[key] = view
                end
                view.offset, view.rotation, view.transparency =
                    self.offset, self.rotation, self.transparency
                parent[channel == 'Text' and '_textGradient' or channel == 'Image' and '_imageGradient' or '_backgroundGradient'] =
                    view
            end
        end
        if Array.is(self.points[1].value) then
            parent[self.target == 'Text' and '_textGradient' or '_backgroundGradient'] = self
        end
    end

    function Ramp:gradientStops(key)
        self._stopSets = self._stopSets or {}
        local stops = self._stopSets[key or 'legacy'] or {}
        self._stopSets[key or 'legacy'] = stops
        local points
        if key then
            points = self.bindings[key]
        else
            points = self.points
        end
        if not points then
            local current = require('source.engine.animation.rampGoals').value(self, key)
            points = Sequence.linear(current, self.goals[key] or current)
        end
        local alphaKey = key == 'color' and 'transparency'
            or key and key:gsub('Color$', 'Transparency')
        self._timelineCaches = self._timelineCaches or {}
        local cache = self._timelineCaches[key or 'legacy'] or { times = {}, seen = {} }
        self._timelineCaches[key or 'legacy'] = cache
        local times, seen = cache.times, cache.seen
        for i = #times, 1, -1 do
            times[i] = nil
        end
        for time in pairs(seen) do
            seen[time] = nil
        end
        for _, sequence in ipairs({ points, alphaKey and self.bindings[alphaKey] or {} }) do
            for _, point in ipairs(sequence) do
                if not seen[point.time] then
                    seen[point.time] = true
                    times[#times + 1] = point.time
                end
            end
        end
        table.sort(times)
        local colorMode = points.interpolation or self.interpolation
        local alphaPoints = alphaKey and self.bindings[alphaKey]
        local alphaMode = alphaPoints and (alphaPoints.interpolation or self.interpolation)
        local curved = colorMode == 'Curve' or alphaMode == 'Curve'
        local count = curved and 16 or #times
        assert(count <= 16, 'GPU gradient supports at most 16 linear points')
        for i = 1, count do
            local time = curved and (i - 1) / (count - 1) or times[i]
            local value =
                Sequence.evaluate(points, time, self.interpolation, stops[i] and stops[i].color)
            assert(Array.is(value) and #value >= 3, 'Gradient Ramp requires RGB/RGBA values')
            local stop = stops[i] or {}
            stops[i] = stop
            stop.time, stop.color = time, value
            local alphaKey = key == 'color' and 'transparency'
                or key and key:gsub('Color$', 'Transparency')
            if alphaKey and self.bindings[alphaKey] then
                stop.transparency =
                    Sequence.evaluate(self.bindings[alphaKey], time, self.interpolation)
            elseif alphaKey and self.goals[alphaKey] then
                stop.transparency = self.goals[alphaKey] * time
            else
                stop.transparency = nil
            end
        end
        for i = #stops, count + 1, -1 do
            stops[i] = nil
        end
        return stops
    end
end

return RampLayout
