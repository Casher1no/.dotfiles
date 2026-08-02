-- https://github.com/angular/vscode-ng-language-service
-- Angular requires a node_modules directory to probe for @angular/language-service
-- and typescript so it uses the project's configured versions.
local fs, fn, uv = vim.fs, vim.fn, vim.uv

local function collect_node_modules(root_dir)
    local results = {}

    local project_node = fs.joinpath(root_dir, "node_modules")
    if uv.fs_stat(project_node) then
        table.insert(results, project_node)
    end

    -- Mason's bin/ entry is a .cmd shim on Windows, so walking up from
    -- exepath() lands outside the package. Address the package directly.
    local mason_node = fs.normalize(
        fs.joinpath(fn.stdpath("data"), "mason/packages/angular-language-server/node_modules")
    )
    if uv.fs_stat(mason_node) then
        table.insert(results, mason_node)
    end

    return results
end

local function get_angular_core_version(root_dir)
    local package_json = fs.joinpath(root_dir, "package.json")
    if not uv.fs_stat(package_json) then
        return ""
    end

    local ok, content = pcall(fn.readblob, package_json)
    if not ok or not content then
        return ""
    end

    local json = vim.json.decode(content) or {}
    local version = (json.dependencies or {})["@angular/core"] or ""
    return version:match("%d+%.%d+%.%d+") or ""
end

---@type vim.lsp.Config
return {
    cmd = function(dispatchers, config)
        local root_dir = (config and config.root_dir) or fn.getcwd()
        local node_paths = collect_node_modules(root_dir)

        local ts_probe = table.concat(node_paths, ",")
        local ng_probe = table.concat(
            vim.iter(node_paths)
                :map(function(p)
                    return fs.joinpath(p, "@angular/language-server/node_modules")
                end)
                :totable(),
            ","
        )
        local cmd = {
            "ngserver",
            "--stdio",
            "--tsProbeLocations",
            ts_probe,
            "--ngProbeLocations",
            ng_probe,
            "--angularCoreVersion",
            get_angular_core_version(root_dir),
        }
        return vim.lsp.rpc.start(cmd, dispatchers)
    end,
    filetypes = { "typescript", "html", "typescriptreact", "typescript.tsx", "htmlangular" },
    -- root_markers alone would not stop the server: an unmatched marker set
    -- only leaves root_dir nil, and nvim starts the client anyway. ngserver
    -- then dies resolving @angular/language-service in a non-Angular project.
    -- Returning without calling on_dir is what actually prevents the start.
    root_dir = function(bufnr, on_dir)
        local root = fs.root(bufnr, { "angular.json", "nx.json" })
        if not root then
            return
        end
        on_dir(root)
    end,
}
