# UIStyler plugin

Style sheets for UI nodes with themes that switch at runtime. Enable it per scene with
`plugins = { 'uiStyler' }` in `settings.lua`; the *Launcher UI* scene (`launcherShowcase`) is the
reference: a launcher window (toolbar with icons, grouped list, action panel, status bar) styled
only by `scripts/styles/sheet.lua` and the theme token files.

```lua
local UIStyler = require('source.engine.plugins').require('uiStyler')
local styler = UIStyler.new(scene.ui)
styler:defineTheme('dark', UIStyler.themes.dark)     -- tokens: plugins/uiStyler/themes/dark.lua
styler:defineTheme('light', UIStyler.themes.light)
styler:sheet({
    { 'Frame.toolbar', { backgroundColor = '$toolbar', stroke = { color = '$border', thickness = 1 } } },
    { 'Button', { textColor = '$text', corner = '$corner' } },
    { 'Button.primary', { backgroundColor = '$accent' } },
    { '#Search', { textColor = '$muted' } },
})
styler:setTheme('dark')
styler:apply(scene.ui.content)       -- also call it for subtrees created later
node:addTag('primary')               -- tags choose rules; restyle with styler:apply(root)
styler:setTheme('light')             -- every applied root is restyled
```

## Selectors

| Selector | Matches | Specificity |
| --- | --- | --- |
| `*` | every node | 0 |
| `Button` | a class (inheritance counts, `Frame` also matches buttons) | 1 |
| `.primary` | a tag | 10 |
| `Button.primary` | class and tag | 11 |
| `#Search` | the node name | 100 |

Higher specificity wins; equal specificity: the later rule wins.

## Values

- A plain value, a table (strings inside are resolved recursively) or `function(tokens, node)`.
- `'$name'` reads the theme token `name`; unknown tokens or themes raise an error.
- `corner = n` adds one `UICorner`; `stroke = { color, thickness, transparency }` adds one border `UIStroke`.
  Both are updated in place on later passes and removed when no rule asks for them.
- A property the styler set is restored to its authored value when no rule sets it any more.

Theme token files are plain tables (one file per theme), so a new theme is one file with the same keys.
