return {
    name = 'lod',
    title = 'Level of detail',
    version = '1.0.0',
    description = 'The LODGroup node: shows one of its children by camera distance or size on screen, '
        .. 'with cross-fade, shadow and animation-rate control per level and a billboard level. '
        .. 'Model files with nodes named <name>-lod0, <name>-lod1 ... are grouped on import, and '
        .. 'the Low / Medium / High quality profiles lower the detail sooner.',
    requires = {},
    -- Enabled per scene with `plugins = { lod = true }`: adds the LODGroup node and the import grouping.
    nodes = { LODGroup = './nodes.lodGroup' },
    -- Runs after a model is instantiated; the result is stored as `model.lodGroups`.
    importers = { lodGroups = './autoLod' },
    -- Extra Environment.render values for the quality profiles; LODGroup multiplies its bias by it.
    quality = {
        Low = { lodBias = 1.5 },
        Medium = { lodBias = 1.2 },
        High = { lodBias = 1 },
    },
}
