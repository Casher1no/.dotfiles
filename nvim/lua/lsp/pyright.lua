-- https://github.com/microsoft/pyright
local function set_python_path(command)
    local path = command.args
    local clients = vim.lsp.get_clients({
        bufnr = vim.api.nvim_get_current_buf(),
        name = "pyright",
    })
    for _, client in ipairs(clients) do
        if client.settings then
            client.settings.python =
                vim.tbl_deep_extend("force", client.settings.python --[[@as table]], { pythonPath = path })
        else
            client.config.settings =
                vim.tbl_deep_extend("force", client.config.settings, { python = { pythonPath = path } })
        end
        client:notify("workspace/didChangeConfiguration", { settings = nil })
    end
end

---@type vim.lsp.Config
return {
    cmd = { "pyright-langserver", "--stdio" },
    filetypes = { "python" },
    -- Analyze with the project's virtualenv, not the system python:
    -- $VIRTUAL_ENV when nvim was started inside one, else <root>/.venv
    -- (the pip/uv/poetry default). Without this, imports installed in the
    -- venv show as "could not be resolved".
    before_init = function(_, config)
        local python
        if vim.env.VIRTUAL_ENV then
            python = vim.env.VIRTUAL_ENV .. "/bin/python"
        else
            local candidate = (config.root_dir or vim.fn.getcwd()) .. "/.venv/bin/python"
            if vim.uv.fs_stat(candidate) then
                python = candidate
            end
        end
        if python then
            -- Mutate in place: the client already references this settings
            -- table, so replacing it (tbl_deep_extend) would be invisible.
            config.settings = config.settings or {}
            config.settings.python = config.settings.python or {}
            config.settings.python.pythonPath = python
        end
    end,
    root_markers = {
        "pyrightconfig.json",
        "pyproject.toml",
        "setup.py",
        "setup.cfg",
        "requirements.txt",
        "Pipfile",
        ".git",
    },
    settings = {
        python = {
            analysis = {
                autoSearchPaths = true,
                useLibraryCodeForTypes = true,
                diagnosticMode = "openFilesOnly",
                -- PyCharm-level strictness: keep real problems (undefined
                -- names, broken imports, bad calls) but drop pyright's
                -- strict-Optional checks ('"reply_text" is not a known
                -- attribute of "None"') that PyCharm doesn't flag either.
                -- Delete an override (or set typeCheckingMode = "strict")
                -- to get the pedantry back.
                typeCheckingMode = "basic",
                diagnosticSeverityOverrides = {
                    reportOptionalMemberAccess = "none",
                    reportOptionalCall = "none",
                    reportOptionalSubscript = "none",
                    reportOptionalOperand = "none",
                    reportOptionalIterable = "none",
                    reportArgumentType = "none",
                },
            },
        },
    },
    on_attach = function(client, bufnr)
        vim.api.nvim_buf_create_user_command(bufnr, "LspPyrightOrganizeImports", function()
            client.request("workspace/executeCommand", {
                command = "pyright.organizeimports",
                arguments = { vim.uri_from_bufnr(bufnr) },
            }, nil, bufnr)
        end, { desc = "Organize Imports" })

        vim.api.nvim_buf_create_user_command(bufnr, "LspPyrightSetPythonPath", set_python_path, {
            desc = "Reconfigure pyright with the provided python path",
            nargs = 1,
            complete = "file",
        })
    end,
}
