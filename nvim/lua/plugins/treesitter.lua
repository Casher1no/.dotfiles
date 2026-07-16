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
        -- install() compiles missing ones in the background and is a no-op
        -- once they exist.
        require("nvim-treesitter").install({
            "python",
            "php",
            "vue",
            "typescript",
            "javascript",
            "c_sharp",
            "java",
            "lua",
            "html",
            "css",
            "json",
            "yaml",
            "toml",
            "bash",
            "markdown",
            "markdown_inline", -- inline code/links in markdown (AI chat, docs)
            "regex",
            "vim",
            "vimdoc",
            "gitcommit",
            "diff",
            "dockerfile",
            "sql",
        })

        -- Attach treesitter highlighting whenever a parser exists for the
        -- buffer's filetype; files without one silently keep the legacy
        -- regex highlighting.
        vim.api.nvim_create_autocmd("FileType", {
            group = vim.api.nvim_create_augroup("TreesitterHighlight", { clear = true }),
            callback = function(args)
                pcall(vim.treesitter.start, args.buf)
            end,
        })
    end,
}
