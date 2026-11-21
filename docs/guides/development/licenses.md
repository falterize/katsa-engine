# Dependencies and licenses

| Component | License/status |
| --- | --- |
| Project source, tools and shaders | MIT; see LICENSE |
| rxi/json.lua | MIT; vendor/json/LICENSE, copyright rxi 2020 |
| OimoPhysics 1.2.5, compiled Lua and Haxe source | MIT; vendor/oimoPhysics/LICENSE; pinned commit in UPSTREAM.md |
| Haxe standard-library helpers in generated Lua | MIT; vendor/oimoPhysics/Haxe-Standard-Library-LICENSE |
| Box2D 2.3.1, vendored in vendor/box2d and built into katsa_box2d | zlib license in vendor/box2d/LICENSE.txt; one local patch: polygon welding compares squared distances (as Box2D 2.4 does) so thin polygons stay valid |
| ENet 1.3.18, vendored in vendor/enet and built into katsa_net | MIT; vendor/enet/LICENSE.txt |
| Dear ImGui 1.93.0 and cimgui (docking), vendored in source/plugins/imgui/vendor/cimgui, compiled into native/<os>-<arch>/ | MIT; LICENSE and imgui/LICENSE.txt there; pins in UPSTREAM.md; no local changes |
| Blender, external conversion tool | GPL; executable not bundled |
| Godot 4.7.1, external asset export/reference tool | MIT; executable and Godot project not bundled in the engine |

The JSON parser is pure Lua. OimoPhysics is compiled from Haxe 4.3.7 with analyzer optimization, adapts its clock to katsa.timer.getTime (local patch in vendor/oimoPhysics/init.lua) and exports 87 backend classes. Oimo itself needs no native library; the optional Jolt backend uses the bundled platform-specific .so/.dll artifacts. Haxe and Blender executables are external tools, not distributed in this archive.

g3d was consulted as a conceptual 3D reference; it is not bundled or required and its source was not copied. Source/image audit hashes from the original migration remain in docs/sourceAudit.json.

Assets of the example scenes (supplied images, the Stare Shooter content, generated colliders, WAV, OBJ and GLB files) and their licenses are documented in the README of the [examples repository](https://github.com/falterize/katsa-engine-examples#asset-notices). Only the engine's own fixtures and default fonts/shaders/textures stay here.

Upstream: https://github.com/rxi/json.lua, https://github.com/saharan/OimoPhysics, https://haxe.org/foundation/open-source.html, https://www.blender.org/about/license/, https://creativecommons.org/publicdomain/zero/1.0/.

<!-- book:nav -->
---
**Katsa book** · chapter 11, Reference · page 9 of 10

[← Current limitations](limitations.md) · [Contents](../../book/README.md) · [Stare Shooter scene →](stareShooter.md)
<!-- /book:nav -->
