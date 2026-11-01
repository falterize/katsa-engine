# Code conventions

All project content is English. Use the v101 `stylua.toml`: four spaces, a 100-column target and preferred single quotes. Separate functions and logical phases with blank lines. Keep imports together, followed by local bindings and the named module table.

## Module shape

```lua
local Dependency = require('source.engine.example.dependency')

local Example = {}

local function helper(value)
    return value
end

function Example.create(settings)
    return Dependency.create(helper(settings))
end

return Example
```

The import above illustrates the convention, not an existing API. All runtime code modules export named tables or deliberate table aliases. Data catalogs may return table literals. Factories use `create`/`new`, builders use `build`, node registration uses `register`, and class wiring uses `install`. Instance methods use `:`; stateless functions use `.`. Closures remain appropriate for callbacks and per-document readers.

Comparable backend modules follow this same layout. Drivers assemble exported method tables once with `core.extensions.apply`. Each module owns its imports; avoid long positional injection signatures such as `(World, C, ffi, O, vector, cast)`.

Use descriptive state/domain names. Conventional loop indices and vector components are useful in math code. Keep related assignments together and expand semicolon-packed control flow. Comments explain units, ownership, callback boundaries, cache invalidation or another non-obvious reason. Straightforward getters and assignments need no narration.

Game code belongs in `source/game`, reusable services in `source/engine`, dependencies in `vendor`, and build/import helpers in `tools`. Vendor code and historical comparison fixtures retain their reference formatting and licenses. Installation and class composition happen at load time, not in hot loops.

Run StyLua 2.6.0 with `--syntax LuaJIT --verify`, then `--check`, over `source/engine source/game source/tests main.lua conf.lua`. `.styluaignore` excludes vendor/reference files. Python tools use Black 24.10.0 and `pyproject.toml`. Follow formatting with relevant runtime tests; formatting alone does not verify behavior.

Project-owned C uses the checked-in `.clang-format` (four spaces, 100 columns); format only the bridge, not upstream vendor headers. Python build tools use the checked-in Black configuration.
