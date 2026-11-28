-- The pointer verbs shared by Button2D and Button3D. A pointer `id` ('mouse', a touch id, or
-- 'code') presses, then either releases (a `click` follows) or is cancelled (it left the object or
-- turned into a camera drag). Signals: press, release, click, cancel; each gets (pointerId, target).
-- `checked` = true also requires the class's `canActivate()` (radius, visibility, ...), like a
-- player's click; calls from code skip it by default. The class provides `getTarget()`.
local PointerVerbs = {}

local function alive(self)
    return self.enabled and not self.destroyed and not self._destroying
end

function PointerVerbs.install(Class)
    function Class:press(id, checked)
        id = id or 'code'
        if not alive(self) or checked and not self:canActivate() then
            return false
        end
        self._held = self._held or {}
        self._held[id] = true
        self:emit('press', id, self:getTarget())
        return true
    end

    function Class:release(id)
        id = id or 'code'
        if not (self._held and self._held[id]) then
            return false
        end
        self._held[id] = nil
        self:emit('release', id, self:getTarget())
        self:emit('click', id, self:getTarget())
        return true
    end

    function Class:cancel(id)
        id = id or 'code'
        if not (self._held and self._held[id]) then
            return false
        end
        self._held[id] = nil
        self:emit('cancel', id, self:getTarget())
        return true
    end

    -- Press and release in one go: emits press, release and click.
    function Class:click(id, checked)
        return self:press(id, checked) and self:release(id)
    end
end

return PointerVerbs
