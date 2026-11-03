return {
    name = 'ik',
    title = 'Inverse Kinematics',
    version = '1.0.0',
    description = 'Skeleton modifiers for 3D rigs: bone pose access plus TwoBone, LookAt, FABRIK, '
        .. 'CCD, Jacobian, Spline and FK solvers that run after animation sampling, with influence '
        .. 'blending, debug drawing and the InverseKinematics3D node.',
    requires = {},
    -- Enabled per scene with `plugins = { 'ik' }`: adds the InverseKinematics3D node.
    nodes = { InverseKinematics3D = './nodes.inverseKinematics3D' },
}
