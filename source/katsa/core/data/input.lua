-- katsa.data functions take either a string or a Data object (FileData, ByteData, ...).
local Input = {}

function Input.toString(value)
    if type(value) == 'table' and value.getString then
        return value:getString()
    end
    return value
end

return Input
