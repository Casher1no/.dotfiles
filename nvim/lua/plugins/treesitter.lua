-- Treesitter: real parse-based syntax highlighting instead of the legacy
-- regex engine. This is what colors method/function *calls* (app.add_handler,
-- logger.info, ...) like an IDE — regex highlighting only knows keywords,
-- strings and definitions. Every theme in this config understands the
-- @function.call / @function.method.call capture groups.
--
-- Uses the maintained `main` branch (requires nvim 0.12+): parsers are
-- installed with require("nvim-treesitter").install() and highlighting is
-- attached per buffer via vim.treesitter.start().
-- Windows: nvim-treesitter shells out to a bare `tree-sitter` (install.lua's
-- do_generate/do_compile) through vim.system, and libuv can only spawn a real
-- executable. npm's global install puts three shims in %APPDATA%\npm —
-- `tree-sitter` (a sh script), `.cmd` and `.ps1` — and vim.fn.exepath resolves
-- the extension-less one, so every parser build dies with ENOENT behind
-- `Error during "tree-sitter build"`. The genuine binary ships inside the
-- package; putting its directory first on PATH is enough to make the spawn
-- work, and costs nothing when a proper tree-sitter.exe is already installed.
--
-- Second Windows-only snag once the CLI does run: `tree-sitter build`
-- compiles parser.c through Rust's `cc` crate, and a windows-msvc build of
-- the CLI reaches for cl.exe, which a MinGW-only machine doesn't have
-- ("Error: program not found"). The crate takes both the compiler and its
-- flag dialect from $CC/$CXX, so naming gcc there switches it to the
-- toolchain that actually exists.
local function ensure_parser_toolchain()
    if vim.fn.has("win32") == 0 then
        return
    end

    local shim = vim.fn.exepath("tree-sitter")
    if shim ~= "" and not shim:lower():match("%.exe$") then
        local dir = vim.fs.dirname((shim:gsub("\\", "/"))) .. "/node_modules/tree-sitter-cli"
        if (vim.uv or vim.loop).fs_stat(dir .. "/tree-sitter.exe") then
            vim.env.PATH = dir:gsub("/", "\\") .. ";" .. vim.env.PATH
        end
    end

    if vim.fn.executable("cl") == 0 and vim.fn.executable("gcc") == 1 then
        vim.env.CC = vim.env.CC or "gcc"
        vim.env.CXX = vim.env.CXX or "g++"
    end
end

return {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    build = ":TSUpdate",
    lazy = false,
    config = function()
        ensure_parser_toolchain()

        -- Parsers for the stacks in this config plus everyday file types.
        -- The list lives in util/doctor/registry.lua so the Doctor panel
        -- (and `:Doctor sync` on a fresh machine) checks/installs the same
        -- set. install() compiles missing ones in the background and is a
        -- no-op once they exist.
        require("nvim-treesitter").install(require("util.doctor.registry").treesitter_parsers)

        -- Attach treesitter highlighting whenever a parser exists for the
        -- buffer's filetype; files without one silently keep the legacy
        -- regex highlighting.
        vim.api.nvim_create_autocmd("FileType", {
            group = vim.api.nvim_create_augroup("TreesitterHighlight", { clear = true }),
            callback = function(args)
                -- Parsing huge files (minified bundles, SQL dumps, giant
                -- YAML) blocks the UI on open and re-parses on every edit,
                -- and this autocmd also fires for telescope preview buffers.
                -- Such buffers keep the legacy regex highlighting instead.
                local stat = vim.uv.fs_stat(vim.api.nvim_buf_get_name(args.buf))
                if stat then
                    if stat.size > 1024 * 1024 then
                        return
                    end
                elseif vim.api.nvim_buf_line_count(args.buf) > 20000 then
                    return
                end
                pcall(vim.treesitter.start, args.buf)
            end,
        })
    end,
}
