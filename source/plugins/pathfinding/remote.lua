-- RemotePlanner: route searches for a Layered map on worker threads (ActorPool), so a crowd of
-- agents does not spend the frame in A*. The workers hold their own copy of the map; the planner
-- sends a fresh snapshot whenever the map's version changes.
--
--   local planner = RemotePlanner.new(nav, { size = 1 })
--   planner:findPath(x0, y0, z0, x1, y1, z1, function(path) ... end)   -- path is nil when none
--   planner:update()                                                    -- every frame
--
-- Without threads (or after a worker failure) the same call searches on the calling thread and
-- answers at once, so callers need no second code path.
local Path = require('./path')

local RemotePlanner = {}
RemotePlanner.__index = RemotePlanner

local SCRIPT = [[
local Layered = require('source.plugins.pathfinding.layered')
local nav
Actor.on('map', function(snapshot)
    nav = Layered.fromSnapshot(snapshot)
end)
Actor.on('route', function(job)
    if not nav then
        return { error = 'no map' }
    end
    local path, reason = nav:findPath(job[1], job[2], job[3], job[4], job[5], job[6], job.options)
    if not path then
        return { reason = reason }
    end
    return { points = path.points, levels = path.levels, cost = path.cost }
end)
]]

-- options: size (workers, default 1), name.
function RemotePlanner.new(nav, options)
    options = options or {}
    local self = setmetatable({ nav = nav, version = nil, pending = 0, searches = 0 }, RemotePlanner)
    if not nav.snapshot then
        return self
    end
    local ok, pool = pcall(function()
        local Pool = require('source.engine.actors.pool')
        local created =
            Pool.new({ script = SCRIPT, size = options.size or 1, name = options.name or 'route' })
        if not created.threaded then
            -- Searching in a pool that runs on this thread would only add copies: search inline.
            local reason = created.fallbackReason
            created:destroy()
            error(reason, 0)
        end
        return created
    end)
    if ok then
        self.pool = pool
        pool.onError = function(message)
            self.failure = message
        end
    else
        self.failure = pool
    end
    return self
end

function RemotePlanner:isThreaded()
    return self.pool ~= nil and self.failure == nil
end

local function ensureMap(self)
    local version = self.nav:version()
    if version ~= self.version then
        self.version = version
        self.pool:broadcast('map', self.nav:snapshot())
    end
end

-- callback(path | nil, reason) runs from update() when a worker answered, immediately otherwise.
function RemotePlanner:findPath(x0, y0, z0, x1, y1, z1, callback, options)
    self.searches = self.searches + 1
    if not self:isThreaded() then
        callback(self.nav:findPath(x0, y0, z0, x1, y1, z1, options))
        return
    end
    ensureMap(self)
    self.pending = self.pending + 1
    self.pool:request('route', { x0, y0, z0, x1, y1, z1, options = options }, function(ok, result)
        self.pending = self.pending - 1
        if not ok or not result or result.error then
            -- A worker that cannot answer is dropped: from now on searches run here.
            self.failure = (ok and type(result) == 'table' and result.error) or tostring(result)
            callback(self.nav:findPath(x0, y0, z0, x1, y1, z1, options))
        elseif not result.points then
            callback(nil, result.reason)
        else
            local path = Path.new(result.points, result.cost)
            path.levels = result.levels
            callback(path)
        end
    end)
end

function RemotePlanner:update()
    if self.pool then
        self.pool:update()
    end
end

function RemotePlanner:destroy()
    if self.pool then
        self.pool:destroy(100)
        self.pool = nil
    end
end

return RemotePlanner
