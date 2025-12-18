return {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },

    config = function()
        local function lsp_name()
            local buf_ft = vim.bo.filetype
            for _, client in ipairs(vim.lsp.get_active_clients({ bufnr = 0 })) do
                if client.config.filetypes and vim.tbl_contains(client.config.filetypes, buf_ft) then
                    return client.name
                end
            end
            return "No LSP"
        end

        local function formatter()
            local ok, null_ls = pcall(require, "null-ls")
            if not ok then return "" end

            local ft = vim.bo.filetype
            local sources = require("null-ls.sources").get_available(ft, "NULL_LS_FORMATTING")

            if #sources > 0 then
                return sources[1].name
            end

            return "No Formatter"
        end

        require("lualine").setup({
            options = {
                theme = "catppuccin",
            },
            sections = {
                lualine_x = {
                    "filetype",
                    lsp_name,
                    formatter
                },
            }
        })
    end,
}
