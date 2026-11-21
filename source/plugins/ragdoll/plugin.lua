return {
    name = 'ragdoll',
    title = 'Ragdoll',
    version = '1.0.0',
    description = 'Turns a skinned humanoid model into a physical ragdoll and back: capsule bodies '
        .. 'per limb joined by RagdollConstraint3D, driven into the skeleton after animation '
        .. 'sampling. Adds the Ragdoll3D node.',
    requires = { 'ik' },
    demoScene = 'stareShooter',
    -- Enabled per scene with `plugins = { ragdoll = true }`: adds the Ragdoll3D node.
    nodes = { Ragdoll3D = './nodes.ragdoll3D' },
}
