-- Java LSP + debugging via nvim-jdtls (https://github.com/mfussenegger/nvim-jdtls).
-- Starts the Eclipse JDT language server per project, loads lombok as a Java
-- agent, and wires up the java-debug-adapter / vscode-java-test bundles so
-- nvim-dap can launch and debug Java (main classes and tests).
return {
    "mfussenegger/nvim-jdtls",
    ft = "java",
    dependencies = { "mfussenegger/nvim-dap" },
    config = function()
        local mason = vim.fn.stdpath("data") .. "/mason/packages/"
        local lombok_jar = mason .. "jdtls/lombok.jar"

        -- Unique workspace per *full project path* (see the long-standing folder-
        -- name collision gotcha with the default jdtls launcher).
        local function workspace_for(root)
            root = root or vim.fn.getcwd()
            local hash = vim.fn.sha256(root):sub(1, 16)
            return vim.fn.expand("~/Library/Caches/jdtls/ws-")
                .. vim.fn.fnamemodify(root, ":t")
                .. "-"
                .. hash
        end

        -- Debug + test adapter jars to hand to jdtls as bundles.
        local function bundles()
            local b = vim.split(
                vim.fn.glob(mason .. "java-debug-adapter/extension/server/com.microsoft.java.debug.plugin-*.jar", true),
                "\n"
            )
            vim.list_extend(b, vim.split(vim.fn.glob(mason .. "java-test/extension/server/*.jar", true), "\n"))
            return vim.tbl_filter(function(j)
                return j ~= ""
            end, b)
        end

        local root_markers = {
            "settings.gradle",
            "settings.gradle.kts",
            "pom.xml",
            "build.gradle",
            "build.gradle.kts",
            "mvnw",
            "gradlew",
            ".git",
        }

        local function start()
            local root = vim.fs.root(0, root_markers) or vim.fn.getcwd()
            require("jdtls").start_or_attach({
                cmd = {
                    "jdtls",
                    "-data",
                    workspace_for(root),
                    "--jvm-arg=-javaagent:" .. lombok_jar,
                },
                root_dir = root,
                init_options = { bundles = bundles() },
                on_attach = function()
                    -- Register the `java` dap adapter and auto-build launch
                    -- configs for the project's main classes.
                    require("jdtls").setup_dap({ hotcodereplace = "auto" })
                    require("jdtls.dap").setup_dap_main_class_configs()
                end,
            })
        end

        -- Start for every Java buffer (the one that triggered lazy-load too).
        vim.api.nvim_create_autocmd("FileType", {
            pattern = "java",
            callback = start,
        })
        start()

        -- :JdtlsWipe — clear this project's workspace and restart jdtls.
        vim.api.nvim_create_user_command("JdtlsWipe", function()
            local dir = workspace_for(vim.fs.root(0, root_markers))
            vim.fn.delete(dir, "rf")
            vim.notify("Wiped jdtls workspace: " .. dir .. "\nRestarting…", vim.log.levels.INFO)
            vim.cmd("lsp restart jdtls")
        end, { desc = "Clear this project's jdtls workspace and restart" })
    end,
}
