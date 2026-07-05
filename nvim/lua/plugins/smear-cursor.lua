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
    },
}
