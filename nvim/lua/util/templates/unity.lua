-- Unity C# templates. Namespace is derived from the path segment after
-- "Scripts" (Assets/Scripts/Features/Items/Components/Foo.cs ->
-- Inheritance.Features.Items.Components), matching every namespace already
-- in this project (see CLAUDE.md / ARCHITECTURE.md).

local M = {}
M.LABEL = "Unity"

local function namespace_for(path)
    local normalized = path:gsub("\\", "/")
    local segments = {}
    for segment in normalized:gmatch("[^/]+") do
        segments[#segments + 1] = segment
    end

    local scripts_index = nil
    for i, segment in ipairs(segments) do
        if segment == "Scripts" then
            scripts_index = i
        end
    end
    if not scripts_index then
        return "Inheritance"
    end

    local ns_segments = { "Inheritance" }
    for i = scripts_index + 1, #segments - 1 do
        ns_segments[#ns_segments + 1] = segments[i]
    end
    return table.concat(ns_segments, ".")
end

M.KINDS = {
    {
        key = "monobehaviour",
        label = "MonoBehaviour Component",
        ext = ".cs",
        namespace_for = namespace_for,
        build = function(class, ns)
            return {
                "using UnityEngine;",
                "",
                "namespace " .. ns,
                "{",
                "\tpublic class " .. class .. " : MonoBehaviour",
                "\t{",
                "\t\tprivate void Awake()",
                "\t\t{",
                "\t\t}",
                "\t}",
                "}",
            }
        end,
    },
    {
        key = "scriptableobject",
        label = "ScriptableObject Record",
        ext = ".cs",
        namespace_for = namespace_for,
        build = function(class, ns)
            return {
                "using BetterAttributes;",
                "using UnityEngine;",
                "",
                "namespace " .. ns,
                "{",
                ('\t[CreateAssetMenu(fileName = "%s", menuName = "Our/Records/%s")]'):format(class, class),
                "\tpublic class " .. class .. " : ScriptableObject",
                "\t{",
                "\t\tpublic string Id => name;",
                "\t}",
                "}",
            }
        end,
    },
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
