-- The scrolling viewport of the curve editor: a CurveEditor2D inside a ScrollFrame that scrolls on
-- both axes. Wide value ranges (-50..140) make the graph taller, a long animation in seconds makes
-- it wider; the axes labels stay at the visible edges (see curveEditor).
local Timeline = require('../../animation.rampTimeline')

local CurveView = {}

local BACKGROUND = { 0.025, 0.045, 0.07 }
local BAR = 6

-- Builds the view inside `parent`. `ramp` owns the time axis (nil for a plain sequence);
-- `property` is the goal being edited (nil for the Ramp's progress curve, always 0..1).
function CurveView.create(ui, parent, ramp, property, points, interpolation, view)
    local scroller = ui:create('ScrollFrame', {
        position = { 0, 8, 0, 84 },
        size = { 1, -16, 0, view.height },
        scrollingDirection = 'XY',
        canvasSize = { 0, 0, 0, view.height },
        scrollBarThickness = BAR,
        horizontalScrollBarInset = 'ScrollBar',
        verticalScrollBarInset = 'ScrollBar',
        backgroundColor = BACKGROUND,
        clip = true,
    }, parent)
    local graph = ui:create('CurveEditor2D', {
        position = { 0, 0, 0, 0 },
        size = { 1, 0, 0, view.height },
        points = points,
        interpolation = interpolation,
        backgroundColor = BACKGROUND,
        clip = true,
    }, scroller)
    local seconds = property and ramp and Timeline.usesSeconds(ramp)
    if seconds then
        -- The last point may be dragged past the end: that lengthens the animation.
        graph.onExtend = function(time)
            Timeline.setDuration(
                ramp,
                math.min(Timeline.MAX_DURATION, ramp.playbackTime * time)
            )
        end
        -- When the last point settles earlier, the animation ends there.
        graph.onSettle = function()
            Timeline.fit(ramp)
        end
    end
    local function width()
        return seconds and ramp.playbackTime or nil
    end
    -- Re-measures the graph. Skipped while a point is dragged: the axes are frozen then, and a
    -- graph that changed size under the pointer would move the point away from it.
    local function fit()
        if graph.drag then
            return
        end
        graph.timeScale = width()
        local viewWidth = scroller._width or view.width
        local w, h = graph:fitWidth(viewWidth), graph:fitHeight(view.height)
        if w <= viewWidth + 0.5 then
            graph.size = { 1, 0, 0, h }
            scroller.canvasSize = { 0, 0, 0, h }
        else
            graph.size = { 0, w, 0, h }
            scroller.canvasSize = { 0, w, 0, h }
        end
    end
    return { graph = graph, scroller = scroller, fit = fit, seconds = seconds }
end

return CurveView
