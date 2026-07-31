-- Chaty - History.lua
-- Per-conversation chat history stored in ChatyDB.history[key].

local addonName, ns = ...

local History = {}
ns.History = History

-- Append a line. dir = "in" | "out". who = display name (for incoming), may be nil.
function History:Add(key, dir, who, text)
    local db = ns.db
    if not db then return end
    local list = db.history[key]
    if not list then
        list = {}
        db.history[key] = list
    end
    list[#list + 1] = { t = time(), dir = dir, who = who, text = text }

    -- Trim to the configured cap (drop oldest).
    local limit = db.historyLimit or 200
    local overflow = #list - limit
    if overflow > 0 then
        for i = 1, #list do
            list[i] = list[i + overflow]
        end
    end
end

-- Return the last `count` entries for a key (chronological order), or empty table.
function History:GetRecent(key, count)
    local list = ns.db and ns.db.history[key]
    if not list then return {} end
    local n = #list
    if not count or count >= n then return list end
    local out = {}
    for i = n - count + 1, n do
        out[#out + 1] = list[i]
    end
    return out
end

function History:Clear(key)
    if ns.db and ns.db.history[key] then
        ns.db.history[key] = nil
    end
end

-- Enforce the per-conversation cap across all stored conversations (on load).
function History:Prune()
    local db = ns.db
    if not db or not db.history then return end
    local limit = db.historyLimit or 200
    for key, list in pairs(db.history) do
        local overflow = #list - limit
        if overflow > 0 then
            local trimmed = {}
            for i = overflow + 1, #list do
                trimmed[#trimmed + 1] = list[i]
            end
            db.history[key] = trimmed
        end
    end
end

-- Fallback display name derived from a conversation key (pre-metadata history).
local function KeyToName(key)
    if key:sub(1, 2) == "W:" then
        local n = key:sub(3):gsub("%-.*$", "")   -- drop realm
        return (n:gsub("^%l", string.upper))
    end
    return "BattleNet"
end

-- Strip WoW colour/hyperlink escapes for a plain-text preview line.
local function StripEscapes(s)
    if not s then return "" end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("|H.-|h(.-)|h", "%1")
    s = s:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    return s
end

-- Return all conversations that have history, newest activity first.
-- Each entry: { key, name, isBN, presenceID, guid, last, preview }
function History:GetConversations()
    local db = ns.db
    local out = {}
    if not db or not db.history then return out end
    for key, list in pairs(db.history) do
        if #list > 0 then
            local m = db.meta and db.meta[key]
            local lastEntry = list[#list]
            out[#out + 1] = {
                key        = key,
                name       = (m and m.name) or KeyToName(key),
                isBN       = m and m.isBN or (key:sub(1, 3) == "BN:"),
                presenceID = m and m.presenceID,
                guid       = m and m.guid,
                class      = m and m.class,
                last       = lastEntry.t or 0,
                preview    = StripEscapes(lastEntry.text),
            }
        end
    end
    table.sort(out, function(a, b) return a.last > b.last end)
    return out
end
