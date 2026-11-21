-- The examples project the tests run against: KATSA_PROJECT, else the folder next to the engine.
-- Returned as an absolute path (the filesystem layer rejects `..` segments).
local folder = os.getenv('KATSA_PROJECT') or '../katsa-engine-examples'
local pipe = io.popen('cd "' .. folder .. '" 2>/dev/null && pwd')
local absolute = pipe:read('*l')
pipe:close()

return absolute or folder
