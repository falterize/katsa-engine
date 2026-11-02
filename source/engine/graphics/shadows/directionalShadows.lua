local Math = require('../../math.math3d')
local Cascades = require('./directionalCascades')
local Projection = require('./shadowProjection')
local Frusta = require('./shadowFrusta')

local Directional = {}

function Directional.prepare(shadows, record, camera, settings)
    record.cascadeCandidates = record.cascadeCandidates or {}
    record.cascadePosition = record.cascadePosition or {}
    local changed = false
    for cascade = 1, Cascades.count do
        local candidate = record.cascadeCandidates[cascade] or Math.identity()
        record.cascadeCandidates[cascade] = candidate
        local extent = Cascades.prepare(
            camera,
            record.light.worldDirection,
            settings.distance,
            shadows.resolution,
            cascade,
            record.cascadePosition
        )
        Projection.install(
            record.cascadePosition,
            record.light.worldDirection,
            extent,
            settings.near,
            settings.distance * 3,
            true,
            candidate,
            shadows.view,
            shadows.projection
        )
        local published = shadows.matrices[record.base + cascade]
        for i = 1, 16 do
            changed = changed or published[i] ~= candidate[i]
        end
    end
    return changed
end

function Directional.draw(shadows, record, world, time)
    record.cascadeMatrices = record.cascadeMatrices or {}
    for cascade = 1, Cascades.count do
        local matrix = shadows.matrices[record.base + cascade]
        for i = 1, 16 do
            matrix[i] = record.cascadeCandidates[cascade][i]
        end
        record.cascadeMatrices[cascade] = matrix
        shadows:drawFace(world, matrix, record.base + cascade - 1, time)
        record.facesDirty[cascade], record.facesValid[cascade] = false, true
        for row = 0, 3 do
            local i = row * 4
            shadows.matrixPixels:setPixel(
                row,
                record.base + cascade - 1,
                matrix[i + 1],
                matrix[i + 2],
                matrix[i + 3],
                matrix[i + 4]
            )
        end
    end
    record.frusta = Frusta.prepare(record.cascadeMatrices, record.frusta)
    shadows.directionalMatricesChanged = true
end

return Directional
