local Node = require('./baseNode')

-- The top node of a scene (`scene.root`). Its children are ordinary nodes: the main World3D (with
-- the World2D inside it), ReplicatedStorage and ServerStorage. It owns no world of its own and
-- draws nothing; it only gives scripts one place to start from, like `game` in Roblox:
-- `scene.root:findPath('World3D/Map/House')`.
local Class = Node.define('Game', 'Node')
return Class
