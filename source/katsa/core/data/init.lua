-- katsa.data: hashing, encoding, compression and binary packing.
local Data = {}

for _, name in ipairs({ 'hash', 'encoding', 'byteData', 'pack' }) do
    for key, value in pairs(require('source.katsa.core.data.' .. name)) do
        Data[key] = value
    end
end

return Data
