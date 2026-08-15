-- clangd (LLVM) — completion, diagnostics, navigation and clang-format
-- formatting for C/C++. Installed as a system package, not through mason
-- (choco `llvm` / brew `llvm` / apt `clangd`; see util/doctor/registry.lua),
-- because it has to match the toolchain that actually compiles the code.
--
-- The MSVC-vs-MinGW driver override lives in clangd's user config — see
-- util/clangd_config.lua for why, and what breaks without it.
local clangd_config = require("util.clangd_config")
clangd_config.ensure()

-- --query-driver is an allowlist, not a hint: clangd interrogates a compiler
-- for its system include paths only when the binary matches one of these
-- globs, and silently keeps its built-in toolchain otherwise. Globbing the
-- directory of each compiler found on PATH covers the versioned and
-- target-prefixed names next to it (x86_64-w64-mingw32-g++, g++-14, …).
local function query_driver_globs()
    local globs, seen = {}, {}
    for _, exe in ipairs({ "g++", "gcc", "clang++", "clang", "c++", "cc" }) do
        local path = vim.fn.exepath(exe)
        if path ~= "" then
            local dir = vim.fs.dirname((path:gsub("\\", "/")))
            if not seen[dir] then
                seen[dir] = true
                globs[#globs + 1] = dir .. "/*"
            end
        end
    end
    return globs
end

local cmd = {
    "clangd",
    "--background-index",
    "--clang-tidy",
    -- Solving a LeetCode problem means one file that already includes
    -- <bits/stdc++.h>; auto-inserting headers on completion only adds noise.
    "--header-insertion=never",
    "--completion-style=detailed",
    "--function-arg-placeholders",
    "--pch-storage=memory",
}

local globs = query_driver_globs()
if #globs > 0 then
    cmd[#cmd + 1] = "--query-driver=" .. table.concat(globs, ",")
end

---@type vim.lsp.Config
return {
    cmd = cmd,
    filetypes = { "c", "cpp", "objc", "objcpp", "cuda" },
    -- Ordered narrowest-first, so a solutions folder with its own .clangd or
    -- Makefile roots there instead of at the enclosing git repo.
    root_markers = {
        ".clangd",
        "compile_commands.json",
        "compile_flags.txt",
        "CMakeLists.txt",
        "Makefile",
        ".git",
    },
    -- clangd offers utf-8 first; nvim warns about the mismatch with its own
    -- default unless the client asks for utf-16 explicitly.
    capabilities = {
        offsetEncoding = { "utf-16" },
    },
}
