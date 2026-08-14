-- Animated "smear" trail as the cursor moves/jumps. Using the README's
-- "faster smear" preset (snappier than the defaults).

-- Windows Terminal draws the real cursor wherever the output stream last left
-- it, so a repaint that starts at the top of the screen shows the cursor up
-- there for a frame before it lands back on the true position — the "cursor
-- jumps down from the top" flicker. It only shows up under a redraw storm,
-- and this plugin is the loudest source of those: it repaints the whole
-- screen every animation frame (hence the notes in util/telescope_tints.lua
-- and util/tree_tints.lua about on_win running at animation framerate).
-- macOS terminals composite a frame at a time and never show it, so the
-- volume is turned down on Windows only.
local is_win = vim.fn.has("win32") == 1

return {
    "sphamba/smear-cursor.nvim",
    event = "VeryLazy",
    -- Escalation if the flicker survives the settings below: `not is_win`
    -- turns the plugin off on Windows and keeps it on macOS.
    enabled = true,
    opts = {
        stiffness = 0.8,
        trailing_stiffness = 0.6,
        stiffness_insert_mode = 0.7,
        trailing_stiffness_insert_mode = 0.7,
        damping = 0.95,
        damping_insert_mode = 0.95,
        distance_stop_animating = 0.5,
        -- Animation frame period in ms — the plugin's only real "framerate".
        -- Default 17 (~60fps); 8 is ~120fps. The animation measures elapsed
        -- time and scales stiffness/damping to match, so the smear moves at
        -- the same speed either way — it's just drawn in twice as many steps.
        -- Twice the frames means twice the redraws pushed through the
        -- terminal, so Windows stays on the 60fps default.
        time_interval = is_win and 17 or 8,
        -- Typing is when the flicker is most obvious: every keystroke starts
        -- a fresh animation, so the repaints never stop while you write a
        -- line. Normal-mode motion smears still work on Windows.
        smear_insert_mode = not is_win,
        -- Window/buffer switches are the smears that physically cross the
        -- screen — jumping out of neo-tree or the cmdline animates from the
        -- top corner downward, which reads as the same top-of-screen glitch
        -- even when the terminal renders it perfectly.
        smear_between_buffers = not is_win,
        -- Telescope's prompt redraws on every keystroke; animating a smear
        -- on top of that forces extra redraws and makes typing feel laggy.
        filetypes_disabled = { "TelescopePrompt" },
    },
}
