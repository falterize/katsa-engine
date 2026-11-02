local unpack = require('../../math.array').unpack
local ipairs = require('../../math.array').ipairs
local Types = require('./sourceTypes')
local kind, faces, pointDirections = Types.kind, Types.faces, Types.pointDirections
local ShadowBindings = {}

function ShadowBindings.install(Shadows)
    function Shadows:send(shader, lighting)
        local settings = lighting.shadows
        for _, record in ipairs(self.assignments) do
            local slot = record.light.slot
            if record.projectionPosition then
                self.lightProjectionPosition[slot] = record.projectionPosition
                self.lightProjectionDirection[slot] = record.projectionDirection
                self.lightData[slot][4] = record.projectionExtent
                local seconds = settings.sourceFadeSeconds or 0.15
                self.lightFade[slot] = record.publishedAt
                        and seconds > 0
                        and math.min(1, (katsa.timer.getTime() - record.publishedAt) / seconds)
                    or 1
            end
        end
        if shader:hasUniform('normalDebug') then
            shader:send('normalDebug', lighting.debug and lighting.debug.normalView == true)
        end
        if shader:hasUniform('shadowDebug') then
            shader:send('shadowDebug', lighting.debug and lighting.debug.shadowView == true)
        end
        if shader:hasUniform('shadowLightFade') then
            shader:send('shadowLightFade', unpack(self.lightFade))
        end
        if shader:hasUniform('shadowLightPosition') then
            shader:send('shadowLightPosition', unpack(self.lightProjectionPosition))
        end
        if shader:hasUniform('shadowLightDirection') then
            shader:send('shadowLightDirection', unpack(self.lightProjectionDirection))
        end
        if shader:hasUniform('lightShadowData') then
            if not self.enabled then
                for i = 1, 32 do
                    self.lightData[i][1] = -1
                end
            end
            shader:send('lightShadowData', unpack(self.lightData))
        end
        if shader:hasUniform('shadowDistance') then
            shader:send('shadowDistance', settings.distance)
        end
        if shader:hasUniform('shadowFadeDistance') then
            shader:send('shadowFadeDistance', settings.fadeDistance or settings.distance * 0.1)
        end
        if self.enabled then
            if shader:hasUniform('shadowAtlas') then
                shader:send('shadowAtlas', self.depth)
            end
            if shader:hasUniform('shadowMatrixData') then
                shader:send('shadowMatrixData', self.matrixTexture)
            end
            if shader:hasUniform('shadowAtlasSize') then
                shader:send('shadowAtlasSize', self.atlasSize)
            end
            self.parameters[1], self.parameters[2], self.parameters[3], self.parameters[4] =
                settings.bias, settings.normalBias, settings.strength, settings.filterSamples
            if shader:hasUniform('shadowSoftness') then
                assert(
                    settings.mode == nil
                        or settings.mode == 'Standard'
                        or settings.mode == 'Realistic',
                    'Shadow mode must be Standard or Realistic'
                )
                shader:send('shadowSoftness', {
                    settings.mode == 'Realistic' and 1 or 0,
                    settings.lightSize or 0.04,
                    settings.softnessLimit or 8,
                    settings.blockerSearchRadius or 4,
                })
            end
            if shader:hasUniform('shadowNear') then
                shader:send('shadowNear', settings.near)
            end
            if shader:hasUniform('shadowFaceResolution') then
                shader:send('shadowFaceResolution', self.resolution)
            end
            if shader:hasUniform('directionalShadowDepthScale') then
                shader:send(
                    'directionalShadowDepthScale',
                    1 / (settings.distance * 3 - settings.near)
                )
            end
            if shader:hasUniform('directionalShadowTexelDepth') then
                local range = settings.distance * 3 - settings.near
                shader:send('directionalShadowTexelDepth', {
                    2 * settings.distance / 8 / self.resolution / range,
                    2 * settings.distance / 3 / self.resolution / range,
                    2 * settings.distance / self.resolution / range,
                })
            end
            if shader:hasUniform('shadowParameters') then
                shader:send('shadowParameters', self.parameters)
            end
            if shader:hasUniform('shadowTexelSize') then
                shader:send('shadowTexelSize', self.texelSize)
            end
        end
    end
end

return ShadowBindings
