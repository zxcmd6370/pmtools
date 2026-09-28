-- Hidden process spawning for the Ignitools backend.
--
-- WHY: the unlock engine launches background PowerShell workers (download,
-- probe, auto-apply). The legacy path is utils.exec(), which is _popen() —
-- it wraps the command in `cmd.exe /c`, and since the luavm (a GUI-subsystem
-- process with no console) is the parent, Windows gives that cmd.exe a brand
-- new *visible* console window. `-WindowStyle Hidden` only hides PowerShell
-- after it has started, so the user still sees a terminal flash for every
-- background launch.
--
-- FIX: when the host VM is LuaJIT (Millennium's luavm is), call
-- CreateProcessW directly with CREATE_NO_WINDOW — the child gets no console
-- at all, and since we close the process/thread handles immediately the
-- child is fully detached (no blocking, no inherited pipe).
--
-- If ffi is unavailable (e.g. the plain-Lua test harness) this falls back to
-- the old utils.exec() path so behaviour never silently disappears.

local m_util = require("utils")
local logger = require("plugin_logger")

local spawn = {}

-- Loaded lazily on first use so a missing ffi never breaks module load.
local ffi, C, bit = nil, nil, nil

local function init_ffi()
    if C then return true end
    local ok_ffi, lib = pcall(require, "ffi")
    if not ok_ffi then return false end
    local ok_bit, b = pcall(require, "bit")
    if not ok_bit then return false end
    local ok_cdef = pcall(function()
        lib.cdef[[
            typedef unsigned long DWORD;
            typedef int BOOL;
            typedef unsigned short WORD;
            typedef void* HANDLE;
            typedef void* LPVOID;
            typedef struct _SECURITY_ATTRIBUTES {
                DWORD nLength;
                LPVOID lpSecurityDescriptor;
                BOOL bInheritHandle;
            } SECURITY_ATTRIBUTES;
            typedef struct _STARTUPINFOW {
                DWORD cb;
                LPVOID lpReserved;
                LPVOID lpDesktop;
                LPVOID lpTitle;
                DWORD dwX;
                DWORD dwY;
                DWORD dwXSize;
                DWORD dwYSize;
                DWORD dwXCountChars;
                DWORD dwYCountChars;
                DWORD dwFillAttribute;
                DWORD dwFlags;
                WORD wShowWindow;
                WORD cbReserved2;
                LPVOID lpReserved2;
                HANDLE hStdInput;
                HANDLE hStdOutput;
                HANDLE hStdError;
            } STARTUPINFOW;
            typedef struct _PROCESS_INFORMATION {
                HANDLE hProcess;
                HANDLE hThread;
                DWORD dwProcessId;
                DWORD dwThreadId;
            } PROCESS_INFORMATION;
            BOOL __stdcall CreateProcessW(LPVOID lpApplicationName, LPVOID lpCommandLine, SECURITY_ATTRIBUTES* lpProcessAttributes, SECURITY_ATTRIBUTES* lpThreadAttributes, BOOL bInheritHandles, DWORD dwCreationFlags, LPVOID lpEnvironment, LPVOID lpCurrentDirectory, STARTUPINFOW* lpStartupInfo, PROCESS_INFORMATION* lpProcessInformation);
            BOOL __stdcall CloseHandle(HANDLE hObject);
            DWORD __stdcall GetLastError(void);
        ]]
    end)
    if not ok_cdef then return false end
    ffi, C, bit = lib, lib.C, b
    return true
end

-- UTF-8 string -> mutable UTF-16LE buffer (CreateProcessW wants a writable
-- command line, so we build a uint16_t array instead of a Lua string).
local function utf8_to_utf16(s)
    local out = {}
    local i, n = 1, #s
    while i <= n do
        local b0 = string.byte(s, i)
        local c
        if b0 < 0x80 then
            c = b0
            i = i + 1
        elseif b0 < 0xE0 then
            c = bit.bor(bit.lshift(bit.band(b0, 0x1F), 6), bit.band(string.byte(s, i + 1), 0x3F))
            i = i + 2
        elseif b0 < 0xF0 then
            c = bit.bor(
                bit.bor(bit.lshift(bit.band(b0, 0x0F), 12), bit.lshift(bit.band(string.byte(s, i + 1), 0x3F), 6)),
                bit.band(string.byte(s, i + 2), 0x3F))
            i = i + 3
        else
            c = bit.bor(
                bit.bor(bit.bor(bit.lshift(bit.band(b0, 0x07), 18), bit.lshift(bit.band(string.byte(s, i + 1), 0x3F), 12)),
                    bit.lshift(bit.band(string.byte(s, i + 2), 0x3F), 6)),
                bit.band(string.byte(s, i + 3), 0x3F))
            i = i + 4
        end
        if c >= 0x10000 then
            local v = c - 0x10000
            out[#out + 1] = bit.bor(0xD800, bit.rshift(v, 10))
            out[#out + 1] = bit.bor(0xDC00, bit.band(v, 0x3FF))
        else
            out[#out + 1] = c
        end
    end
    local buf = ffi.new("uint16_t[?]", #out + 1)
    for j, v in ipairs(out) do buf[j - 1] = v end
    buf[#out] = 0
    return buf
end

-- True when the ffi fast path is live (CreateProcessW CREATE_NO_WINDOW).
function spawn.ffi_available()
    return init_ffi()
end

-- One-time boot diagnostic: tells the log whether background launches are
-- fully invisible (ffi) or going through the console-flashing fallback.
if init_ffi() then
    logger.log("Pmtools: hidden spawn active (CreateProcessW CREATE_NO_WINDOW)")
else
    logger.log("Pmtools: hidden spawn unavailable — background launches fall back to utils.exec")
end

-- Launch `cmdline` fully detached and completely invisible. Returns true on
-- success (or when the legacy fallback was used), false if even the fallback
-- threw. Never blocks: the child runs without a console and without any pipe
-- the caller would have to wait on.
function spawn.exec(cmdline)
    if not init_ffi() then
        return pcall(m_util.exec, cmdline)
    end
    local ok = pcall(function()
        local si = ffi.new("STARTUPINFOW")
        si.cb = ffi.sizeof("STARTUPINFOW")
        si.dwFlags = 0x1 -- STARTF_USESHOWWINDOW
        si.wShowWindow = 0 -- SW_HIDE (belt and braces; CREATE_NO_WINDOW already prevents a console)
        local pi = ffi.new("PROCESS_INFORMATION")
        local cmdw = utf8_to_utf16(cmdline)
        local res = C.CreateProcessW(
            nil, cmdw, nil, nil, 0,
            0x08000000 + 0x00000200, -- CREATE_NO_WINDOW | CREATE_NEW_PROCESS_GROUP
            nil, nil, si, pi)
        if res == 0 then
            error("CreateProcessW failed with error " .. C.GetLastError())
        end
        C.CloseHandle(pi.hProcess)
        C.CloseHandle(pi.hThread)
    end)
    if not ok then
        logger.log("Pmtools: hidden spawn failed, falling back to utils.exec")
        return pcall(m_util.exec, cmdline)
    end
    return true
end

-- Like spawn.exec but the child process breaks out of the caller's job
-- object via CREATE_BREAKAWAY_FROM_JOB. This lets the child survive even
-- when the parent (Steam/Millennium) is killed -- used for self-update.
function spawn.exec_breakaway(cmdline)
    if not init_ffi() then
        return os.execute(cmdline)
    end
    local ok = pcall(function()
        local si = ffi.new("STARTUPINFOW")
        si.cb = ffi.sizeof("STARTUPINFOW")
        local pi = ffi.new("PROCESS_INFORMATION")
        local cmdw = utf8_to_utf16(cmdline)
        -- CREATE_BREAKAWAY_FROM_JOB (0x01000000) lets the child survive
        -- the parent's job object. CREATE_NO_WINDOW (0x08000000) prevents
        -- a console flash; the .cmd launcher uses START for the visible window.
        local flags = 0x01000000 + 0x08000000
        local res = C.CreateProcessW(
            nil, cmdw, nil, nil, 0, flags,
            nil, nil, si, pi)
        if res == 0 then
            local err = C.GetLastError()
            logger.log("Pmtools: breakaway CreateProcessW failed, err=" .. tostring(err))
            error("CreateProcessW failed with error " .. err)
        end
        C.CloseHandle(pi.hProcess)
        C.CloseHandle(pi.hThread)
    end)
    if not ok then
        logger.log("Pmtools: breakaway spawn failed, falling back to os.execute")
        return os.execute(cmdline)
    end
    return true
end

return spawn
