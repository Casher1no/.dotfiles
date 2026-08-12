-- Treesitter: real parse-based syntax highlighting instead of the legacy
-- regex engine. This is what colors method/function *calls* (app.add_handler,
-- logger.info, ...) like an IDE — regex highlighting only knows keywords,
-- strings and definitions. Every theme in this config understands the
-- @function.call / @function.method.call capture groups.
--
-- Uses the maintained `main` branch (requires nvim 0.12+): parsers are
-- installed with require("nvim-treesitter").install() and highlighting is
-- attached per buffer via vim.treesitter.start().
return {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    build = ":TSUpdate",
    lazy = false,
    config = function()
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
