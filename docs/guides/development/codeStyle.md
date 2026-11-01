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

Run StyLua 2.6.0 with `--syntax LuaJIT --verify`, then `--check`, over `source/engine source/game source/katsa source/tests main.lua conf.lua`. `.styluaignore` excludes vendor/reference files. Python tools use Black 24.10.0 and `pyproject.toml`. Follow formatting with relevant runtime tests; formatting alone does not verify behavior.

Project-owned C uses the checked-in `.clang-format` (four spaces, 100 columns); format only the bridge, not upstream vendor headers. Python build tools use the checked-in Black configuration.

## Module size and categories

Split a module by responsibility before it passes about 400 lines; `tools/testing/checkStyle.py` fails any module above 700. A package keeps an `init.lua` that only assembles its parts, and each part owns one category (for example `source/katsa/graphics/{state,transform,color,renderState,canvas,batch,draw,primitives,text,frame}.lua` and `source/katsa/physics/{binding,scale,registry,errors,object,shape,fixture,body,contact,world,joint,jointProperties}.lua`).

* Shared mutable state lives in one module (`graphics/state.lua`); category modules read it from there instead of passing upvalues around. GL bindings that exist only after context creation arrive through `State.onSetup`.
* Helpers needed by several parts are exported from their owner (`Batch.addQuad`, `Canvas.markTargetsDirty`) rather than duplicated. Repeated class boilerplate (`type`, `typeOf`, `release`) comes from a shared helper (`physics/object.lua`).
* Public constructors are named `new*`; the package `init.lua` copies them into the public table.

## Style tooling

`python3 tools/testing/checkStyle.py` checks the katsa runtime and its tests for over-long lines, double-quoted strings, one-line function bodies, missing blank lines between functions and oversized modules. `python3 tools/testing/fixStyle.py <paths>` applies the mechanical fixes (expands one-line functions and inline `if` bodies, separates functions, wraps calls, packed tables, long strings and comments); review its output and run the tests afterwards. Lines it cannot split safely are fixed by hand.
