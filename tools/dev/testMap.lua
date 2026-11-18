-- Which test flags cover which part of the repository (used by tools/dev/testChanged.lua).
-- A file is matched by every `prefix` it starts with; the flags of all matches are collected.
-- `validation/tests/versions/vNNN_N/...` always maps to its own `--test-vNNN.N` flag.
return {
    -- Changes under these prefixes need no test run.
    ignore = { 'docs/', 'README', '.github/', 'tools/build/', 'tools/project/' },

    -- Anything else under these prefixes runs `fallback`.
    code = { 'source/', 'assets/shaders/', 'main.lua', 'conf.lua', 'native/' },
    fallback = { '--test-v108.9', '--test' },

    rules = {
        { prefix = 'game/scenes/levelEditor/', flags = { '--test-v108.9' } },
        { prefix = 'validation/tests/versions/v108_9/', flags = { '--test-v108.9' } },
        { prefix = 'source/engine/scenes/packed/', flags = { '--test-v108.8' } },
        { prefix = 'source/engine/core/prefabs.lua', flags = { '--test-v108.8' } },
        { prefix = 'source/engine/scenes/paths.lua', flags = { '--test-v108.8', '--test' } },
        { prefix = 'source/engine/scenes/', flags = { '--test-v108.8', '--test' } },
        { prefix = 'source/engine/ui/', flags = { '--test-v108.8', '--test-v106.8' } },
        { prefix = 'source/engine/nodes/ui/', flags = { '--test-v108.8', '--test-v106.8' } },
        { prefix = 'source/engine/nodes/core/', flags = { '--test-v108.8', '--test-v106.8', '--test' } },
        { prefix = 'source/engine/nodes/', flags = { '--test-v108.8', '--test' } },
        { prefix = 'source/engine/physics/', flags = { '--test' } },
        { prefix = 'source/engine/graphics/', flags = { '--test-v108.8', '--test-v106.8', '--test-shadows' } },
        { prefix = 'assets/shaders/', flags = { '--test-v108.8', '--test-shadows' } },
        { prefix = 'source/engine/world/', flags = { '--test-v108.8', '--test' } },
        { prefix = 'source/engine/animation/', flags = { '--test-v108.8' } },
        { prefix = 'source/engine/net/', flags = { '--test-v108.8', '--test-v108.7.net' } },
        { prefix = 'source/plugins/ik/', flags = { '--test-v108.5' } },
        { prefix = 'source/plugins/ragdoll/', flags = { '--test-v108.8' } },
        { prefix = 'source/plugins/uiStyler/', flags = { '--test-v108.5', '--test-v108.7.styler' } },
        { prefix = 'source/game/scenes/replicationLab/', flags = { '--test-v108.8' } },
        { prefix = 'source/game/scenes/multiplayerCars/', flags = { '--test-v108.4' } },
    },
}
