-- https://github.com/eclipse-jdtls/eclipse.jdt.ls (Java language server)
--
-- The `jdtls` launcher installed by Mason sets up a sensible default workspace
-- data directory and bootstraps the server, so a plain config is enough for
-- general project work. For advanced features (debugging, test runners) the
-- dedicated nvim-jdtls plugin can be added later.
-- Lombok support: jdtls must load lombok as a Java agent, otherwise all
-- Lombok-generated code (getters/setters, @Slf4j `log`, @Builder, etc.) is
-- invisible and shows up as "unused"/"cannot resolve" errors. Mason bundles a
-- lombok.jar with the jdtls package, so we point the agent at that.
-- Use stdpath rather than $MASON: the env var is only set once mason.nvim has
-- finished setup, which may be after this config is evaluated, leaving the path
-- broken (jdtls then fails to start with "Error opening zip file").
local lombok_jar = vim.fn.stdpath("data") .. "/mason/packages/jdtls/lombok.jar"

-- The Mason jdtls launcher derives its workspace dir from sha1(basename(cwd)),
-- so two projects sharing a folder name collide and corrupt each other's
-- workspace (the classic phantom "cannot be resolved to a type"). Pin a unique
-- workspace per *full project path* instead.
local function workspace_for(root)
    root = root or vim.fn.getcwd()
    local hash = vim.fn.sha256(root):sub(1, 16)
    return vim.fn.expand("~/Library/Caches/jdtls/ws-") .. vim.fn.fnamemodify(root, ":t") .. "-" .. hash
end

-- The workspace of the running jdtls client (so :JdtlsWipe matches the real
-- project root jdtls picked), falling back to cwd when none is attached.
local function active_workspace()
    for _, client in ipairs(vim.lsp.get_clients({ name = "jdtls" })) do
        if client.config.root_dir then
            return workspace_for(client.config.root_dir)
        end
    end
    return workspace_for()
end

-- :JdtlsWipe — delete the current project's workspace and restart jdtls.
vim.api.nvim_create_user_command("JdtlsWipe", function()
    local dir = active_workspace()
    vim.fn.delete(dir, "rf")
    vim.notify("Wiped jdtls workspace: " .. dir .. "\nRestarting…", vim.log.levels.INFO)
    vim.cmd("LspRestart jdtls")
end, { desc = "Clear this project's jdtls workspace and restart" })

---@type vim.lsp.Config
return {
    -- cmd is a function so the workspace is computed from the project root at
    -- launch time (per project), not once when this module loads.
    cmd = function(dispatchers, config)
        return vim.lsp.rpc.start({
            "jdtls",
            "-data",
            workspace_for(config.root_dir),
            "--jvm-arg=-javaagent:" .. lombok_jar,
        }, dispatchers)
    end,
    filetypes = { "java" },
    root_markers = {
        "settings.gradle",
        "settings.gradle.kts",
        "pom.xml",
        "build.gradle",
        "build.gradle.kts",
        "mvnw",
        "gradlew",
        ".git",
    },
}
