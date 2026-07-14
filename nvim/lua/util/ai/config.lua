-- Persisted settings for the local-LLM AI features (see util/ai/init.lua).
-- Machine-local (stdpath state): which model is available here differs per
-- machine, so this intentionally does not sync through the dotfiles repo.
local M = {}

M.file = vim.fn.stdpath("state") .. "/ai.json"

M.defaults = {
    base_url = "http://127.0.0.1:1234/v1", -- LM Studio's OpenAI-compatible server
    model = nil, -- auto-selected on first successful /models fetch
    autocomplete = false,
}

local function read_all()
    local f = io.open(M.file, "r")
    if not f then
        return {}
    end
    local content = f:read("*a")
    f:close()
    if content == "" then
        return {}
    end
    local ok, data = pcall(vim.json.decode, content)
    return (ok and type(data) == "table") and data or {}
end

local function write_all(data)
    local f = io.open(M.file, "w")
    if f then
        f:write(vim.json.encode(data))
        f:close()
    end
end

function M.get()
    return vim.tbl_extend("force", vim.deepcopy(M.defaults), read_all())
end

function M.set(key, value)
    local data = read_all()
    data[key] = value
    write_all(data)
end

function M.model()
    return M.get().model
end

return M
