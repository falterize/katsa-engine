-- The launcher's style sheet. Selectors: Class (a node class), .tag (class + tag as Class.tag).
-- Values starting with '$' come from the active theme (see the uiStyler plugin's themes).
return {
    { 'Frame.root', { backgroundColor = '$background', backgroundTransparency = 0 } },
    { 'Frame.toolbar', { backgroundColor = '$toolbar', backgroundTransparency = 0.08, stroke = { color = '$border', thickness = 1 } } },
    { 'Button.tool', {
        backgroundTransparency = 1,
        textColor = '$text',
        fontSize = '$smallFontSize',
        corner = '$corner',
    } },
    { 'ImageLabel.icon', { imageColor = '$text' } },
    { 'ImageLabel.accentIcon', { imageColor = '$accent' } },
    { 'Frame.listPanel', { backgroundColor = '$panel', backgroundTransparency = 0.12, corner = '$corner' } },
    { 'Frame.group', { backgroundColor = '$panelAlt', backgroundTransparency = 0.1 } },
    { 'TextLabel.groupTitle', { textColor = '$text', fontSize = '$fontSize' } },
    { 'Button.instance', { backgroundTransparency = 1, corner = '$corner' } },
    { 'Button.selected', { backgroundColor = '$selection', backgroundTransparency = 0 } },
    { 'TextLabel.title', { textColor = '$text', fontSize = '$fontSize' } },
    { 'TextLabel.muted', { textColor = '$muted', fontSize = '$smallFontSize' } },
    { 'Frame.actions', { backgroundColor = '$panel', backgroundTransparency = 0.05, corner = '$corner', stroke = { color = '$border', thickness = 1 } } },
    { 'Button.action', {
        backgroundColor = '$button',
        backgroundTransparency = 0,
        textColor = '$text',
        fontSize = '$fontSize',
        corner = '$corner',
        stroke = { color = '$border', thickness = 1 },
    } },
    { 'Button.primary', { backgroundColor = '$accent', textColor = '$accentText', stroke = { color = '$accent', thickness = 1 } } },
    { 'Button.danger', { textColor = '$danger' } },
    { 'Frame.status', { backgroundColor = '$toolbar', backgroundTransparency = 0.05, stroke = { color = '$border', thickness = 1 } } },
}
