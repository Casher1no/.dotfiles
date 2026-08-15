-- clangd's Windows build ships targeting x86_64-pc-windows-msvc, so with no
-- configuration it hunts for Visual Studio's headers and can't resolve even
-- <iostream> on a machine whose compiler is MinGW ("'bits/stdc++.h' file not
-- found", and everything downstream of it red). The whole fix is one driver
-- override: with `Compiler: g++` clangd re-runs the driver query against
-- whatever g++ is on PATH and adopts its real target triple
-- (x86_64-w64-windows-gnu) and its include paths.
--
-- Two reasons this lives in clangd's *user* config rather than a project
-- `.clangd`: a scratch directory of LeetCode solutions has no project root
-- and no compile_commands.json, so there is nowhere project-scoped to put it;
-- and the override is machine-shaped ("this box compiles with g++"), not
-- project-shaped. A project that ships its own .clangd is read after this one
-- and still wins.
--
-- The file is only ever created, never rewritten — an existing config is
-- somebody's deliberate choice.

local uv = vim.uv or vim.loop

local M = {}

-- Pinning the standard here (rather than only in the build command) is what
-- makes C++23 features resolve while editing a loose .cpp with no build
-- system. The cost: in a project that *does* have a compile_commands.json,
-- this is appended to the real flags and overrides the standard it specifies.
M.content = table.concat({
    "# Written by nvim (lua/util/clangd_config.lua) — safe to edit or delete.",
    "# `Compiler: g++` makes clangd use the GCC/MinGW toolchain on PATH",
    "# instead of its built-in MSVC default.",
    "CompileFlags:",
    "  Compiler: g++",
    "  Add: [-std=c++23]",
    "",
}, "\n")

-- Where clangd looks for its user config (clangd docs, "Configuration"):
-- %LocalAppData% on Windows, Preferences on macOS, XDG elsewhere.
function M.path()
    local sysname = uv.os_uname().sysname
    if sysname:find("Windows") then
        local base = os.getenv("LOCALAPPDATA") or vim.fn.expand("~/AppData/Local")
        return base:gsub("\\", "/") .. "/clangd/config.yaml"
    end
    if sysname == "Darwin" then
        return vim.fn.expand("~/Library/Preferences/clangd/config.yaml")
    end
    local base = os.getenv("XDG_CONFIG_HOME") or vim.fn.expand("~/.config")
    return base .. "/clangd/config.yaml"
end

-- Returns true when it wrote the file, false when one already existed (or
-- when writing failed — clangd still starts, it just falls back to MSVC).
function M.ensure()
    local path = M.path()
    if uv.fs_stat(path) then
        return false
    end
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    local file = io.open(path, "w")
    if not file then
        return false
    end
    file:write(M.content)
    file:close()
    return true
end

-- Doctor probe (util/doctor/registry.lua): "ok" | "warn" + detail.
function M.status()
    local path = M.path()
    local file = io.open(path, "r")
    if not file then
        return "warn", "not written yet — created when a C/C++ file is opened"
    end
    local body = file:read("*a")
    file:close()
    if body:find("Compiler:") then
        return "ok", vim.fn.fnamemodify(path, ":~")
    end
    return "warn", "exists but sets no Compiler — clangd may still target MSVC"
end

return M
