OimoPhysics 1.2.5

Repository: https://github.com/saharan/OimoPhysics
Commit: 5c4681f32e8eaa3916beffef9645e659eae613a9
License: MIT

Generated Lua: Haxe 4.3.7, LuaJIT target, analyzer optimization, standard-library DCE.
No native physics library, luv, UTF-8 or regex module is required at runtime.
The module isolates generated symbols in a private Lua environment and adapts the profiling clock to love.timer.getTime.
Rebuild: python3 tools/build/buildPhysics.py --haxe /path/to/haxe
The Haxe compiler is an external build tool and is not bundled. Its embedded standard-library helpers are MIT licensed.

Local v45 fix: BVH collectPairs processes a one-proxy world instead of returning
before moved bounds are synchronized. This fixes raycasts after teleporting the
only collider. Both the Haxe source and bundled generated Lua are patched; the
original MIT license is retained.

## Local correction in Katsa v97

`RigidBody.getAngularVelocityTo` now copies `_angVel` rather than `_vel`,
matching `getAngularVelocity`. Both the bundled Lua runtime and Haxe source
contain this correction. The point-response buffer optimization depends on
this getter; regression checks use distinct linear and angular velocities.
