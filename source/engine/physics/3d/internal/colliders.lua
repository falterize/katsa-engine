local Colliders = {}

function Colliders.install(Physics, Body3D)
    function Body3D:addCollider(collider)
        return self.physics.adapter:addCollider(self, collider)
    end

    function Body3D:refreshFilters()
        self.physics:addGroup(self.group)
        self.physics.adapter:refreshFilters(self)
    end
end

return Colliders
