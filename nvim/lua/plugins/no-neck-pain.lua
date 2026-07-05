-- Centers the current buffer in a fixed-width column by padding empty side
-- windows, useful on wide monitors. Toggle with <leader>zz. The on/off state
-- persists across restarts via state_file below.
--
-- We track state ourselves (rather than the plugin's postEnable/postDisable
-- callbacks) because those also fire during the plugin's own internal
-- enable/disable cycling (e.g. its teardown on quit), which would delete the
-- marker file right before it could be read on the next startup.
local state_file = vim.fn.stdpath("state") .. "/no-neck-pain-enabled"

local function was_enabled()
    return vim.fn.filereadable(state_file) == 1
end

local function toggle()
    vim.cmd("NoNeckPain")
    if was_enabled() then
        vim.fn.delete(state_file)
    else
        vim.fn.writefile({}, state_file)
    end
end

return {
    "shortcuts/no-neck-pain.nvim",
    cmd = "NoNeckPain",
    -- Load at startup (not just on-demand) so a previously-enabled state can
    -- be restored automatically.
    event = "VimEnter",
    keys = {
        { "<leader>zz", toggle, desc = "Toggle centered view" },
    },
    opts = {
        width = 150,
    },
    config = function(_, opts)
        require("no-neck-pain").setup(opts)
        if was_enabled() then
            vim.schedule(function()
                vim.cmd("NoNeckPain")
            end)
        end
    end,
}
