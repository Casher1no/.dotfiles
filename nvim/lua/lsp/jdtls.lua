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

---@type vim.lsp.Config
return {
    cmd = {
        "jdtls",
        "--jvm-arg=-javaagent:" .. lombok_jar,
    },
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
