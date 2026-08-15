-- Compile-and-run for a single translation unit — the LeetCode / scratch-file
-- workflow, where there's no build system and the saved project tasks behind
-- <leader>r (util/tasks.lua) would mean one entry per throwaway folder.
--
-- The compile runs through vim.system rather than a `g++ … && ./a.out` shell
-- one-liner on purpose: `&&` is a parse error in Windows PowerShell 5.1, and
-- 'shell' differs per machine. Failures land in the quickfix list; the binary
-- is only launched when the compile actually succeeded.

local M = {}

-- Shared with the debug configuration in plugins/dap.lua, which recompiles
-- with `debug = true` so breakpoints land on the lines you set them on.
M.standard = "-std=c++23"

local function compiler()
    for _, exe in ipairs({ "g++", "clang++" }) do
        if vim.fn.executable(exe) == 1 then
            return exe
        end
    end
    return nil
end

-- The binary sits next to its source, so a folder of solutions stays flat and
-- `two_sum.cpp` is obviously paired with `two_sum.exe`.
function M.binary(src)
    return vim.fn.fnamemodify(src, ":r") .. (vim.fn.has("win32") == 1 and ".exe" or "")
end

-- Returns cc, argv, exe — or nil when there's no compiler to run.
local function compile_command(src, opts)
    local cc = compiler()
    if not cc then
        vim.notify("No C++ compiler on PATH (looked for g++, clang++)", vim.log.levels.ERROR)
        return nil
    end

    local exe = M.binary(src)
    local args = { cc, M.standard, "-Wall", "-Wextra", "-g" }
    -- -O0 for debugging so the stepping order matches the source; -O2
    -- otherwise, which also turns on the warnings that need dataflow.
    args[#args + 1] = opts.debug and "-O0" or "-O2"
    vim.list_extend(args, { src, "-o", exe })
    return cc, args, exe
end

-- gcc/clang diagnostics match nvim's stock 'errorformat', so :cnext walks the
-- errors and <CR> jumps to them.
local function report_failure(cc, src, stderr)
    local name = vim.fn.fnamemodify(src, ":t")
    local lines = vim.split(stderr or "", "\n", { trimempty = true })
    vim.fn.setqflist({}, " ", { title = cc .. " " .. name, lines = lines, efm = vim.o.errorformat })
    vim.cmd("copen")
    vim.notify("Compile failed — see quickfix", vim.log.levels.ERROR)
end

-- Compiles `src` and calls on_success(exe_path). Returns nothing; everything
-- after the compile happens on the vim.system callback.
function M.build(src, opts, on_success)
    opts = opts or {}
    local cc, args, exe = compile_command(src, opts)
    if not cc then
        return
    end

    vim.notify("Compiling " .. vim.fn.fnamemodify(src, ":t") .. "…", vim.log.levels.INFO)

    vim.system(args, { text = true, cwd = vim.fn.fnamemodify(src, ":h") }, function(result)
        vim.schedule(function()
            if result.code ~= 0 then
                report_failure(cc, src, result.stderr)
                return
            end
            on_success(exe)
        end)
    end)
end

-- Blocking variant for nvim-dap, whose `program` field is resolved inline
-- while the session starts and has nowhere to put a callback. Returns the
-- executable path, or nil when the compile failed.
function M.build_sync(src, opts)
    local cc, args, exe = compile_command(src, opts or {})
    if not cc then
        return nil
    end

    local result = vim.system(args, { text = true, cwd = vim.fn.fnamemodify(src, ":h") }):wait()
    if result.code ~= 0 then
        report_failure(cc, src, result.stderr)
        return nil
    end
    return exe
end

-- Build the current buffer, then run it in a terminal so stdin/stdout behave
-- like a real console (LeetCode drivers usually read input).
function M.run()
    local src = vim.api.nvim_buf_get_name(0)
    if src == "" then
        vim.notify("Buffer has no file name — save it first", vim.log.levels.WARN)
        return
    end
    if vim.bo.modified then
        vim.cmd("silent write")
    end

    M.build(src, {}, function(exe)
        -- Table form, not a string: paths under "Program Files" or a folder
        -- with a space would otherwise be split by the shell.
        -- auto_close=false so the output survives the program exiting — see
        -- util/tasks.lua. Enter (or q / Esc) closes the finished terminal.
        require("snacks").terminal({ exe }, {
            cwd = vim.fn.fnamemodify(src, ":h"),
            auto_close = false,
        })
    end)
end

return M
