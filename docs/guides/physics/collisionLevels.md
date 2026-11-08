# Collision levels

A `Collider3D` with `shape = 'Geometry'` (a model file or a part of a model) or a Mesh source builds its physics shape at one of five levels, the same choices as in other editors:

| Level | What it builds | Use for |
| --- | --- | --- |
| `Trimesh` | One thin prism per triangle (Static bodies only). Exact, expensive. | Level geometry |
| `Single Convex` | One convex hull per mesh part. | Rocks, props that are already convex |
| `Simplified Convex` | One hull per part, reduced to `hullPoints` vertices. | Cheap dynamic bodies |
| `Multiple Convex` | The whole model cut into up to `maxHulls` nearly convex hulls. Concave shapes (an L, a car body, a chair) keep their hollows. | Dynamic bodies that must be accurate |
| `Bounding Box` | One box. Default. | Anything that only needs a volume |

The 3D levels replace the old `Simple`, `Convex` and `Detailed` names (`Bounding Box`, `Single Convex`, `Trimesh`); the old names are rejected with an error that lists the valid ones. `Collider2D` keeps its own `Simple` / `Convex` / `Detailed` image levels.

## Multiple Convex

`Multiple Convex` is a small V-HACD: the model is voxelised (`resolution` cells along the longest side), the cells are cut by axis-aligned planes where that removes the most empty volume, and every piece keeps the real triangles inside its box, so each hull follows the surface and neighbouring hulls meet exactly at their cut.

| Property | Default | Meaning |
| --- | --- | --- |
| `maxHulls` | 8 | Most pieces (1 to 64). |
| `hullPoints` | 32 | Most vertices per piece (4 to 128). |
| `concavity` | 0.02 | A piece that leaves less than this share of the model's volume empty is not cut further. |
| `resolution` | 32 | Voxels along the longest side (8 to 96). Higher is finer and slower. |

The four properties are visible in the inspector only for the levels that use them. Results are cached per mesh and settings, so identical colliders cost nothing after the first. A typical car body takes under 0.1 s.

## Part of a model

`geometrySource` accepts a model path, or a live `Node3D`/`Mesh3D` of the same world: a subtree selects just that part (for example the `Body` mesh of a car and not its wheels).

## Code

```lua
local Decomposition = require('source.engine.physics.3d.decomposition')
local hulls = Decomposition.decompose(triangleSoup, { maxHulls = 6, hullPoints = 24 })
-- hulls: list of vertex lists, one convex hull each
```

Files: `source/engine/physics/3d/decomposition/` (`hull`, `voxelGrid`, `planner`, `clip`, `decompose`, `cache`), `collisionLevel.lua`.

## Cars

multiplayerCars builds its hull with `Multiple Convex` from the Duke 69 body panels (`scripts/game/carHull.lua`). A dent only displaces the hull vertices; the decomposition itself runs once.
