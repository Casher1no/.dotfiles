-- Unity C# templates. The namespace a new file gets is the same one
-- util/cs_namespace.lua holds every existing file to: the project's root
-- namespace (Unity's own m_ProjectGenerationRootNamespace) plus the folders
-- below Assets/Scripts, so Assets/Scripts/Features/Items/Components/Foo.cs
-- lands in Inheritance.Features.Items.Components. Sharing the resolver means a
-- file created here can never be one the "Fix namespace" intention then
-- objects to.

local M = {}
M.LABEL = "Unity"

local function namespace_for(path)
    -- Falls back to the folder name for a project that declares no root
    -- namespace anywhere; the intention prompts for the real one on first use.
    return require("util.cs_namespace").expected(path) or vim.fn.fnamemodify(path, ":h:t")
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
