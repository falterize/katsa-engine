# replicationLab

Example of node replication: rounds, teleporting, nicknames and chat on a hosted server.

- Server (`server/scripts`): `rounds.lua` runs Intermission, Playing and Results; the `Round`
  node carries `State`/`Timer` attributes, coins `Coin<N>` and a moving `Platform` are replicated
  nodes. Players are teleported to the lobby or arena through the `Teleport` remote. `roster.lua`
  keeps `Players` nodes with `Nickname`/`Score`; `bots.lua` adds bots; `chat.lua` validates messages.
- Client (`scripts`): `game/session.lua` joins and calls `client:replicate`, `avatarView.lua`
  builds the model, AnimationTree and nickname for each avatar, `ui/` holds the HUD and chat
  (Enter opens the chat). The controller is shared with stareShooter
  (`source/game/characters`).
- Test: `validation/tests/versions/v108_8/replicationLab.lua`.
