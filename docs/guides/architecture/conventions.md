# Project conventions

- Lua properties, modules and functions: lowerCamelCase; node classes and engine
  enum values: PascalCase. Image and shader file names: lowerCamelCase.
- API constants owned by LÖVE/OpenGL preserve the external API's exact spelling,
  including nearest/linear, static/stream audio types and triangles mesh mode.
- Primitive geometry identifiers (cube, sphere), registered resource names and
  custom group names are identifiers, not enum modes; they are case-sensitive.
- Put texture sampling and map settings in SurfaceAppearance3D, spatial transforms
  in Node3D/Mesh3D and shader behavior in Shader3D. Shared composition helpers create
  real inspectable children and do not move game behavior into the engine.
- textures: surfaces, sky, ui, characters, particles, materials, internal.
  audio: music, ambient, effects. models: characters, examples, sources.
  shaders: engine, examples, particles. Keep paired model sidecars/MTLs adjacent.
- Engine UI: drawing, input, layout, spatial and node definitions. Renderer: pipeline,
  shadows, geometry, quality and debug. Workspace: inspectors, curves, panels, tree
  and debug. Game examples are grouped by their domain, with explicit route catalog.
- Keep current documentation in categorized guides and reference images. Release
  notes, historical reports and migration plans belong outside the project source.
- Vendor dependencies retain upstream layout. Do not rewrite external identifiers
  or scatter compatibility modules merely to preserve old require paths.
