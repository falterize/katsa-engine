-- katsa.process: start another program (typically this game as a dedicated server) and watch it.
--
--   local child = katsa.process.spawn({
--       command = katsa.process.getLaunchCommand({ '--scene', 'myGame', '--server', '7777' }),
--       console = true, -- Windows: the child opens its own console window
--       log = 'server.log', -- POSIX: where its output goes when it has no console
--   })
--   if child then print(child:getPid(), child:isRunning()) end
--   child:kill()
--
-- Supported on Windows, Linux and macOS (through the C library). Phones have no such thing:
-- `katsa.process.isSupported()` is false there and `spawn` returns nil with a reason.
local ffi = require('ffi')

local Process = {}
local Child = {}
Child.__index = Child

local launchBase
local launchBaseHasPath = true

-- Called once at startup with the program that started this process: the executable, the
-- launcher script a development run has (`luajit tools/dev/katsa.lua`) and the game source path.
function Process.setLaunchBase(parts, hasGamePath)
    launchBaseHasPath = hasGamePath ~= false
    launchBase = {}
    for index, value in ipairs(parts) do
        launchBase[index] = tostring(value)
    end
end

-- The command line that starts this same game again with `extra` game arguments.
function Process.getLaunchCommand(extra)
    if not launchBase then
        return nil
    end
    local command = {}
    for index, value in ipairs(launchBase) do
        command[index] = value
    end
    -- Without a game path on the command line (a packaged executable), a lone `--` tells the
    -- runtime that what follows are game arguments, not a path.
    if not launchBaseHasPath and extra and #extra > 0 then
        command[#command + 1] = '--'
    end
    for _, value in ipairs(extra or {}) do
        command[#command + 1] = tostring(value)
    end
    return command
end

function Process.isSupported()
    return ffi.os == 'Windows' or ffi.os == 'Linux' or ffi.os == 'OSX'
end

--------------------------------------------------------------------------------------------------
-- Windows

local win

local function windows()
    if win then
        return win
    end
    ffi.cdef([[
        typedef struct {
            unsigned long cb; wchar_t *lpReserved; wchar_t *lpDesktop; wchar_t *lpTitle;
            unsigned long dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars;
            unsigned long dwFillAttribute, dwFlags; unsigned short wShowWindow, cbReserved2;
            unsigned char *lpReserved2; void *hStdInput, *hStdOutput, *hStdError;
        } KATSA_STARTUPINFOW;
        typedef struct { void *hProcess; void *hThread; unsigned long dwProcessId, dwThreadId; } KATSA_PROCESS_INFORMATION;
        int CreateProcessW(const wchar_t *app, wchar_t *cmd, void *pa, void *ta, int inherit,
            unsigned long flags, void *env, const wchar_t *cwd, KATSA_STARTUPINFOW *si,
            KATSA_PROCESS_INFORMATION *pi);
        int GetExitCodeProcess(void *process, unsigned long *code);
        int TerminateProcess(void *process, unsigned int code);
        int CloseHandle(void *handle);
        void *OpenProcess(unsigned long access, int inherit, unsigned long pid);
        unsigned long GetCurrentProcessId(void);
        int MultiByteToWideChar(unsigned cp, unsigned long flags, const char *s, int n, wchar_t *out, int outn);
        int AllocConsole(void);
        void *GetConsoleWindow(void);
        void *__acrt_iob_func(unsigned index);
        void *freopen(const char *path, const char *mode, void *stream);
    ]])
    win = ffi.C
    return win
end

local function wide(text)
    local c = windows()
    local count = c.MultiByteToWideChar(65001, 0, text, -1, nil, 0)
    local buffer = ffi.new('wchar_t[?]', count)
    c.MultiByteToWideChar(65001, 0, text, -1, buffer, count)
    return buffer
end

-- CommandLineToArgvW's quoting rules: quote when needed, double the backslashes before a quote.
local function quote(argument)
    if argument ~= '' and not argument:find('[%s"]') then
        return argument
    end
    local escaped = argument:gsub('(\\*)"', '%1%1\\"'):gsub('(\\+)$', '%1%1')
    return '"' .. escaped .. '"'
end

local STILL_ACTIVE = 259
local CREATE_NEW_CONSOLE = 0x10
local PROCESS_QUERY_LIMITED_INFORMATION = 0x1000

local function spawnWindows(options)
    local c = windows()
    local parts = {}
    for index, value in ipairs(options.command) do
        parts[index] = quote(value)
    end
    local line = wide(table.concat(parts, ' '))
    local startup = ffi.new('KATSA_STARTUPINFOW')
    startup.cb = ffi.sizeof(startup)
    local info = ffi.new('KATSA_PROCESS_INFORMATION')
    local flags = options.console and CREATE_NEW_CONSOLE or 0
    if c.CreateProcessW(nil, line, nil, nil, 0, flags, nil, nil, startup, info) == 0 then
        return nil, 'CreateProcess failed'
    end
    c.CloseHandle(info.hThread)
    return setmetatable({ handle = info.hProcess, pid = tonumber(info.dwProcessId) }, Child)
end

--------------------------------------------------------------------------------------------------
-- POSIX

local posix

local function loadPosix()
    if posix then
        return posix
    end
    ffi.cdef([[
        typedef int katsa_pid_t;
        int posix_spawnp(katsa_pid_t *pid, const char *file, const void *actions, const void *attr,
            char *const argv[], char *const envp[]);
        int posix_spawn_file_actions_init(void *actions);
        int posix_spawn_file_actions_destroy(void *actions);
        int posix_spawn_file_actions_addopen(void *actions, int fd, const char *path, int oflag, unsigned mode);
        int posix_spawn_file_actions_adddup2(void *actions, int fd, int newfd);
        katsa_pid_t waitpid(katsa_pid_t pid, int *status, int options);
        int kill(katsa_pid_t pid, int signal);
        katsa_pid_t getpid(void);
        extern char **environ;
    ]])
    posix = ffi.C
    return posix
end

local function environment()
    if ffi.os == 'OSX' then
        ffi.cdef('char ***_NSGetEnviron(void);')
        return ffi.C._NSGetEnviron()[0]
    end
    return ffi.C.environ
end

local function spawnPosix(options)
    local c = loadPosix()
    local count = #options.command
    local argv = ffi.new('char*[?]', count + 1)
    local keep = {}
    for index, value in ipairs(options.command) do
        local copy = ffi.new('char[?]', #value + 1)
        ffi.copy(copy, value)
        keep[index] = copy
        argv[index - 1] = copy
    end
    local actions
    if options.log then
        actions = ffi.new('char[128]')
        c.posix_spawn_file_actions_init(actions)
        -- O_WRONLY | O_CREAT | O_APPEND differ between Linux and macOS.
        local flags = ffi.os == 'OSX' and (0x1 + 0x200 + 0x8) or (0x1 + 0x40 + 0x400)
        c.posix_spawn_file_actions_addopen(actions, 1, options.log, flags, 420)
        c.posix_spawn_file_actions_adddup2(actions, 1, 2)
    end
    local pid = ffi.new('katsa_pid_t[1]')
    local code = c.posix_spawnp(pid, argv[0], actions, nil, argv, environment())
    if actions then
        c.posix_spawn_file_actions_destroy(actions)
    end
    if code ~= 0 then
        return nil, 'posix_spawnp failed (' .. code .. ')'
    end
    return setmetatable({ pid = tonumber(pid[0]) }, Child)
end

--------------------------------------------------------------------------------------------------

-- options: command (list of strings), console (Windows: own console window), log (POSIX: file that
-- receives the output). Returns a child handle, or nil and a reason.
function Process.spawn(options)
    assert(type(options) == 'table' and type(options.command) == 'table', 'spawn needs a command list')
    if not Process.isSupported() then
        return nil, 'Starting programs is not supported on this platform'
    end
    local ok, child, reason = pcall(ffi.os == 'Windows' and spawnWindows or spawnPosix, options)
    if not ok then
        return nil, tostring(child)
    end
    return child, reason
end

function Child:getPid()
    return self.pid
end

function Child:isRunning()
    if self.exited then
        return false
    end
    if ffi.os == 'Windows' then
        local code = ffi.new('unsigned long[1]')
        if windows().GetExitCodeProcess(self.handle, code) == 0 or code[0] ~= STILL_ACTIVE then
            self.exited = true
        end
    else
        local status = ffi.new('int[1]')
        if loadPosix().waitpid(self.pid, status, 1) ~= 0 then -- WNOHANG: 0 while it still runs
            self.exited = true
        end
    end
    return not self.exited
end

-- Ends the child at once (use a shutdown command first when it should save or say goodbye).
function Child:kill()
    if self.exited then
        return
    end
    if ffi.os == 'Windows' then
        windows().TerminateProcess(self.handle, 1)
        windows().CloseHandle(self.handle)
        self.exited = true
    else
        loadPosix().kill(self.pid, 15)
    end
end

-- Whether a process with this id is still alive (used by a server to follow its parent).
function Process.isAlive(pid)
    if not Process.isSupported() then
        return true
    end
    if ffi.os == 'Windows' then
        local handle = windows().OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid)
        if handle == nil then
            return false
        end
        local code = ffi.new('unsigned long[1]')
        local alive = windows().GetExitCodeProcess(handle, code) ~= 0 and code[0] == STILL_ACTIVE
        windows().CloseHandle(handle)
        return alive
    end
    return loadPosix().kill(pid, 0) == 0 or ffi.errno() == 1 -- EPERM: it exists, it is not ours
end

function Process.getId()
    if ffi.os == 'Windows' then
        return tonumber(windows().GetCurrentProcessId())
    end
    return tonumber(loadPosix().getpid())
end

-- Windows: makes sure this process has a console and that print/io.read use it (a GUI build of the
-- runtime starts without one). Returns true when a console is available.
function Process.attachConsole()
    if ffi.os ~= 'Windows' then
        return true
    end
    local c = windows()
    if c.GetConsoleWindow() ~= nil then
        return true
    end
    if c.AllocConsole() == 0 then
        return false
    end
    c.freopen('CONOUT$', 'w', c.__acrt_iob_func(1))
    c.freopen('CONOUT$', 'w', c.__acrt_iob_func(2))
    c.freopen('CONIN$', 'r', c.__acrt_iob_func(0))
    return true
end

return Process
