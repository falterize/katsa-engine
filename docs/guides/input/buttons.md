# Button2D and Button3D

Both are invisible components: put one under a node and that node becomes clickable. They share
settings and signals, so 2D and 3D code reads the same.

| Setting | Meaning |
| --- | --- |
| `enabled` | Off: the target is not clickable. |
| `priority` | When several buttons answer one click, higher goes first. |
| `includeDescendants` | On (default): everything below the target counts, so one button on a model, a `Node2D` or a physics body covers all its parts. Off: only the target itself. |

`Button3D` adds `adornee` (click another node), `radius` and `positionSource` (distance from
the interaction source). Signals on both: `press`, `release`, `click`, `cancel`, each with
`(pointerId, target)`. Code can call `press(id)`, `release(id)`, `cancel(id)` and `click(id)`.

```lua
-- A text button: a Label with a Button2D inside.
local play = ui:create('Label', { text = 'Play', size = { 0, 160, 0, 48 } }, ui.content)
ui:create('Button2D', {}, play):connect('click', function(id, target)
    startGame()
end)

-- A physical 2D object: its UI children are the hit area while it moves.
ui:create('Button2D', {}, body):connect('click', function() end)
```

`Button2D` works on UI nodes (Frame, Label, ImageRect...), `Node2D`, `Body2D` and plain nodes of
a screen `World2D`. A `Node2D` or `Body2D` is hit through the UI nodes below it; a bare
`Collider2D` without a visual child is not picked.
