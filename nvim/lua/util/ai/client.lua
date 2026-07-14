-- Thin async curl client for LM Studio's OpenAI-compatible server.
-- All callbacks are delivered via vim.schedule (vim.system callbacks run on
-- a luv thread where the nvim API is off-limits).
--
-- Unavailability contract: when the server is unreachable, callbacks get
-- (nil, "offline") and nothing is notified from here except through
-- notify_offline(), which user-invoked features (chat/inline) may call and
-- which dedups to once a minute. The autocomplete path never notifies at
-- all — coding without a server must stay completely silent.
local config = require("util.ai.config")

local M = {}

-- Cached server status; the palette AI section renders from this without
-- blocking and triggers async refreshes.
M.status = { online = nil, models = {}, fetched_at = 0 }

local last_offline_notify = 0

function M.notify_offline()
    local now = vim.uv.now()
    if now - last_offline_notify > 60000 then
        last_offline_notify = now
        vim.notify("LM Studio server unreachable — AI features idle (palette → AI)", vim.log.levels.WARN)
    end
end

local function mark_offline()
    M.status.online = false
    M.status.models = {}
    M.status.fetched_at = vim.uv.now()
end

-- Incremental SSE parser: feed raw stdout chunks (which may split lines or
-- JSON anywhere), get back the completed content deltas. Pure function over
-- the passed state table so it can be tested headlessly.
function M._sse_feed(sse, chunk)
    sse.pending = (sse.pending or "") .. chunk
    local deltas = {}
    while true do
        local nl = sse.pending:find("\n", 1, true)
        if not nl then
            break
        end
        local line = sse.pending:sub(1, nl - 1):gsub("\r$", "")
        sse.pending = sse.pending:sub(nl + 1)
        local payload = line:match("^data:%s*(.*)")
        if payload and payload ~= "" and payload ~= "[DONE]" then
            local ok, obj = pcall(vim.json.decode, payload)
            if ok and type(obj) == "table" then
                local choice = type(obj.choices) == "table" and obj.choices[1]
                local content = type(choice) == "table"
                    and type(choice.delta) == "table"
                    and choice.delta.content
                if type(content) == "string" and content ~= "" then
                    deltas[#deltas + 1] = content
                end
            end
        end
    end
    return deltas
end

-- GET /models. cb(list) on success (list of model id strings), cb(nil, err)
-- otherwise. Also refreshes M.status and auto-selects the first model if
-- none is configured yet.
function M.models(cb)
    vim.system({
        "curl",
        "-sf",
        "--connect-timeout",
        "1",
        "--max-time",
        "2",
        config.get().base_url .. "/models",
    }, { text = true }, function(res)
        vim.schedule(function()
            if res.code ~= 0 then
                mark_offline()
                if cb then
                    cb(nil, "offline")
                end
                return
            end
            local ok, data = pcall(vim.json.decode, res.stdout or "")
            local list = {}
            if ok and type(data) == "table" and type(data.data) == "table" then
                for _, m in ipairs(data.data) do
                    if type(m.id) == "string" then
                        list[#list + 1] = m.id
                    end
                end
            end
            M.status.online = true
            M.status.models = list
            M.status.fetched_at = vim.uv.now()
            if not config.get().model and #list > 0 then
                config.set("model", list[1])
            end
            if cb then
                cb(list)
            end
        end)
    end)
end

local function curl_seconds(timeout_ms)
    return tostring(math.max(1, math.floor((timeout_ms or 120000) / 1000)))
end

-- Streaming POST /chat/completions.
-- opts = { messages, model?, temperature?, max_tokens?, stop?, timeout_ms?,
--          on_delta = fn(text)?, on_done = fn(full_text, err) }
-- Returns { cancel = fn() }; after cancel() no callbacks fire.
function M.chat(opts)
    local cfg = config.get()
    local model = opts.model or cfg.model
    if not model then
        vim.schedule(function()
            opts.on_done(nil, "no model")
        end)
        return { cancel = function() end }
    end

    local body = {
        model = model,
        stream = true,
        temperature = opts.temperature or 0.3,
        max_tokens = opts.max_tokens or 1024,
        messages = opts.messages,
    }
    if opts.stop then
        body.stop = opts.stop
    end

    local sse, acc = {}, {}
    local cancelled = false
    local proc = vim.system({
        "curl",
        "-sS",
        "-N",
        "--no-buffer",
        "--connect-timeout",
        "1",
        "--max-time",
        curl_seconds(opts.timeout_ms),
        "-H",
        "Content-Type: application/json",
        "-d",
        "@-",
        cfg.base_url .. "/chat/completions",
    }, {
        stdin = vim.json.encode(body),
        stdout = function(_, data)
            if cancelled or not data then
                return
            end
            local deltas = M._sse_feed(sse, data)
            if #deltas > 0 then
                vim.schedule(function()
                    if cancelled then
                        return
                    end
                    for _, d in ipairs(deltas) do
                        acc[#acc + 1] = d
                        if opts.on_delta then
                            opts.on_delta(d)
                        end
                    end
                end)
            end
        end,
    }, function(res)
        vim.schedule(function()
            if cancelled then
                return
            end
            if res.code == 0 or #acc > 0 then
                -- A mid-stream timeout still returns what was generated.
                M.status.online = true
                opts.on_done(table.concat(acc))
            elseif res.code == 7 or res.code == 28 then
                mark_offline()
                opts.on_done(nil, "offline")
            else
                opts.on_done(nil, vim.trim(res.stderr or "") ~= "" and vim.trim(res.stderr) or ("curl exit " .. res.code))
            end
        end)
    end)

    return {
        cancel = function()
            cancelled = true
            pcall(function()
                proc:kill(15)
            end)
        end,
    }
end

-- Non-streaming chat request, used by ghost-text completion. cb(text) or
-- cb(nil, err). Returns { cancel = fn() }.
function M.complete(opts, cb)
    local cfg = config.get()
    local model = opts.model or cfg.model
    if not model then
        vim.schedule(function()
            cb(nil, "no model")
        end)
        return { cancel = function() end }
    end

    local body = {
        model = model,
        stream = false,
        temperature = opts.temperature or 0.2,
        max_tokens = opts.max_tokens or 128,
        messages = opts.messages,
    }
    if opts.stop then
        body.stop = opts.stop
    end

    local cancelled = false
    local proc = vim.system({
        "curl",
        "-sf",
        "--connect-timeout",
        "1",
        "--max-time",
        curl_seconds(opts.timeout_ms or 10000),
        "-H",
        "Content-Type: application/json",
        "-d",
        "@-",
        cfg.base_url .. "/chat/completions",
    }, {
        stdin = vim.json.encode(body),
        text = true,
    }, function(res)
        vim.schedule(function()
            if cancelled then
                return
            end
            if res.code ~= 0 then
                -- 7 = connection refused, 28 = timeout, 22 = HTTP error
                -- (e.g. no model loaded). All silent-fail territory.
                if res.code == 7 or res.code == 28 then
                    mark_offline()
                end
                cb(nil, "offline")
                return
            end
            M.status.online = true
            local ok, data = pcall(vim.json.decode, res.stdout or "")
            local choice = ok and type(data) == "table" and type(data.choices) == "table" and data.choices[1]
            local content = type(choice) == "table"
                and type(choice.message) == "table"
                and choice.message.content
            if type(content) == "string" then
                cb(content)
            else
                cb(nil, "bad response")
            end
        end)
    end)

    return {
        cancel = function()
            cancelled = true
            pcall(function()
                proc:kill(15)
            end)
        end,
    }
end

return M
