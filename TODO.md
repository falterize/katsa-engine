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
