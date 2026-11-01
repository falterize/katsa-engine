local Paths = {}

function Paths.identifier(value)
    assert(type(value) == 'string' and value:match('^[%w_-]+$'), 'Invalid save identifier')
    assert(#value <= 80, 'Save identifier is too long')
    return value
end

function Paths.relative(value, directory)
    assert(type(value) == 'string' and #value <= 1024, 'Invalid data file path')
    if directory and value == '' then
        return value
    end
    value = value:gsub('\\', '/')
    assert(
        value ~= ''
            and not value:find('[%c:*?"<>|]')
            and value:sub(1, 1) ~= '/'
            and value:sub(-1) ~= '/'
            and not value:find('//', 1, true),
        'Use a relative data file path'
    )
    for part in value:gmatch('[^/]+') do
        assert(part ~= '.' and part ~= '..' and not part:find('[ .]$'), 'Invalid data path segment')
        local stem = (part:match('^[^.]+') or part):upper()
        assert(
            stem ~= 'CON'
                and stem ~= 'PRN'
                and stem ~= 'AUX'
                and stem ~= 'NUL'
                and not stem:match('^COM[1-9]$')
                and not stem:match('^LPT[1-9]$'),
            'Reserved data filename'
        )
    end
    assert(
        directory or not value:lower():match('%.tmp$') and not value:lower():match('%.bak$'),
        'The .tmp and .bak suffixes are reserved for data recovery'
    )
    return value
end

function Paths.namespace(value)
    value = Paths.relative(value, true)
    assert(value ~= '', 'Data scope must have a name')
    for part in value:gmatch('[^/]+') do
        assert(#part <= 80, 'Data scope segment is too long')
    end
    return value
end

return Paths
