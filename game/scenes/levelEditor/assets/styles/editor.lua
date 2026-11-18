-- Editor style sheet (uiStyler). Widgets carry tags; colours come from the theme tokens, so the
-- Settings window can switch dark/light at runtime. Later rules win equal specificity, so state
-- tags (`on`, `selected`) come after the base ones.
return {
    { 'Frame.dock', { backgroundColor = '$panel', backgroundTransparency = 0 } },
    { 'Frame.bar', { backgroundColor = '$toolbar', backgroundTransparency = 0 } },
    { 'Frame.sep', { backgroundColor = '$border', backgroundTransparency = 0 } },
    { 'Frame.window', { backgroundColor = '$panel', backgroundTransparency = 0, corner = '$corner', stroke = { color = '$border', thickness = 1 } } },
    { 'Frame.dim', { backgroundColor = '$background', backgroundTransparency = 0.45 } },
    { 'Button.splitter', { backgroundColor = '$background', backgroundTransparency = 0 } },
    { 'ScrollFrame.list', { backgroundColor = '$background', backgroundTransparency = 0 } },
    { 'ScrollFrame.popupList', { backgroundTransparency = 1 } },
    { 'Label.title', { textColor = '$text', fontSize = 14 } },
    { 'Label.text', { textColor = '$text', fontSize = 13 } },
    { 'Label.classTag', { textColor = '$muted', fontSize = 11 } },
    { 'Label.muted', { textColor = '$muted', fontSize = 13 } },
    { 'TextBox.field', { backgroundColor = '$background', textColor = '$text', corner = 3, stroke = { color = '$border', thickness = 1 } } },
    { 'Button.tool', { backgroundColor = '$button', backgroundTransparency = 0, textColor = '$text', corner = '$corner' } },
    { 'Button.tab', { backgroundColor = '$panel', backgroundTransparency = 0, textColor = '$muted', corner = '$corner' } },
    { 'Button.row', { backgroundColor = '$panel', backgroundTransparency = 1, textColor = '$text' } },
    { 'Button.icon', { backgroundColor = '$button', backgroundTransparency = 1, textColor = '$muted' } },
    { 'Button.danger', { textColor = '$danger' } },
    { 'Button.on', { backgroundColor = '$accent', backgroundTransparency = 0, textColor = '$accentText' } },
    { 'Button.selected', { backgroundColor = '$selection', backgroundTransparency = 0, textColor = '$text' } },
    { 'Button.disabled', { textColor = '$muted' } },
    { 'Frame.marquee', { backgroundColor = '$accent', backgroundTransparency = 0.8, stroke = { color = '$accent', thickness = 1 } } },
    { 'Frame.dropLine', { backgroundColor = '$accent', backgroundTransparency = 0 } },
    { 'Frame.dropInto', { backgroundColor = '$accent', backgroundTransparency = 0.7 } },
}
