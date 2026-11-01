local Types = require('source.engine.graphics.shadows.sourceTypes')
local kind, faces, pointDirections = Types.kind, Types.faces, Types.pointDirections
local ShadowAtlas = {}

function ShadowAtlas.install(Shadows)
    function Shadows:resize(resolution, faceCount)
        local columns = math.ceil(math.sqrt(faceCount))
        local rows = math.ceil(faceCount / columns)
        local limit = katsa.graphics.getSystemLimits().texturesize
        local effective = math.min(resolution, math.floor(limit / math.max(columns, rows)))
        assert(effective >= 32, 'GPU texture limit cannot fit the active shadow maps')
        if self.resolution == effective and self.columns == columns and self.rows == rows then
            return
        end
        if self.depth then
            self.depth:release()
        end
        self.atlasAllocations = self.atlasAllocations + 1
        assert(katsa.graphics.getCanvasFormats().depth24, 'Shadow mapping requires readable depth24')
        self.depth = katsa.graphics.newCanvas(
            effective * columns,
            effective * rows,
            { format = 'depth24', readable = true, dpiscale = 1 }
        )
        self.depth:setDepthSampleMode()
        self.depth:setFilter('nearest', 'nearest')
        self.depth:setWrap('clamp', 'clamp')
        self.texelSize[1], self.texelSize[2] = 1 / (effective * columns), 1 / (effective * rows)
        self.atlasSize[1], self.atlasSize[2] = columns, rows
        self.resolution, self.columns, self.rows = effective, columns, rows
        self.nextUpdate = 0
        self.atlasInvalid = true
    end
end

return ShadowAtlas
