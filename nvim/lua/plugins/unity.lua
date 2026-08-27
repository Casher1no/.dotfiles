-- apyra/nvim-unity-sync, used as a library rather than as a plugin.
--
-- All this spec does is put the repo on the runtimepath and register the
-- bridge's autocmds and commands at startup. There is no `config` and no
-- `opts`, which means lazy.nvim never calls require("unity.plugin").setup() --
-- that module registers a VimLeave autocmd running
-- os.execute("pkill -f unity2025") unconditionally on every OS, wires its file
-- events to nvim-tree (this config uses neo-tree), and guards its LSP autocmds
-- with `pattern = ".cs"`, which matches no file. See util/unity_sync.lua for
-- the full list and for what replaces it.
--
-- The plugin therefore loads lazily on the first require("unity.handler"),
-- which only happens inside a Unity project that has an Assembly-CSharp.csproj.
--
-- The companion Unity Editor package (apyra/nvim-unity) is deliberately NOT
-- used: it replaces Unity's own csproj generation with a template that
-- hardcodes the DefineConstants of Unity 6000.0.23, so every UNITY_* #if would
-- resolve against the wrong version. Unity's own generated project stays
-- authoritative here; this only keeps its <Compile> list current between
-- regenerations.
return {
    "apyra/nvim-unity-sync",
    lazy = true,
    init = function()
        require("util.unity_sync").setup()
    end,
}
