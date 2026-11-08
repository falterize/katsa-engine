return {
    name = 'uiStyler',
    title = 'UI Styler',
    version = '1.0.0',
    description = 'Style sheets for UI nodes: rules selected by class, tag or name that read '
        .. 'their values from a theme, with runtime theme switching.',
    requires = {},
    -- Adds the UIStyler node (theme and style folder in the Inspector).
    nodes = { UIStyler = './nodes.uiStyler' },
}
