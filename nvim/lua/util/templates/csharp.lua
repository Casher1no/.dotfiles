-- Generic (non-Unity) C# templates for plain .csproj/.sln projects.
-- Namespace is root namespace (nearest .csproj filename) + subfolders
-- between the project root and the target file.

local M = {}
M.LABEL = "C#"

local function project_root(path)
    local dir = vim.fs.dirname((path:gsub("\\", "/")))
    local matches = vim.fs.find(function(name)
        return name:match("%.csproj$") ~= nil
    end, { path = dir, upward = true, limit = 1 })
    if not matches[1] then
        return nil, nil
    end
    return vim.fs.dirname(matches[1]), vim.fn.fnamemodify(matches[1], ":t:r")
end

local function namespace_for(path)
    local normalized = path:gsub("\\", "/")
    local root, root_ns = project_root(path)
    if not root then
        return "App"
    end

    local dir = vim.fs.dirname(normalized)
    local relative = dir:sub(#root + 2)
    local segments = { root_ns }
    if relative ~= "" then
        for segment in relative:gmatch("[^/]+") do
            segments[#segments + 1] = segment
        end
    end
    return table.concat(segments, ".")
end

M.KINDS = {
    {
        key = "class",
        label = "Plain class",
        ext = ".cs",
        namespace_for = namespace_for,
        build = function(class, ns)
            return { "namespace " .. ns, "{", "\tpublic class " .. class, "\t{", "\t}", "}" }
        end,
    },
    {
        key = "struct",
        label = "Struct",
        ext = ".cs",
        namespace_for = namespace_for,
        build = function(class, ns)
            return { "namespace " .. ns, "{", "\tpublic readonly struct " .. class, "\t{", "\t}", "}" }
        end,
    },
    {
        key = "interface",
        label = "Interface",
        ext = ".cs",
        namespace_for = namespace_for,
        build = function(class, ns)
            return { "namespace " .. ns, "{", "\tpublic interface " .. class, "\t{", "\t}", "}" }
        end,
    },
}

return M
