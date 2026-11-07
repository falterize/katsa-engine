-- ImageLoader: decodes image files (PNG, JPEG, ...) on worker threads.
--
--   local loader = ImageLoader.new()          -- one worker per spare core, at most 4
--   loader:load('assets/hero.png', function(ok, image) ... end)   -- image: an ImageData
--   loader:update()                           -- every frame; callbacks run here, on the main thread
--
-- Reading the file stays on the calling thread (so archives and the save folder work); the
-- decoding, which is the slow part, runs on a worker and hands the pixels back through shared
-- memory. The callback receives an ordinary `katsa.image` ImageData (one memory copy).
local ffi = require('ffi')
local Pool = require('source.engine.actors.pool')
local SharedArray = require('source.katsa.thread.sharedArray')

local ImageLoader = {}
ImageLoader.__index = ImageLoader

local SCRIPT = [[
local ffi = require('ffi')
local nativeLib = require('source.katsa.core.nativeLib')
local SharedArray = require('source.katsa.thread.sharedArray')
Actor.on('decode', function(bytes)
    local pixels, width, height = nativeLib.decodeImage(bytes)
    if not pixels then
        error('Could not decode image: ' .. tostring(width))
    end
    local size = width * height * 4
    local shared = SharedArray.new('uint8_t', size)
    ffi.copy(shared.data, pixels, size)
    return { handle = shared:giveAway(), width = width, height = height }
end)
]]

function ImageLoader.new(size)
    local workers = size or math.min(4, Pool.defaultSize())
    return setmetatable({ pool = Pool.new({ script = SCRIPT, size = workers, name = 'images' }) }, ImageLoader)
end

-- `source` is a file path or the encoded bytes. callback(ok, imageOrError).
function ImageLoader:load(source, callback)
    local bytes = source
    if #source < 1024 and not source:find('\0', 1, true) then
        local message
        bytes, message = katsa.filesystem.read(source)
        if not bytes then
            callback(false, message)
            return
        end
    end
    self.pool:request('decode', bytes, function(ok, result)
        if not ok then
            callback(false, result)
            return
        end
        local shared = SharedArray.adopt(result.handle, 'uint8_t', result.width * result.height * 4)
        local image = katsa.image.newImageData(
            result.width,
            result.height,
            'rgba8',
            ffi.string(shared.data, shared.count)
        )
        shared:release()
        callback(true, image)
    end)
end

function ImageLoader:update(limit)
    return self.pool:update(limit)
end

function ImageLoader:getPending()
    return self.pool:getPending()
end

function ImageLoader:destroy(joinMs)
    self.pool:destroy(joinMs)
end

return ImageLoader
