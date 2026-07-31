-- Whispy - Core.lua
-- Namespace, flat-dark palette, shared UI helpers, DB init, slash commands.

local addonName, ns = ...

--=========================================================================
-- Palette (flat dark). Reference ns.P.xxx everywhere -- never hardcode.
--=========================================================================
local P = {
    bg      = { 0.05, 0.05, 0.09, 0.97 },  -- window background
    header  = { 0.08, 0.08, 0.13, 1.00 },  -- header/footer strip
    footer  = { 0.07, 0.07, 0.11, 1.00 },
    border  = { 0.20, 0.20, 0.30, 1.00 },  -- window edge
    sep     = { 0.15, 0.15, 0.22, 1.00 },  -- separators / button borders
    accent  = { 0.24, 0.60, 1.00, 1.00 },  -- blue accent (titles, highlights)
    btnBg   = { 0.13, 0.13, 0.20, 1.00 },
    btnHov  = { 0.22, 0.22, 0.33, 1.00 },
    text    = { 0.88, 0.88, 0.92, 1.00 },  -- primary text
    dim     = { 0.45, 0.45, 0.52, 1.00 },  -- muted text
    inC     = { 0.85, 0.85, 0.90 },        -- incoming message text
    outC    = { 0.62, 0.78, 1.00 },        -- outgoing ("You") message text
    bubIn   = { 0.16, 0.17, 0.22, 1.00 },  -- incoming bubble background (grey)
    bubOut  = { 0.10, 0.30, 0.24, 1.00 },  -- outgoing bubble background (green)
    bubTxt  = { 0.93, 0.94, 0.96, 1.00 },  -- bubble text
    bubTime = { 0.60, 0.62, 0.66, 1.00 },  -- bubble timestamp
}
ns.P = P

--=========================================================================
-- ApplyFlatBg -- the single backdrop helper
--=========================================================================
local solidBD = {
    bgFile   = "Interface/Buttons/WHITE8X8",
    edgeFile = "Interface/Buttons/WHITE8X8",
    edgeSize = 1,
    insets   = { left = 1, right = 1, top = 1, bottom = 1 },
}

function ns.ApplyFlatBg(f, r, g, b, a, er, eg, eb, ea)
    f:SetBackdrop(solidBD)
    f:SetBackdropColor(r, g, b, a or 1)
    f:SetBackdropBorderColor(
        er or P.border[1], eg or P.border[2], eb or P.border[3], ea or P.border[4]
    )
end

--=========================================================================
-- MakeFlatBtn -- reusable flat button factory
--=========================================================================
function ns.MakeFlatBtn(parent, text, w, h)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(w or 60, h or 22)
    ns.ApplyFlatBg(btn, P.btnBg[1], P.btnBg[2], P.btnBg[3], P.btnBg[4],
                        P.sep[1], P.sep[2], P.sep[3], P.sep[4])
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetAllPoints()
    fs:SetJustifyH("CENTER")
    fs:SetTextColor(P.text[1], P.text[2], P.text[3])
    fs:SetText(text)
    btn.label = fs

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(P.btnHov[1], P.btnHov[2], P.btnHov[3], P.btnHov[4])
        fs:SetTextColor(1, 1, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(P.btnBg[1], P.btnBg[2], P.btnBg[3], P.btnBg[4])
        fs:SetTextColor(P.text[1], P.text[2], P.text[3])
    end)
    return btn
end

--=========================================================================
-- Small utilities
--=========================================================================

-- "|cAARRGGBB" colour string from a 0-1 rgb triple.
function ns.Hex(r, g, b)
    return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

-- Class colour for a player: from their GUID when the game still knows them,
-- otherwise from an explicit class token (stored metadata / sample data).
function ns.ClassColorFromGUID(guid, class)
    if guid and guid ~= "" then
        local ok, _, c = pcall(GetPlayerInfoByGUID, guid)
        if ok and c and RAID_CLASS_COLORS[c] then
            return RAID_CLASS_COLORS[c]
        end
    end
    if class and RAID_CLASS_COLORS[class] then
        return RAID_CLASS_COLORS[class]
    end
    return nil
end

-- Strip a trailing "-Realm" if it matches the player's own realm, for tidy display.
local playerRealm
function ns.ShortName(name)
    if not name then return "?" end
    if not playerRealm then
        playerRealm = (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
    end
    local base, realm = name:match("^(.-)%-(.+)$")
    if base and realm then
        local nr = realm:gsub("%s+", "")
        if nr == playerRealm then return base end
    end
    return name
end

function ns.Print(msg)
    print(ns.Hex(P.accent[1], P.accent[2], P.accent[3]) .. "Whispy|r: " .. tostring(msg))
end

--=========================================================================
-- Localisation
--
-- Every user-visible string lives in ns.strings (English). Translations go in
-- ns.locales[<locale>] and win when the client is running that locale --
-- unless ns.forceEnglish is set, which pins the whole UI back to the English
-- source regardless of client language.
--=========================================================================
ns.strings = {
    recentChats = "Recent chats",
    allChats    = "All Chats",
    noChats     = "No chats yet",
    today       = "Today",
    typeHint    = "Type a message, Enter to send",
    now         = "now",
    tipLeft     = "|cffaaaaaaLeft-click:|r recent chats",
    tipRight    = "|cffaaaaaaRight-click:|r all chats",
    tipDrag     = "|cffaaaaaaDrag:|r move button",
}

ns.locales = {}   -- [locale] = { key = "translation", ... }

function ns.T(key)
    if not ns.forceEnglish then
        local loc = ns.locales[GetLocale()]
        local s = loc and loc[key]
        if s then return s end
    end
    return ns.strings[key] or key
end

-- date() renders month and weekday names in the client's language. When
-- ns.forceEnglish is set we substitute the English names ourselves and hand
-- the remaining (language-neutral) tokens to date(). All *displayed* dates go
-- through here; raw date() is only used for numeric comparison keys.
local EN_MONTH = { "January", "February", "March", "April", "May", "June",
                   "July", "August", "September", "October", "November", "December" }
local EN_DAY   = { "Sunday", "Monday", "Tuesday", "Wednesday",
                   "Thursday", "Friday", "Saturday" }

function ns.Date(fmt, t)
    if ns.forceEnglish then
        local d = date("*t", t)
        fmt = fmt:gsub("%%%%", "\1")                          -- protect literal %%
                 :gsub("%%B", EN_MONTH[d.month])
                 :gsub("%%b", EN_MONTH[d.month]:sub(1, 3))
                 :gsub("%%A", EN_DAY[d.wday])
                 :gsub("%%a", EN_DAY[d.wday]:sub(1, 3))
                 :gsub("\1", "%%%%")
    end
    return date(fmt, t)
end

--=========================================================================
-- SavedVariables / DB
--=========================================================================
local defaults = {
    enabled       = true,   -- route whispers into Whispy windows (suppress default chat)
    playSound     = true,   -- play a sound on incoming whisper
    historyLimit  = 200,    -- max stored lines per conversation
    replayLimit   = 30,     -- lines replayed into a freshly opened window
    winWidth      = 340,
    winHeight     = 260,
    history       = {},     -- [key] = { {t=epoch, dir="in"/"out", who=name, text=..}, ... }
    meta          = {},     -- [key] = { name=, isBN=, presenceID=, guid= } (identity)
    lastPos       = nil,    -- { point, relPoint, x, y } for the next new window
    minimap       = { angle = 205 },  -- minimap button position (degrees)
}
ns.defaults = defaults

local function InitDB()
    WhispyDB = WhispyDB or {}
    for k, v in pairs(defaults) do
        if WhispyDB[k] == nil then
            if type(v) == "table" then
                WhispyDB[k] = CopyTable(v)
            else
                WhispyDB[k] = v
            end
        end
    end
    ns.db = WhispyDB
end

--=========================================================================
-- Load / lifecycle
--=========================================================================
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        InitDB()
        if ns.History and ns.History.Prune then ns.History:Prune() end
    elseif event == "PLAYER_LOGIN" then
        playerRealm = (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
    end
end)

--=========================================================================
-- Slash commands
--=========================================================================
SLASH_WHISPY1 = "/whispy"
SlashCmdList["WHISPY"] = function(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.*)$")
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "help" then
        ns.Print("commands:")
        ns.Print("  /whispy <name>        - open a whisper window")
        ns.Print("  /whispy toggle        - enable/disable routing whispers into Whispy")
        ns.Print("  /whispy sound         - toggle incoming whisper sound")
        ns.Print("  /whispy list          - list open conversations")
        ns.Print("  /whispy clear <name>  - clear history for a conversation")
        ns.Print("  /whispy clearall      - wipe all stored history")
        ns.Print("  /whispy chats         - open the full chat list")
        ns.Print("  /whispy minimap       - show/hide the minimap button")
        ns.Print("  /whispy test          - play a simulated demo conversation")
        ns.Print("  /whispy sim <name> <text> - inject one fake incoming whisper")
    elseif cmd == "chats" or cmd == "all" then
        ns.ToggleChatList()
    elseif cmd == "minimap" then
        ns.SetMinimapShown(ns.db.minimap.hide == true)  -- flip current state
        ns.Print("minimap button " .. (ns.db.minimap.hide and "|cffff6666hidden|r" or "|cff44ff88shown|r"))
    elseif cmd == "toggle" then
        ns.db.enabled = not ns.db.enabled
        ns.Print("whisper routing " .. (ns.db.enabled and "|cff44ff88ON|r" or "|cffff6666OFF|r"))
    elseif cmd == "sound" then
        ns.db.playSound = not ns.db.playSound
        ns.Print("incoming sound " .. (ns.db.playSound and "|cff44ff88ON|r" or "|cffff6666OFF|r"))
    elseif cmd == "list" then
        ns.ListWindows()
    elseif cmd == "clear" then
        if rest and rest ~= "" then
            ns.History:Clear(rest)
            ns.Print("cleared history for " .. rest)
        else
            ns.Print("usage: /whispy clear <name>")
        end
    elseif cmd == "clearall" then
        wipe(ns.db.history)
        ns.Print("all history wiped.")
    elseif cmd == "screenshot" or cmd == "ss" then
        ns.SetScreenshotMode(not ns.screenshot)
    elseif cmd == "test" then
        ns.RunTest()
    elseif cmd == "sim" then
        local name, text = rest:match("^(%S+)%s+(.+)$")
        if name and text then
            ns.SimulateIncoming(name, text)
        else
            ns.Print("usage: /whispy sim <name> <text>")
        end
    else
        -- treat the whole message as a player name to open
        local target = msg:gsub("%s+$", "")
        if target ~= "" then
            ns.OpenConversation(target)
        end
    end
end
