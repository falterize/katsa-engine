local Contacts = {}

local function queue(physics, phase, a, b, contact, impulse)
    local da, db = a:getUserData(), b:getUserData()
    if not da or not db then
        return
    end
    if phase == 'hit' then
        local x, y = da.body, db.body
        if
            not x.collisionHit
            and not y.collisionHit
            and not (x.object._signals and x.object._signals.collisionHit)
            and not (y.object._signals and y.object._signals.collisionHit)
        then
            return
        end
    end
    local nx, ny = contact:getNormal()
    local x, y = contact:getPositions()
    local f = physics.factor
    physics.events[#physics.events + 1] = {
        phase = phase,
        body0 = da.body,
        body1 = db.body,
        collider0 = da.collider,
        collider1 = db.collider,
        sensor = a:isSensor() or b:isSensor(),
        impulse = impulse and impulse / f or nil,
        position = x and { x / f, y / f } or nil,
        normal = { nx, ny },
    }
end

function Contacts.install(physics)
    physics.world:setContactFilter(function(a, b)
        local x, y = a:getUserData(), b:getUserData()
        if not x or not y then
            return false
        end
        local triggerX = x.descriptor.isTrigger == true or x.body.object.isTrigger == true
        local triggerY = y.descriptor.isTrigger == true or y.body.object.isTrigger == true
        x, y = x.body, y.body
        if
            x.object.canCollide == false and not triggerX
            or y.object.canCollide == false and not triggerY
        then
            return false
        end
        return not x.destroyed
            and not y.destroyed
            and physics:groupsCollide(
                x.object.collisionGroup or 'Default',
                y.object.collisionGroup or 'Default'
            )
    end)
    physics.world:setCallbacks(
        function(a, b, contact)
            queue(physics, 'begin', a, b, contact)
        end,
        function(a, b, contact)
            queue(physics, 'end', a, b, contact)
        end,
        nil,
        function(a, b, contact, n1, _, n2)
            queue(physics, 'hit', a, b, contact, (n1 or 0) + (n2 or 0))
        end
    )
end

local function emit(body, name, other, event)
    if body.destroyed or body._pendingDestroy or body.object.destroyed then
        return
    end
    if body.object.emit then
        body.object:emit(name, other.object, event)
        local alias = ({
            triggerEnter = 'triggerEntered',
            triggerExit = 'triggerExited',
            collisionEnter = 'collisionEntered',
            collisionExit = 'collisionExited',
        })[name]
        if alias then
            body.object:emit(alias, other, event)
        end
    end
    local callback = body[name]
    if callback then
        callback(body, other, event)
    end
end

function Contacts.dispatch(physics)
    if #physics.events == 0 then
        physics:flush()
        return
    end
    local events = physics.events
    physics.events = physics._eventScratch or {}
    physics._eventScratch = events
    physics._dispatching = true
    local ok, message = pcall(function()
        for _, event in ipairs(events) do
            local a, b = event.body0, event.body1
            if event.phase == 'begin' or event.phase == 'end' then
                -- Fixture pairs are counted so compound bodies emit one enter/exit.
                local setA = event.sensor and a.triggerOverlaps or a.collisionOverlaps
                local setB = event.sensor and b.triggerOverlaps or b.collisionOverlaps
                local old = setA[b] or 0
                local count = math.max(0, old + (event.phase == 'begin' and 1 or -1))
                setA[b], setB[a] = count > 0 and count or nil, count > 0 and count or nil
                a.overlaps[b] = a.triggerOverlaps[b] or a.collisionOverlaps[b]
                b.overlaps[a] = b.triggerOverlaps[a] or b.collisionOverlaps[a]
                if old == 0 and count > 0 or old > 0 and count == 0 then
                    local name = (event.sensor and 'trigger' or 'collision')
                        .. (count > 0 and 'Enter' or 'Exit')
                    emit(a, name, b, event)
                    emit(b, name, a, event)
                end
            elseif event.phase == 'hit' then
                emit(a, 'collisionHit', b, event)
                emit(b, 'collisionHit', a, event)
            end
        end
    end)
    for i = #events, 1, -1 do
        events[i] = nil
    end
    physics._dispatching = false
    physics:flush()
    if not ok then
        error(message, 0)
    end
end

return Contacts
