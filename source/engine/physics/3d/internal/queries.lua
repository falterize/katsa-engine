local Queries = {}

function Queries.install(Physics, Body3D)
    function Physics:raycast(a, b, filter, out)
        assert(not self._querying, 'Physics queries are not reentrant')
        assert(not self.released, 'Cannot query a released Physics world')
        self.ray:clear()
        self.rayFilter = filter
        local u = self.units
        self.rayBegin:init(a[1] / u, a[2] / u, a[3] / u)
        self.rayEnd:init(b[1] / u, b[2] / u, b[3] / u)
        self._querying = true
        local ok, err = pcall(self.world.rayCast, self.world, self.rayBegin, self.rayEnd, self.ray)
        self._querying = false
        self.rayFilter = nil
        if not self._stepping and not self._flushing then
            self:flushBodyChanges()
        end
        if not ok then
            error(err, 0)
        end
        if not self.ray.hit then
            return
        end
        out = out or {}
        out.position = out.position or {}
        out.normal = out.normal or {}
        out.body, out.fraction = self.ray.shape.userData, self.ray.fraction
        out.position[1], out.position[2], out.position[3] =
            self.ray.position.x * u, self.ray.position.y * u, self.ray.position.z * u
        out.normal[1], out.normal[2], out.normal[3] =
            self.ray.normal.x, self.ray.normal.y, self.ray.normal.z
        return out
    end
end

return Queries
