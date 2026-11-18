# TODO

## UI: event-driven layout invalidation

`UI:layout()` decides whether anything changed by scanning every property of every node
(`source/engine/ui/layout/changeTracking.lua`, compiled schemas in `core/valueSnapshot.lua`).
That costs roughly 0.75 ms per call at 640 UI nodes (it was 1.2 ms before type tests stopped
going through `node:isA`), and it runs on every call of `getAbsolutePosition()`,
`getAbsoluteSize()`, `UI:hit()`, `UI:pointer()` and once per draw. The cost grows with the node
count, so large UIs (the level editor) pay for it several times per frame.

Goal: make `layout()` nearly free when nothing changed.

- Mark a node dirty when a layout-relevant property is written: through `__newindex` for absent
  keys, `PropertyChanges.set` for observed fields, and the managed vector `revision` for
  `position[1] = x` style writes.
- The hard part: properties stored as raw fields on the instance never reach `__newindex`, so
  they must move behind the typed/observed store (or be written through setters) before polling
  can be dropped. Engine code that writes scroll offsets, text measurements and layout results
  with `rawset` needs the same audit.
- Keep the polling scan as a debug check (`KATSA_VERIFY_LAYOUT`): run both and assert that the
  dirty flags never miss a change. The v106.8 suite (991+ UI checks) and the scene smoke tests
  are the regression net; real-GPU and Windows behaviour need the owner's confirmation.
- Until then, per-frame polling code should lay out once per frame (the level editor's
  `Kit.rect`) instead of calling the absolute getters in loops.

## multiplayerCars: collisions with other cars

- **Fixed (v108.9):** a car rammed by a client-driven car was launched (28 m/s in the probe, "into the
  sky" at time scale 4). The server keeps a kinematic stand-in for every client-driven car; its
  velocity was derived from the pose change per physics step, which is zero between network updates
  and several times the real speed on the step a pose lands, and a kinematic body never loses
  speed in a hit (infinite mass) while the real car was stopped by the same hit on its client. The
  stand-in now takes the replicated speed, and `PhysicsCar:limitPush` limits what a struck car can
  gain to the equal-mass collision result and caps hit speed and lift. Probe:
  `--test-v108.9.cars.accel` (`KATSA_SCALE=4` runs it at time scale 4).
- **Open:** the two-sided hit is still approximate. Properly, the server should run one shared
  contact with finite masses (the driver's client sends the impact, the server applies the
  impulse to the bot, and the client applies the reaction), instead of two independent solves.
- **Open, needs a decision:** car acceleration feels too fast. It matches the configuration
  (`acceleration = 24` m/s^2, 0 to 100 km/h in about 1.3 s; it was 14 before the "snappier car
  physics" commit) and both worlds step exactly once per 1/60 s, so it is tuning, not a
  server/client split artefact. Candidate: 14 to 16, with a gentler start and the top-speed taper.
