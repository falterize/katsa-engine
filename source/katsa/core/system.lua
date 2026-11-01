-- katsa.system: operating system queries and shell integration.
local Native = require('source.katsa.core.native')

local System = {}
local platform

function System.setPlatform(p)
    platform = p
end

function System.getOS()
    local name = Native.os()
    if name == 'OSX' then
        return 'OS X'
    end
    return name
end

function System.getProcessorCount()
    return platform and platform:getProcessorCount() or 1
end

function System.getClipboardText()
    return platform and platform:getClipboard() or ''
end

function System.setClipboardText(text)
    if platform then
        platform:setClipboard(text)
    end
end

function System.openURL(url)
    return platform ~= nil and platform:openURL(url)
end

function System.getPowerInfo()
    return 'unknown', nil, nil
end

return System
