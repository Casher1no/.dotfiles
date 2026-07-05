-- New-file-from-template registry. Detects the current project's stack(s)
-- via util/project_stacks.lua and only offers that stack's templates (e.g.
-- Unity C# in a Unity project, Laravel + PHP in a Laravel project, Angular
-- in an Angular project). If no stack is detected, falls back to showing
-- every language's templates, each labeled with its stack so it's still
-- unambiguous.
--
-- Invoked from Neo-tree ("A" mapping, see plugins/neo-tree.lua) or the
-- command palette (see util/palette.lua).

local case = require("util.case")

local M = {}

local STACK_MODULES = {
    unity = "util.templates.unity",
    csharp = "util.templates.csharp",
    laravel = "util.templates.laravel",
    php = "util.templates.php",
    angular = "util.templates.angular",
    vue = "util.templates.vue",
    python = "util.templates.python",
}

local ALL_STACKS = { "unity", "csharp", "laravel", "php", "angular", "vue", "python" }

local function collect_kinds(stack_keys, prefix_labels)
    local kinds, seen = {}, {}
    for _, stack_key in ipairs(stack_keys) do
        local mod_name = STACK_MODULES[stack_key]
        if mod_name then
            local ok, mod = pcall(require, mod_name)
            if ok and mod then
                for _, kind in ipairs(mod.KINDS) do
                    local id = stack_key .. ":" .. kind.key
                    if not seen[id] then
                        seen[id] = true
                        local label = prefix_labels and ("[" .. mod.LABEL .. "] " .. kind.label) or kind.label
                        kinds[#kinds + 1] = vim.tbl_extend("force", {}, kind, { label = label })
                    end
                end
            end
        end
    end
    return kinds
end

-- Prompt for template kind + name, write the file into `dir`, then open it.
-- Calls on_done() afterwards (e.g. to refresh a file tree).
function M.create_interactive(dir, on_done)
    local stacks = require("util.project_stacks").detect(dir)
    if #stacks == 0 then
        stacks = ALL_STACKS
    end

    local kinds = collect_kinds(stacks, #stacks > 1)
    if #kinds == 0 then
        vim.notify("No file templates registered for this project type", vim.log.levels.WARN)
        return
    end

    local labels = {}
    for _, kind in ipairs(kinds) do
        labels[#labels + 1] = kind.label
    end

    vim.ui.select(labels, { prompt = "New file:" }, function(choice)
        if not choice then
            return
        end
        local kind = nil
        for _, k in ipairs(kinds) do
            if k.label == choice then
                kind = k
            end
        end

        vim.ui.input({ prompt = "Name: " }, function(raw_name)
            if not raw_name or raw_name == "" then
                return
            end

            local class_name = kind.class_name and kind.class_name(raw_name) or case.pascal_case(raw_name)
            local filename = kind.filename and kind.filename(raw_name, class_name) or (class_name .. kind.ext)
            local path = dir .. "/" .. filename

            if vim.fn.filereadable(path) == 1 then
                vim.notify("File already exists: " .. path, vim.log.levels.ERROR)
                return
            end

            local namespace = kind.namespace_for and kind.namespace_for(path) or nil
            local lines = kind.build(class_name, namespace, path)

            vim.fn.mkdir(dir, "p")
            vim.fn.writefile(lines, path)
            vim.cmd("edit " .. vim.fn.fnameescape(path))
            if on_done then
                on_done()
            end
        end)
    end)
end

return M
