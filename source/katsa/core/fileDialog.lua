-- Native "open file" dialog. Windows uses the common dialog (comdlg32), Linux asks zenity or
-- kdialog, macOS uses osascript. The call blocks until the dialog closes. Returns a list of
-- absolute paths (empty when cancelled) or nil plus a reason when no dialog is available.
local ffi = require('ffi')

local FileDialog = {}

local function shellQuote(text)
    return "'" .. tostring(text):gsub("'", "'\\''") .. "'"
end

local function run(command)
    local pipe = io.popen(command, 'r')
    if not pipe then
        return nil
    end
    local output = pipe:read('*a') or ''
    pipe:close()
    return output
end

local function lines(output)
    local list = {}
    for line in (output or ''):gmatch('[^\r\n]+') do
        list[#list + 1] = line
    end
    return list
end

local function commandExists(name)
    local out = run('command -v ' .. name .. ' 2>/dev/null')
    return out ~= nil and out:match('%S') ~= nil
end

local function windows(options)
    ffi.cdef([[
        typedef struct {
            uint32_t lStructSize; void* hwndOwner; void* hInstance;
            const uint16_t* lpstrFilter; uint16_t* lpstrCustomFilter;
            uint32_t nMaxCustFilter; uint32_t nFilterIndex;
            uint16_t* lpstrFile; uint32_t nMaxFile;
            uint16_t* lpstrFileTitle; uint32_t nMaxFileTitle;
            const uint16_t* lpstrInitialDir; const uint16_t* lpstrTitle;
            uint32_t Flags; uint16_t nFileOffset; uint16_t nFileExtension;
            const uint16_t* lpstrDefExt; intptr_t lCustData; void* lpfnHook;
            const uint16_t* lpTemplateName; void* pvReserved; uint32_t dwReserved; uint32_t FlagsEx;
        } KatsaOpenFileName;
        int GetOpenFileNameW(KatsaOpenFileName* dialog);
        void* GetActiveWindow(void);
        int MultiByteToWideChar(unsigned codePage, uint32_t flags, const char* text, int bytes, uint16_t* out, int size);
        int WideCharToMultiByte(unsigned codePage, uint32_t flags, const uint16_t* text, int chars, char* out, int size, const char* defaultChar, int* used);
    ]])
    local comdlg, kernel, user = ffi.load('comdlg32'), ffi.load('kernel32'), ffi.load('user32')
    local function wide(text)
        local size = kernel.MultiByteToWideChar(65001, 0, text, #text, nil, 0)
        local buffer = ffi.new('uint16_t[?]', size + 1)
        kernel.MultiByteToWideChar(65001, 0, text, #text, buffer, size)
        return buffer, size
    end
    -- Filters: "Name\0*.a;*.b\0...\0\0" as UTF-16.
    local parts = {}
    for _, filter in ipairs(options.filters or { { 'All files', '*' } }) do
        local patterns = {}
        for ext in tostring(filter[2]):gmatch('[^;,]+') do
            patterns[#patterns + 1] = ext == '*' and '*.*' or ('*.' .. ext:gsub('^%*?%.?', ''))
        end
        parts[#parts + 1] = filter[1] .. '\0' .. table.concat(patterns, ';') .. '\0'
    end
    local filterText = table.concat(parts) .. '\0'
    local filterBuffer = ffi.new('uint16_t[?]', #filterText + 1)
    local index = 0
    for position = 1, #filterText do
        filterBuffer[index] = filterText:byte(position)
        index = index + 1
    end
    local MAX = 32768
    local file = ffi.new('uint16_t[?]', MAX)
    local title = wide(options.title or 'Open')
    local dialog = ffi.new('KatsaOpenFileName')
    dialog.lStructSize = ffi.sizeof(dialog)
    dialog.hwndOwner = user.GetActiveWindow()
    dialog.lpstrFilter = filterBuffer
    dialog.nFilterIndex = 1
    dialog.lpstrFile = file
    dialog.nMaxFile = MAX
    dialog.lpstrTitle = title
    -- FILEMUSTEXIST | PATHMUSTEXIST | NOCHANGEDIR | EXPLORER | (ALLOWMULTISELECT)
    dialog.Flags = 0x1000 + 0x800 + 0x8 + 0x80000 + (options.multiple and 0x200 or 0)
    if comdlg.GetOpenFileNameW(dialog) == 0 then
        return {}
    end
    local function utf8(offset)
        local length = 0
        while file[offset + length] ~= 0 do
            length = length + 1
        end
        if length == 0 then
            return nil, offset
        end
        local size = kernel.WideCharToMultiByte(65001, 0, file + offset, length, nil, 0, nil, nil)
        local buffer = ffi.new('char[?]', size)
        kernel.WideCharToMultiByte(65001, 0, file + offset, length, buffer, size, nil, nil)
        return ffi.string(buffer, size), offset + length + 1
    end
    -- One name: a full path. Several: the folder, then each file name, separated by NULs.
    local first, nextOffset = utf8(0)
    local second, afterSecond = utf8(nextOffset)
    if not second then
        return { first }
    end
    local result = { first .. '\\' .. second }
    local offset = afterSecond
    while true do
        local name
        name, offset = utf8(offset)
        if not name then
            break
        end
        result[#result + 1] = first .. '\\' .. name
    end
    return result
end

local function linux(options)
    local title = options.title or 'Open'
    if commandExists('zenity') then
        local command = 'zenity --file-selection --title=' .. shellQuote(title)
            .. (options.multiple and " --multiple --separator='\n'" or '')
        for _, filter in ipairs(options.filters or {}) do
            local patterns = {}
            for ext in tostring(filter[2]):gmatch('[^;,]+') do
                patterns[#patterns + 1] = ext == '*' and '*' or ('*.' .. ext:gsub('^%*?%.?', ''))
            end
            command = command .. ' --file-filter=' .. shellQuote(filter[1] .. ' | ' .. table.concat(patterns, ' '))
        end
        return lines(run(command .. ' 2>/dev/null'))
    elseif commandExists('kdialog') then
        local command = 'kdialog --title ' .. shellQuote(title)
            .. (options.multiple and ' --multiple --separate-output' or '') .. ' --getopenfilename .'
        return lines(run(command .. ' 2>/dev/null'))
    end
    return nil, 'Install zenity or kdialog to get a file dialog; drag files into the window instead'
end

local function mac(options)
    local script = options.multiple
            and 'set f to choose file with multiple selections allowed\nset out to ""\nrepeat with i in f\nset out to out & POSIX path of i & linefeed\nend repeat\nreturn out'
        or 'POSIX path of (choose file)'
    return lines(run('osascript -e ' .. shellQuote(script) .. ' 2>/dev/null'))
end

-- options: { title = string, multiple = boolean, filters = { { 'Name', 'ext;ext' }, ... } }
function FileDialog.open(options)
    options = options or {}
    local os = ffi.os
    local ok, result, reason
    if os == 'Windows' then
        ok, result = pcall(windows, options)
    elseif os == 'OSX' then
        ok, result = pcall(mac, options)
    elseif os == 'Linux' then
        ok, result, reason = pcall(linux, options)
    else
        return nil, 'No native file dialog on ' .. tostring(os)
    end
    if not ok then
        return nil, tostring(result)
    end
    return result, reason
end

return FileDialog
