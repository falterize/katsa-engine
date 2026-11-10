-- Inspector descriptions of bodies, colliders and constraints.
-- Editor text only: the classes carry no hint of their own.
-- Shape: { ClassName = { property = 'text' } }; a subclass inherits its base class entries.
return {
    Body3D = {
        mass = 'Mass in kg. Shows density-derived mass until an explicit override is authored; '
            .. 'effective only for dynamic bodies.',
    },
    Collider3D = {
        collisionLevel = 'Trimesh: exact triangles (static bodies). Single Convex: one hull for '
            .. 'the whole source. Simplified Convex: one hull with few vertices. Multiple Convex: '
            .. 'several hulls that follow a concave model (cars, rooms, arches). Bounding Box: one '
            .. 'box.',
        concavity = 'How much of the model volume a piece may leave empty inside its hull '
            .. 'before it is cut again (0.02 = 2%). Lower values fit tighter and make more pieces.',
        geometrySource = 'Select a Node3D / Mesh3D or enter an OBJ, GLB or glTF model path. '
            .. 'File sources use Size as local scale.',
        hullPoints = 'Most vertices of each convex hull.',
        maxHulls = 'Most convex pieces the model is cut into.',
        resolution = 'Voxels along the longest side used to find concave regions. Higher is '
            .. 'slower.',
    },
}
