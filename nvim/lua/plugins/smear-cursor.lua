-- Animated "smear" trail as the cursor moves/jumps. Using the README's
-- "faster smear" preset (snappier than the defaults).
return {
    "sphamba/smear-cursor.nvim",
    event = "VeryLazy",
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
        -- terminal, so drop back to 17 if it stutters instead of smoothing.
        time_interval = 8,
        -- Telescope's prompt redraws on every keystroke; animating a smear
        -- on top of that forces extra redraws and makes typing feel laggy.
        filetypes_disabled = { "TelescopePrompt" },
    },
}
