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
- Maps: `maps.lua` builds the templates in `ServerStorage/Maps`; each round clones a random one
  into the world (replicated) and destroys it afterwards. Boxes carry the `Solid` attribute
  (`Moving` too for the platform): the client's `game/solids.lua` gives them physics bodies, and the
  character is carried by moving ones through `Player.carrier`. Bots stand on the map through
  `Maps:heightAt`, because the server has no physics.

<details><summary>Adding a map</summary><br>

Add a spec (boxes `{ x, y, z, width, height, depth, color }` around the arena centre and coins
`{ x, z, surface }`) to `SPECS` in `maps.lua`. Keep boxes axis aligned (the client bodies do not
rotate) and mesh names unique.

</details>

- Test: `validation/tests/versions/v108_8/replicationLab.lua`.
