# Localization

`source/engine/localization` holds the strings of every language and picks the right one.

```lua
local Localization = require('source.engine.localization')
local L = Localization.get()                          -- the shared service
L:loadDirectory(scene.resources, 'shared://locales')  -- en.lua, ru.lua, de.lua
L:setLocale(L:detect())                               -- system language, else the fallback (en)
L:t('menu.play')                                      -- 'Play'
L:t('lab.items', { count = 5 })                       -- plural form + {count}
L:onChange(function(locale) end)
```

A locale file returns `{ name = 'Русский', font = optional, strings = { ... } }`. Strings are nested tables (read as
dotted keys) or flat. A table with `other` is a plural set (`one`, `few`, `many`, `other`) chosen by `params.count`
with the rules of the language (English-like languages, French, Russian/Ukrainian/Belarusian, Polish, and
none for Japanese, Chinese, Korean, Vietnamese, Thai, Indonesian; unknown languages use the English rule).
`{name}` marks are filled from `params`.

A key missing in the current language falls back to the `fallback` locale (default `en`), then to the key itself.
`L:getMissing()` lists the keys nobody found.

## In the UI

`Label`, `Button` and `TextBox` have `textKey` and `textParams`; set them and the text follows the language,
also while the game runs:

```lua
ui:button({ textKey = 'lab.more', onPress = ... }, panel)
ui:text({ textKey = 'lab.items', textParams = params }, panel)   -- change params.count in place
```

The inspector shows `textKey`. Fonts: choose a font per language yourself from `L:getMeta().font`.
Hot reload re-reads locale files while the game runs (see `hotReload.md`).

Example scene: `localizationLab`. Tests: `validation/tests/versions/v108_7/localization.lua`.
