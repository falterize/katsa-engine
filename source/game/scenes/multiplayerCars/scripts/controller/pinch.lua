-- Two-finger pinch zoom for touch screens. It follows the mouse-wheel rules (controller/input.lua):
-- no zoom while a finger is over an interactable UI element, and only while playing. The finger that
-- holds the virtual joystick never takes part, so steering with one thumb while turning the camera
-- with the other does not zoom. The joystick id is read lazily because the input router may claim a
-- finger after the scene saw it.
-- State on the session: touches[id] = { x, y }, pinchLast (distance of the previous pair).
local SCALE = 0.02

local Pinch = {}

local function pair(session, touches)
    local joystickId = session.scene.input and session.scene.input.joystickId
    local a, b
    for id, touch in pairs(touches) do
        if id ~= joystickId then
            if not a then
                a = touch
            elseif not b then
                b = touch
            end
        end
    end
    return a, b
end

local function distance(session, touches)
    local a, b = pair(session, touches)
    if a and b then
        return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2), a, b
    end
end

local function allowed(session, a, b)
    local input, ui = session.scene.input, session.scene.ui
    return session.client ~= nil
        and input
        and input:playing()
        and not ui:blocksWorldClick(a[1], a[2], true)
        and not ui:blocksWorldClick(b[1], b[2], true)
end

function Pinch.pressed(session, id, x, y)
    if id ~= 'mouse' and not session.scene.ui:blocksWorldClick(x, y, true) then
        session.touches = session.touches or {}
        session.touches[id] = { x, y }
        session.pinchLast = distance(session, session.touches)
    end
end

function Pinch.moved(session, id, x, y)
    local touches = session.touches
    if id == 'mouse' or not touches or not touches[id] then
        return
    end
    touches[id][1], touches[id][2] = x, y
    local current, a, b = distance(session, touches)
    if current and session.pinchLast and allowed(session, a, b) then
        session.orbit:zoom((current - session.pinchLast) * SCALE)
    end
    session.pinchLast = current
end

function Pinch.released(session, id)
    if session.touches then
        session.touches[id] = nil
        session.pinchLast = distance(session, session.touches)
    end
end

return Pinch
