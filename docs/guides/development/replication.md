# Node replication

The server owns the game world. What the server creates, changes or deletes is mirrored on every
client; what a client does to its own world stays on that client (the Roblox model).

## Marking what replicates

```lua
-- server
server:replicate(world)               -- once, after the world exists
local round = world:create('Folder', { name = 'Round', replicated = true })
round:setAttribute('Timer', 30)       -- attributes replicate with the node
pad.replicatedProperties = { 'position', 'color' }

-- client
client:replicate(clientWorld)
clientWorld.root.children  -- Round arrives with its attributes
client.nodeCreated:connect(function(node) end)
```

- `replicated` is a flag on every node (Node group in the inspector, off by default).
- `replicatedProperties` lists the properties that follow the server. It is stored on the node
  and is set from code.
- Everything inside `ReplicatedStorage` replicates without a flag. `ServerStorage` exists only on
  the server and is never scanned, so private nodes live there. A host is a normal client.
- A node's parent on the client is its nearest replicated ancestor (or the world root).

## Rules

- Server writes win: the next change of a property overwrites a client's local edit of it.
- Replicated values are plain: booleans, numbers, strings, vectors and tables of them. Node
  references are not replicated.
- Late joiners receive the full replicated tree, then incremental CREATE/CHANGE/REMOVE
  operations each snapshot tick (reliable channel).
- The server scans replicated nodes each tick; keep replicated trees small and use attributes for
  state such as timers and scores.
- Events between machines use Remotes (`server:remote(...)`, reliable or `remote:unreliable()`).

Code: `source/engine/net/replication/` (`values`, `operations`, `storage`, `server`, `client`).
Example: the `replicationLab` scene (`docs/guides/development/replicationLab.md`).
