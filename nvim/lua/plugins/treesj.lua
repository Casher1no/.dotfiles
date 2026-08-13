-- Split/join code constructs (argument lists, tables, objects, arrays)
-- between one line and multiline. Deliberately no keymaps of its own: it
-- surfaces as context-aware entries in the code-action menu instead
-- (util/actions.lua, JetBrains-intentions style) — Split when the node is
-- on one line, Join when it is already spread out.
return {
    "Wansmer/treesj",
    lazy = true, -- pulled in by require("treesj…") from util/actions.lua
    opts = { use_default_keymaps = false },
}
