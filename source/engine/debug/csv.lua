-- Shared CSV cell/row formatting (RFC 4180 quoting, full-precision numbers).
local Csv = {}

function Csv.cell(value)
    if value == nil then
        return ''
    end
    local text = type(value) == 'number' and string.format('%.17g', value) or tostring(value)
    if text:find('[,"\r\n]') then
        return '"' .. text:gsub('"', '""') .. '"'
    end
    return text
end

function Csv.row(values, count)
    local cells = {}
    for index = 1, count or #values do
        cells[index] = Csv.cell(values[index])
    end
    return table.concat(cells, ',')
end

return Csv
