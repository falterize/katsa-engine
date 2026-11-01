local Joints = {}

function Joints.install(Physics, Body3D)
    function Physics:_createJoint(kind, a, b, settings)
        return self.adapter:createJoint(kind, a, b, settings or {})
    end

    function Physics:createJoint(kind, a, b, settings)
        local classes = {
            Spherical = 'BallSocketConstraint3D',
            Revolute = 'HingeConstraint3D',
            Prismatic = 'PrismaticConstraint3D',
            Cylindrical = 'CylindricalConstraint3D',
            Universal = 'UniversalConstraint3D',
            Ragdoll = 'RagdollConstraint3D',
            Generic = 'GenericConstraint3D',
        }
        settings = settings or {}
        local world = a.object._world
        local attachment0 = world:create(
            'Attachment3D',
            { name = 'JointAttachment0', position = settings.anchor1 or { 0, 0, 0 } },
            a.object
        )
        local attachment1 = world:create(
            'Attachment3D',
            { name = 'JointAttachment1', position = settings.anchor2 or { 0, 0, 0 } },
            b.object
        )
        return world:create(
            assert(classes[kind], 'Unknown joint kind'),
            { attachment0 = attachment0, attachment1 = attachment1 }
        )
    end
end

return Joints
