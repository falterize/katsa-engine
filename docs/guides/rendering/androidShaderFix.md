# Android shader link fix — v35 (retained in v36)

The Android screenshot reports cross-stage matrix stride mismatches for Model, ViewProjection and ObjectNormalMatrix. In v34 these uniforms were declared in both stages, although only the vertex stage used them. Different GLES stage precision defaults can produce incompatible matrix declarations on mobile drivers.

v35 and v36 declare these matrices only inside VERTEX. WorldPosition and WorldNormal use matching explicit highp precision in both stages. Instance attributes, vertex matrices and lighting distances use highp. Sky uniforms are pixel-only and ray calculations use highp. No global default precision statement is added, because LÖVE supplies shader function prototypes before user code.

The runtime suite validates both shaders as GLSL ES before opening a 3D scene. Desktop shader validation and actual Mesa rendering cannot certify compatibility with every Android GPU. Repeat the menu-to-game transition on the affected device.

References:
- https://love2d.org/wiki/Shader_Variables
- https://love2d.org/wiki/love.graphics.validateShader
- https://love2d.org/wiki/GLES_Shader_Testing_in_Desktop
