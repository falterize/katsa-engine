[Hierarchical models and animation](models.md) describes the current import API.

# Model import

Current API and limitations: Hierarchical models and skeleton animation (external release history).
OBJ, GLB and one-buffer glTF are runtime formats. FBX is converted offline; it is
not passed directly to Models.load. Skeletons, skinning and clips are now supported.


## Per-mesh skin limits

See [skin limits](../rendering/skinLimits.md) for runtime `MaxBoneInfluences`
and `BonePaletteLimit`, Workspace editing and palette batching. Models retain
all imported weights; lowering instance limits does not modify source assets.
