// @fragmentDeclarations
uniform vec2 pixelCells;
// @fragmentCode
vec2 cells=max(pixelCells,vec2(1.0));
vec2 sampledUV=(floor(uv*cells)+0.5)/cells;
vec3 pixel=Texel(textureImage,sampledUV).rgb;
result=result/max(texel.rgb,vec3(0.02))*pixel;
