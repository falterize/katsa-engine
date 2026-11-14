local Colliders = {}

function Colliders.install(Physics, Body3D)
    function Body3D:addCollider(collider)
        return self.space.adapter:addCollider(self, collider)
    end

    function Body3D:refreshFilters()
        self.space:addGroup(self.group)
        self.space.adapter:refreshFilters(self)
    end
end

return Colliders
