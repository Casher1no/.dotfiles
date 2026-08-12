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
    -- The full command set, not just :NoNeckPain — lazy stubs only what's
    -- listed, and e.g. :NoNeckPainResize before the first toggle would
    -- otherwise be E492 (the plugin defines these in plugin/no-neck-pain.lua).
    cmd = {
        "NoNeckPain",
        "NoNeckPainResize",
        "NoNeckPainWidthUp",
        "NoNeckPainWidthDown",
        "NoNeckPainToggleLeftSide",
        "NoNeckPainToggleRightSide",
        "NoNeckPainScratchPad",
        "NoNeckPainDebug",
    },
    keys = {
        { "<leader>zz", toggle, desc = "Toggle centered view" },
    },
    -- init runs on every startup while the plugin stays unloaded; the plugin
    -- is only pulled in (through its :NoNeckPain command stub) when the
    -- marker file says centering was left enabled. Deferred to a tick after
    -- VimEnter so it centers against the final startup window layout.
    init = function()
        if was_enabled() then
            vim.api.nvim_create_autocmd("VimEnter", {
                once = true,
                callback = function()
                    vim.schedule(function()
                        vim.cmd("NoNeckPain")
                    end)
                end,
            })
        end
    end,
    opts = {
        width = 150,
    },
}
