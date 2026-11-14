-- Node replication: the server creates, changes and deletes nodes and every client sees it, the
-- way Roblox's network works. Whatever a client does to its own world stays on that client.
--
--   server:replicate(world)                       client:replicate(world)
--   node.replicated = true                        -- the node appears on every client
--   node.replicatedProperties = { 'position' }   -- these properties follow the server
--   node:setAttribute('Timer', 30)                -- clients read node:getAttribute('Timer')
--
-- What replicates: a node with `replicated = true` and every node inside `ReplicatedStorage`; its
-- class, name, parent (the nearest replicated ancestor), attributes (booleans, numbers, strings and
-- tables of them) and the properties it lists in `replicatedProperties`. Nothing else leaves the
-- machine, and `ServerStorage` is never scanned. Server writes win over a client's local edit of
-- the same property at the next change. Guide: docs/guides/development/replication.md.
return {
    Server = require('./server'),
    Client = require('./client'),
    Operations = require('./operations'),
    Storage = require('./storage'),
    Values = require('./values'),
}
