# Dependencies and licenses

| Component | License/status |
| --- | --- |
| Project source, tools and shaders | MIT; see LICENSE |
| rxi/json.lua | MIT; vendor/json/LICENSE, copyright rxi 2020 |
| OimoPhysics 1.2.5, compiled Lua and Haxe source | MIT; vendor/oimoPhysics/LICENSE; pinned commit in UPSTREAM.md |
| Haxe standard-library helpers in generated Lua | MIT; vendor/oimoPhysics/Haxe-Standard-Library-LICENSE |
| LÖVE 11.5, external runtime | zlib/libpng; not bundled, dependencies have their own licenses |
| Box2D 2.3.1, vendored in native/third_party/box2d and built into katsa_box2d | zlib license in native/third_party/box2d/LICENSE.txt; one local patch: polygon welding compares squared distances (as Box2D 2.4 does) so thin polygons stay valid |
| Generated colliderMask.png examples and test fixture | CC0 1.0; procedurally generated for collider demonstrations |
| Blender, external conversion tool | GPL; executable not bundled |
| Eight supplied v33 images | Original license unspecified; no MIT relicensing of user assets |
| Supplied Stare Shooter model, textures, images and adapted game/shader content | Original license unspecified; imported user content is not relicensed as MIT |
| Godot 4.7.1, external asset export/reference tool | MIT; executable and Godot project not bundled in the engine |
| Generated WAV, OBJ, GLB and test FBX assets | CC0 1.0; embedded supplied textures retain their original status |

The JSON parser is pure Lua. OimoPhysics is compiled from Haxe 4.3.7 with analyzer optimization, adapts its clock to katsa.timer.getTime (local patch in vendor/oimoPhysics/init.lua) and exports 87 backend classes. Oimo itself needs no native library; the optional Jolt backend uses the bundled platform-specific .so/.dll artifacts. Haxe and Blender executables are external tools, not distributed in this archive.

g3d was consulted as a conceptual 3D reference; it is not bundled or required and its source was not copied. Source/image audit hashes from the original migration remain in docs/sourceAudit.json.

Upstream: https://github.com/rxi/json.lua, https://github.com/saharan/OimoPhysics, https://github.com/love2d/love/tree/11.5, https://haxe.org/foundation/open-source.html, https://www.blender.org/about/license/, https://creativecommons.org/publicdomain/zero/1.0/.
