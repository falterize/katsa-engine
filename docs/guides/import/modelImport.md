[Hierarchical models and animation](models.md) describes the current import API.

# Model import

Current API and limitations: Hierarchical models and skeleton animation (external release history).
OBJ, GLB and one-buffer glTF are runtime formats. FBX is converted offline; it is
not passed directly to Models.load. Skeletons, skinning and clips are now supported.


## Per-mesh skin limits

See [skin limits](../rendering/skinLimits.md) for runtime `MaxBoneInfluences`
and `BonePaletteLimit`, Workspace editing and palette batching. Models retain
all imported weights; lowering instance limits does not modify source assets.

<!-- book:nav -->
---
**Katsa book** · chapter 5, Models and animation · page 1 of 11

[← Android shader link fix — v35 (retained in v36)](../rendering/androidShaderFix.md) · [Contents](../../book/README.md) · [Models, opacity and surface materials — v64 →](models.md)
<!-- /book:nav -->
