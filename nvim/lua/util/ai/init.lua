-- Local-LLM AI suite, backed by LM Studio's OpenAI-compatible server:
--   completion.lua — automatic ghost-text autocomplete, Tab accepts
--   inline.lua     — <leader>cp visual-selection edit assistant
--   chat.lua       — side-panel chat
--   config.lua     — persisted settings, client.lua — curl transport
-- Configured from the palette's AI section (util/palette.lua). Everything
-- no-ops silently when the server or a model is unavailable.
local M = {}

local function set_highlights()
    -- default=true keeps theme overrides possible; reapplied on ColorScheme
    -- because the palette's live theme preview wipes highlights per switch.
    vim.api.nvim_set_hl(0, "AiGhost", { link = "Comment", default = true })
    vim.api.nvim_set_hl(0, "AiProgress", { link = "DiagnosticVirtualTextInfo", default = true })
    vim.api.nvim_set_hl(0, "AiReviewOld", { link = "DiffDelete", default = true })
    vim.api.nvim_set_hl(0, "AiReviewNew", { link = "DiffAdd", default = true })
    vim.api.nvim_set_hl(0, "AiHint", { link = "NonText", default = true })
end

function M.setup()
    set_highlights()
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("AiHighlights", { clear = true }),
        callback = set_highlights,
    })
    require("util.ai.completion").setup()
end

return M
