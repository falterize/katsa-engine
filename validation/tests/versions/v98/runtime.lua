local T = {}

local function extra(test)
    local Opacity = require('source.engine.materials.opacity')
    local ffi = require('ffi')
    local data = katsa.image.newImageData(257, 65, 'rgba8')
    local pointer = ffi.cast('uint8_t*', data:getFFIPointer())
    ffi.fill(pointer, data:getSize(), 255)
    local image = katsa.graphics.newImage(data)
    Opacity.register(image, data)
    test:check(
        Opacity.image(image),
        'Block opacity classification accepts a fully opaque multi-block image'
    )
    for _, pixel in ipairs({ 0, 1, 16382, 16383, 16384, 16704 }) do
        pointer[pixel * 4 + 3] = 254
        Opacity.register(image, data)
        test:check(
            not Opacity.image(image),
            'Block opacity classification finds alpha at pixel ' .. pixel
        )
        pointer[pixel * 4 + 3] = 255
    end
    -- Binary zero RGB bytes must remain ordinary pattern characters.
    ffi.fill(pointer, data:getSize(), 0)
    for i = 3, data:getSize() - 1, 4 do
        pointer[i] = 255
    end
    Opacity.register(image, data)
    test:check(Opacity.image(image), 'Zero RGB bytes do not invalidate opaque alpha')
    image:release()
    data:release()
    local Batches = require('source.engine.graphics.pipeline.batches')
    local batch = Batches.new()
    local mesh = katsa.graphics.newMesh(
        { { 'VertexPosition', 'float', 3 } },
        { { 0, 0, 0 }, { 1, 0, 0 }, { 0, 1, 0 } },
        'triangles'
    )
    local group = { data = {}, example = { geometry = { mesh = mesh } }, dirty = true }
    batch.groups[1] = group
    for count = 1, 65 do
        local row = {}
        for j = 1, 27 do
            row[j] = j + count
        end
        group.data[count] = row
        group.dirty = true
        group.dirtyFirst = count
        group.dirtyLast = count
        batch:upload(group)
        batch:detach(mesh)
        assert(
            group.capacity >= count and group.capacity < math.max(16, count * 2),
            'Unbounded instance capacity'
        )
        local first = group.mesh:getVertex(count)
        assert(first == row[1], 'Instance growth did not preserve the current vertex row')
    end
    test:check(
        batch.meshAllocations == 5,
        '65 gradual instance additions require five bounded allocations'
    )
    batch:release()
    mesh:release()
end

function T.new(manager)
    local base = require('validation.tests.versions.v97.runtime').new(manager)
    local finish = base.finish
    base.finish = function(test)
        extra(test)
        finish(test)
        print('PASSED ' .. test.count .. ' v98 regression/integration checks')
    end
    return base
end

return T
