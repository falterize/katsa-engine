-- Manual CSV snapshots. Serialization is independent of the UI and never runs while idle.
local Version = require('source.engine.core.version')
local Export = {}
local columns = {
    'schema',
    'app_version',
    'exported_utc',
    'scene',
    'physics_backend',
    'scope',
    'window_seconds',
    'window_end_seconds',
    'metric_id',
    'label',
    'unit',
    'bucket_start_seconds',
    'last_sample_seconds',
    'samples',
    'sample_mean',
    'min',
    'max',
    'last',
    'aggregation',
    'duration_seconds',
}

local function csv(value)
    if value == nil then
        return ''
    end
    local text = type(value) == 'number' and string.format('%.17g', value) or tostring(value)
    if text:find('[,"\r\n]') then
        return '"' .. text:gsub('"', '""') .. '"'
    end
    return text
end

local function row(output, values)
    local cells = {}
    for index = 1, #columns do
        cells[index] = csv(values[index])
    end
    output[#output + 1] = table.concat(cells, ',')
end

function Export.build(definitions, histories, options)
    assert(options.seconds == 5 or options.seconds == 30, 'Export window must be 5 or 30 seconds')
    assert(options.scope == 'selected' or options.scope == 'all', 'Unknown export scope')
    assert(
        type(options.time) == 'number' and options.time >= 0 and options.time < math.huge,
        'Export time must be finite and nonnegative'
    )
    local selected
    for _, definition in ipairs(definitions) do
        if definition.id == options.metricId then
            selected = definition
        end
    end
    assert(options.scope == 'all' or selected, 'Select a metric before exporting its history')
    local output = { table.concat(columns, ',') }
    local cutoff, rows = options.time - options.seconds, 0
    local utc = options.utc or os.date('!%Y-%m-%dT%H:%M:%SZ')
    for _, definition in ipairs(definitions) do
        if options.scope == 'all' or definition == selected then
            local history, recorded = histories[definition.id], false
            local function append(bucket)
                row(output, {
                    2,
                    Version.value,
                    utc,
                    options.scene or '',
                    options.backend or 'none',
                    options.scope,
                    options.seconds,
                    options.time,
                    definition.id,
                    definition.label,
                    definition.unit or '',
                    bucket and bucket.period * history.interval or '',
                    bucket and bucket.time or '',
                    bucket and bucket.samples or 0,
                    bucket and bucket.mean or '',
                    bucket and bucket.low or '',
                    bucket and bucket.high or '',
                    bucket and bucket.last or '',
                    history and history.aggregation == 'rate' and 'events/seconds' or 'arithmetic',
                    bucket and bucket.duration or '',
                })
                rows = rows + 1
            end
            if history then
                for index = 1, history.count do
                    local bucket = history:get(index)
                    if bucket.time >= cutoff and bucket.time <= options.time then
                        append(bucket)
                        recorded = true
                    end
                end
            end
            -- Explicit unavailable rows distinguish missing data from a measured zero.
            if not recorded then
                append(nil)
            end
        end
    end
    return table.concat(output, '\r\n') .. '\r\n', rows
end

function Export.save(definitions, histories, options)
    local data, rows = Export.build(definitions, histories, options)
    local folder = 'stats-logs'
    assert(love.filesystem.createDirectory(folder), 'Could not create the Stats log directory')
    local metric = options.scope == 'all' and 'all' or options.metricId
    local stem = folder
        .. '/stats-'
        .. os.date('!%Y%m%dT%H%M%SZ')
        .. '-'
        .. metric:gsub('[^%w_-]', '_')
        .. '-'
        .. options.seconds
        .. 's'
    local path, index = stem .. '.csv', 1
    while love.filesystem.getInfo(path) do
        path = stem .. '-' .. index .. '.csv'
        index = index + 1
    end
    assert(love.filesystem.write(path, data), 'Could not write the Stats log')
    return path, rows
end

return Export
