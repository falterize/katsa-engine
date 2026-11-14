local Node = require('./baseNode')

-- ReplicatedStorage and ServerStorage (net/replication/storage.lua). Its content is replicated, or
-- not, by the container itself, so the node has no `replicated` switch of its own.
local Class = Node.define('StorageFolder', 'Folder')
return Class
