-- Whispy - Whisper.lua
-- Routes whisper events into Whispy windows, suppresses the default chat copy,
-- and sends outgoing whispers from conversation windows.

local addonName, ns = ...

--=========================================================================
-- Sending
--=========================================================================

-- Called by a window's edit box on Enter.
function ns.SendFromWindow(win, text)
    local info = win.info
    -- Screenshot mode talks to nobody: the conversations are fabricated, so
    -- echo the line locally instead of whispering a real player.
    if ns.screenshot then
        win:AddChat("out", nil, text)
        ns.History:Add(ns.MakeKey(info), "out", nil, text)
        return
    end
    if info.isBN and info.presenceID then
        if C_BattleNet and C_BattleNet.SendWhisper then
            C_BattleNet.SendWhisper(info.presenceID, text)
        elseif BNSendWhisper then
            BNSendWhisper(info.presenceID, text)
        end
    else
        local target = info.name
        if not target or target == "" then return end
        SendChatMessage(text, "WHISPER", nil, target)
    end
    -- The matching *_INFORM event echoes the line back into the window,
    -- so we don't add it here (single source of truth).
end

--=========================================================================
-- BattleNet name resolution
--=========================================================================

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

-- Retail 12.x can deliver the bnSenderID event arg as a "secret value", which
-- tainted code may not read, concatenate, or pass to GetAccountInfoByID.
-- Returns a normal, storable ID or nil: secrets are dropped, then re-resolved
-- from the (non-secret) sender name where possible so replies keep working.
local function UsableBNetID(presenceID, name)
    if IsSecret(presenceID) then presenceID = nil end
    -- IsSecret must run before the ~= "" comparison: comparing a secret throws.
    if not presenceID and BNet_GetBNetIDAccount
        and not IsSecret(name) and name and name ~= "" then
        local id = BNet_GetBNetIDAccount(name)
        if id and not IsSecret(id) then presenceID = id end
    end
    return presenceID
end

-- Protected display strings ("|Kf1|k...|k") render as the real name only in
-- the session that minted them; string operations mangle them and storing
-- them yields garbage after a reload. Treat them as unusable for display.
local function IsKString(s)
    return type(s) == "string" and not IsSecret(s) and s:find("|K", 1, true) ~= nil
end
ns.IsKString = IsKString

local function BNName(presenceID, fallback)
    if IsSecret(presenceID) then presenceID = nil end
    if presenceID and C_BattleNet and C_BattleNet.GetAccountInfoByID then
        local ai = C_BattleNet.GetAccountInfoByID(presenceID)
        if ai then
            -- account-info fields can come back as 12.x secret values too;
            -- IsSecret must run before any comparison or string op on them
            local an = ai.accountName
            if not IsSecret(an) and an and an ~= "" and not IsKString(an) then
                return an
            end
            -- the battleTag is always plain text; its nickname half is the
            -- name the contact goes by
            local bt = ai.battleTag
            if not IsSecret(bt) and bt and bt ~= "" then
                return bt:match("^(.-)#") or bt
            end
        end
    end
    return fallback or ("BN:" .. tostring(presenceID))
end
ns.BNName = BNName

--=========================================================================
-- Incoming / outgoing routing (fires once per event)
--=========================================================================

-- While combat hides the windows, the combatChat option leaves the default
-- chat copy of each whisper visible, so nothing arrives unseen mid-fight.
local function ChatCopyShown()
    return ns.inCombat and ns.db.combatHide and ns.db.combatChat
end

local function Alert(win)
    if ChatCopyShown() then
        -- The default chat frame is showing this whisper itself, with the
        -- game's own tell sound and taskbar flash; only queue the window.
        ns.ShowWindow(win)
        return
    end
    ns.AlertSound("in", win.info)
    -- ShowWindow keeps the window hidden (and queues it) while in combat.
    if ns.ShowWindow(win) and not win:IsMouseOver() then
        FlashClientIcon()
    end
end

-- The game records a whisper in its reply memory only after a chat frame has
-- displayed it, and Whispy suppresses that display. Mirror the record so the
-- game's own reply paths keep working: the Reply key, the reply-to-last-told
-- key, and "/r" typed into the default edit box. Each of them then puts the
-- edit box into whisper mode, where the UpdateHeader hook below takes over.
-- `name` is the raw event author/target, exactly what the game would store.
local function RememberTell(name, isBN, told)
    if IsSecret(name) or type(name) ~= "string" or name == "" then return end
    local setter
    if ChatFrameUtil then
        setter = told and ChatFrameUtil.SetLastToldTarget or ChatFrameUtil.SetLastTellTarget
    else
        setter = told and ChatEdit_SetLastToldTarget or ChatEdit_SetLastTellTarget
    end
    if type(setter) ~= "function" then return end
    -- The game's list can hold secret names from lockdown whispers it displayed
    -- itself; comparing our plain name against one of those throws.
    pcall(setter, name, isBN and "BN_WHISPER" or "WHISPER")
end

-- Shared routing core. Both the live event handlers and the /whispy test
-- simulator go through these two functions, so there is one code path.

-- Conversation descriptors of the most recent incoming and outgoing whisper,
-- the fallback for the reply hooks below when the game's own memory is empty.
-- Session-only, like the default UI's own last-teller memory.
local lastIncoming, lastOutgoing

-- info = { name=, isBN=, presenceID=, guid= }
-- alert: nil/true = sound, window and flash; "quiet" = window only (used for
-- lines recovered after a lockdown, which the chat frame already announced);
-- false = record only. epoch: original time of a recovered line.
local function RouteIncoming(info, text, alert, epoch)
    local win = ns.GetWindow(info)
    lastIncoming = win.info
    win:AddChat("in", info.name, text, epoch)
    ns.History:Add(ns.MakeKey(win.info), "in", info.name, text, epoch)
    if alert == "quiet" then
        ns.ShowWindow(win)
    elseif alert ~= false then
        Alert(win)
    end
    -- Still not on screen after the alert: combat, a window the user closed,
    -- or a background tab in tab mode. Count it so the minimap badge (and the
    -- tab's own badge) can say something arrived. IsVisible rather than
    -- IsShown: a tabbed window can be flagged shown while the host is hidden.
    if not win:IsVisible() then ns.MarkUnread(win) end
    return win
end

local function RouteOutgoing(info, text, quiet, epoch)
    local win = ns.GetWindow(info)
    lastOutgoing = win.info
    win:AddChat("out", nil, text, epoch)
    ns.History:Add(ns.MakeKey(win.info), "out", nil, text, epoch)
    if not quiet then ns.AlertSound("out", win.info) end
    ns.ShowWindow(win)
    return win
end

local handlers = {}

-- The guid arg can also be a 12.x secret value; a stored secret guid would
-- throw later (GetWindow compares it), so drop it at the source.
local function UsableGUID(guid)
    if IsSecret(guid) then return nil end
    return guid
end

-- Regular incoming whisper: arg1=text, arg2=author(Name-Realm), arg12=guid
function handlers.CHAT_MSG_WHISPER(...)
    local text, author = ...
    local guid = UsableGUID(select(12, ...))
    RememberTell(author, false)
    RouteIncoming({ name = author, isBN = false, guid = guid }, text)
end

-- Regular outgoing whisper you sent: arg1=text, arg2=target, arg12=guid
function handlers.CHAT_MSG_WHISPER_INFORM(...)
    local text, target = ...
    local guid = UsableGUID(select(12, ...))
    RememberTell(target, false, true)
    RouteOutgoing({ name = target, isBN = false, guid = guid }, text)
end

-- BattleNet incoming: arg1=text, arg2=name, arg13=presenceID
function handlers.CHAT_MSG_BN_WHISPER(...)
    local text, author = ...
    local presenceID = UsableBNetID(select(13, ...), author)
    RememberTell(author, true)
    RouteIncoming({ name = BNName(presenceID, author), isBN = true, presenceID = presenceID }, text)
end

-- BattleNet outgoing: arg1=text, arg2=target, arg13=presenceID
function handlers.CHAT_MSG_BN_WHISPER_INFORM(...)
    local text, target = ...
    local presenceID = UsableBNetID(select(13, ...), target)
    RememberTell(target, true, true)
    RouteOutgoing({ name = BNName(presenceID, target), isBN = true, presenceID = presenceID }, text)
end

-- AFK / DND auto-replies from a target you whispered: arg1=message, arg2=author
local function autoReply(label)
    return function(...)
        local text, author = ...
        local guid = select(12, ...)
        local win = ns.Windows[ns.MakeKey({ name = author, isBN = false })]
        if not win then return end -- only surface if a conversation already exists
        win:AddChat("system", author, "[" .. label .. "] " .. text)
    end
end
handlers.CHAT_MSG_AFK = autoReply("AFK")
handlers.CHAT_MSG_DND = autoReply("DND")

-- "No player named '%s' is currently playing." -- the client-localised format
-- string, turned into a Lua pattern that captures the name.
local playerNotFound = ERR_CHAT_PLAYER_NOT_FOUND_S and
    ("^" .. ERR_CHAT_PLAYER_NOT_FOUND_S
        :gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")
        :gsub("%%%%s", "(.+)") .. "$")

-- Returns the open window for the offline target named in a system message,
-- or nil when the message is something else / no conversation is open.
local function OfflineTargetWindow(text)
    if not playerNotFound then return nil end
    if IsSecret(text) then return nil end
    local name = text and text:match(playerNotFound)
    if not name then return nil end
    return ns.Windows[ns.MakeKey({ name = name, isBN = false })]
end

-- Whispering someone offline: show the server's "not online" reply inside the
-- conversation window instead of the default chat frame. The line is
-- transient -- closing the window drops it, and it is never saved to history.
function handlers.CHAT_MSG_SYSTEM(...)
    local text = ...
    local win = OfflineTargetWindow(text)
    if win then win:AddChat("system", nil, text, nil, true) end
end

-- The Battle.net counterpart: whispering an offline BN friend answers with
-- CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE (arg1=display text, arg2=name).
-- BN windows are keyed by presence ID, so find the conversation by name.
local function OfflineBNWindow(name)
    if IsSecret(name) or not name or name == "" then return nil end
    for _, win in pairs(ns.Windows) do
        if win.info.isBN and win.info.name == name then return win end
    end
    return nil
end

function handlers.CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE(...)
    local text, name = ...
    local win = OfflineBNWindow(name)
    if win then win:AddChat("system", nil, text, nil, true) end
end

--=========================================================================
-- Event frame (routing) -- runs once per event, independent of chat frames
--=========================================================================

-- One predicate, used by BOTH the router below and the suppression filter.
-- The chat frames run their filters before our router sees the event, so any
-- disagreement between the two means a message hidden from default chat that
-- never reaches a Whispy window -- silently lost. During the 12.x "chat
-- messaging lockdown" the text and the sender name are each delivered as
-- secret values (MakeKey/AddChat/History concatenate both), so a message with
-- either one secret stays in the default chat frames instead.
local function Routable(...)
    local text, name = ...
    return not (IsSecret(text) or IsSecret(name))
end

--=========================================================================
-- Lockdown recovery -- a whisper that arrives with a secret text or sender
-- stays in the default chat frame (above), but it is also remembered by its
-- chat line ID. Once the lockdown lifts, the client hands the plain text and
-- sender back through C_ChatInfo.GetChatLine*, and the line is routed into
-- its window and history after all -- quietly, since the chat frame already
-- announced it. Lines you sent can only be filed when their target was plain.
--=========================================================================
local pending = {}     -- { event=, lineID=, t=, name=, guid=, presenceID= }
local drainTicker

local recoverable = {
    CHAT_MSG_WHISPER           = "in",
    CHAT_MSG_WHISPER_INFORM    = "out",
    CHAT_MSG_BN_WHISPER        = "in",
    CHAT_MSG_BN_WHISPER_INFORM = "out",
}

local function InLockdown()
    return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
        and C_ChatInfo.InChatMessagingLockdown() or false
end

local function Recover(e)
    local text = C_ChatInfo.GetChatLineText(e.lineID)
    -- nil: the line has left the client's chat log; secret: still unreadable
    -- although the lockdown is over. Neither can be retried usefully.
    if IsSecret(text) or type(text) ~= "string" or text == "" then return end
    local dir = recoverable[e.event]
    local name = e.name
    if not name then
        -- for a line you sent, the recorded sender is you, not the target
        if dir == "out" then return end
        name = C_ChatInfo.GetChatLineSenderName(e.lineID)
        if IsSecret(name) or type(name) ~= "string" or name == "" then return end
    end
    local info
    if e.event:find("_BN_", 1, true) then
        local presenceID = UsableBNetID(e.presenceID, name)
        info = { name = BNName(presenceID, name), isBN = true, presenceID = presenceID }
    else
        local guid = e.guid
        if not guid and dir == "in" and C_ChatInfo.GetChatLineSenderGUID then
            guid = UsableGUID(C_ChatInfo.GetChatLineSenderGUID(e.lineID))
        end
        info = { name = name, isBN = false, guid = guid }
    end
    if dir == "in" then
        RememberTell(name, info.isBN)
        RouteIncoming(info, text, "quiet", e.t)
    else
        RouteOutgoing(info, text, true, e.t)
    end
end

local function Drain()
    if InLockdown() then return end
    local batch = pending
    pending = {}
    for _, e in ipairs(batch) do
        local ok, err = pcall(Recover, e)
        if not ok then geterrorhandler()(err) end
    end
    if #pending == 0 and drainTicker then
        drainTicker:Cancel()
        drainTicker = nil
    end
end

local function Defer(event, ...)
    if not recoverable[event] then return end
    if not (C_ChatInfo and C_ChatInfo.GetChatLineText and C_ChatInfo.GetChatLineSenderName) then return end
    local lineID = select(11, ...)
    if IsSecret(lineID) or type(lineID) ~= "number" then return end
    local name, presenceID = select(2, ...), select(13, ...)
    -- IsSecret must run before any comparison on these
    if IsSecret(name) or name == "" then name = nil end
    if IsSecret(presenceID) then presenceID = nil end
    pending[#pending + 1] = {
        event = event, lineID = lineID, t = time(),
        name = name, guid = UsableGUID(select(12, ...)), presenceID = presenceID,
    }
    if not drainTicker then drainTicker = C_Timer.NewTicker(1, Drain) end
end

local ef = CreateFrame("Frame")
for event in pairs(handlers) do
    ef:RegisterEvent(event)
end
ef:SetScript("OnEvent", function(_, event, ...)
    if not ns.db or not ns.db.enabled then return end
    if not Routable(...) then
        Defer(event, ...)
        return
    end
    local h = handlers[event]
    if not h then return end
    -- Safety net: the default chat copy is already suppressed by the time we
    -- run, so a routing error would swallow the message entirely. If a route
    -- fails (e.g. an unexpected secret value deeper in the payload), echo the
    -- raw line into the default chat frame and surface the error.
    local ok, err = pcall(h, ...)
    if not ok then
        local text, name = ...
        pcall(function()
            DEFAULT_CHAT_FRAME:AddMessage(
                ("%s: %s"):format(tostring(name), tostring(text)), 1, 0.5, 1)
        end)
        geterrorhandler()(err)
    end
end)

--=========================================================================
-- Suppression -- hide the default chat copy while Whispy is handling whispers
--=========================================================================
local function suppress(_, _, ...)
    if not (ns.db and ns.db.enabled == true) then return false end
    -- Windows are hidden in combat; keep the chat copy so the whisper is seen.
    if ChatCopyShown() then return false end
    -- Whispy can't route a secret-valued sender or text into a window, so
    -- leave that copy visible in the default chat frames.
    return Routable(...)  -- true = block from default chat frames
end

local suppressedEvents = {
    "CHAT_MSG_WHISPER",
    "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_BN_WHISPER",
    "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_AFK",
    "CHAT_MSG_DND",
}
for _, e in ipairs(suppressedEvents) do
    ChatFrame_AddMessageEventFilter(e, suppress)
end

-- System messages are only hidden selectively: just the "player not online"
-- reply, and only when a Whispy window is open to show it instead.
ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(self, event, ...)
    local text = ...
    return suppress(self, event, ...) and OfflineTargetWindow(text) ~= nil
end)

-- Same selective rule for the BN offline notice: hidden from the default
-- chat frames only when a Whispy conversation window shows it instead.
ChatFrame_AddMessageEventFilter("CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE", function(self, event, ...)
    local name = select(2, ...)
    return suppress(self, event, ...) and OfflineBNWindow(name) ~= nil
end)

--=========================================================================
-- Whisper start interception -- open a focused Whispy window when a whisper
-- is STARTED (/w <name>, clicking a name in chat, unit menu -> Whisper),
-- instead of the default chat edit box. All of those routes make the chat
-- edit box enter WHISPER mode, which calls its UpdateHeader method.
--=========================================================================

local prevType, prevTarget

local function OpenFromWhisperStart(editBox, chatType, tellTarget)
    local isBN = (chatType == "BN_WHISPER") or (tellTarget:find("^|K") ~= nil)
    local presenceID, name
    if isBN then
        presenceID = UsableBNetID(nil, tellTarget)
        if not presenceID then return end  -- can't resolve; let default UI handle it
        name = BNName(presenceID, tellTarget)
    else
        name = tellTarget                   -- keep realm suffix for cross-realm sends
    end

    local win = ns.GetWindow({ name = name, isBN = isBN, presenceID = presenceID })
    ns.ShowWindow(win, true)

    -- take the default edit box out of whisper mode and close it
    local ct = editBox:GetAttribute("chatType")
    if ct and ct:find("WHISPER") then
        editBox:SetAttribute("chatType", "SAY")
        editBox:SetAttribute("tellTarget", nil)
        local uh = editBox.UpdateHeader or ChatEdit_UpdateHeader
        if uh then uh(editBox, true) end       -- internal call: ignored by our hook
    end
    if ChatFrameEditBoxMixin and ChatFrameEditBoxMixin.OnEscapePressed then
        ChatFrameEditBoxMixin.OnEscapePressed(editBox)
    elseif ChatEdit_OnEscapePressed then
        ChatEdit_OnEscapePressed(editBox)
    end

    if win:IsShown() then win.editBox:SetFocus() end
end

local function OnUpdateHeader(editBox, internalCall)
    if internalCall then return end         -- our own reset call -- avoid recursion
    if not ns.db or not ns.db.enabled or ns.inCombat then
        prevType, prevTarget = nil, nil
        return                              -- in combat: leave whispers to default UI
    end
    local chatType   = editBox:GetAttribute("chatType")
    local tellTarget = editBox:GetAttribute("tellTarget")
    -- Retail 12.x makes whisper targets "secret values": tainted addon code
    -- (our UpdateHeader hook taints this call stack) may not read, compare, or
    -- concatenate them. When the target is secret we can't identify the
    -- conversation, so reset and let the default whisper edit box handle it.
    -- Checked before anything stores tellTarget, so prevTarget is never secret
    -- and the de-dup comparison below can't throw.
    if IsSecret(tellTarget) then
        prevType, prevTarget = nil, nil
        return
    end
    if chatType ~= "WHISPER" and chatType ~= "BN_WHISPER" then
        prevType, prevTarget = chatType, tellTarget
        return
    end
    if prevType == chatType and prevTarget == tellTarget then return end  -- de-dup
    prevType, prevTarget = chatType, tellTarget
    if not tellTarget or tellTarget == "" then return end
    OpenFromWhisperStart(editBox, chatType, tellTarget)
end

local function HookEditBox(editBox)
    if not editBox or editBox._Whispy_UH_Hooked then return end
    if type(editBox.UpdateHeader) == "function" then
        hooksecurefunc(editBox, "UpdateHeader", OnUpdateHeader)
        editBox._Whispy_UH_Hooked = true
    end
end

if ChatFrameUtil and ChatFrameUtil.ActivateChat then
    -- hook UpdateHeader on each chat edit box as it becomes active
    hooksecurefunc(ChatFrameUtil, "ActivateChat", HookEditBox)
elseif ChatEdit_UpdateHeader then
    hooksecurefunc("ChatEdit_UpdateHeader", OnUpdateHeader)  -- older-client fallback
end

-- Hook edit boxes that already exist at login (in case they were activated
-- before Whispy loaded).
local startHook = CreateFrame("Frame")
startHook:RegisterEvent("PLAYER_LOGIN")
startHook:SetScript("OnEvent", function()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        HookEditBox(_G["ChatFrame" .. i .. "EditBox"])
    end
end)

--=========================================================================
-- Reply keybindings -- the game's REPLY binding ("R" by default) replies to
-- the last whisper received, REPLY2 to the last player you whispered. Both
-- read the reply memory RememberTell mirrors above, put the edit box into
-- whisper mode (the UpdateHeader hook opens the conversation and flips the
-- box back to SAY), then re-activate the now-empty default edit box. After
-- they run, close that box and hand the keyboard to the Whispy window. When
-- the memory is empty (a secret name the mirror had to skip), fall back to
-- the last conversation Whispy itself saw.
--=========================================================================

local function OnReply(last)
    if not ns.db or not ns.db.enabled then return end
    if not last then return end
    local editBox = (ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow())
        or (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())
    if editBox then
        -- The default UI found a target Whispy could not take over (a
        -- secret-named sender it left in the chat frame): the box is in
        -- whisper mode for it -- don't fight that.
        local ct = editBox:GetAttribute("chatType")
        if ct == "WHISPER" or ct == "BN_WHISPER" then return end
        -- Otherwise the box was only re-opened by the reply itself.
        local text = editBox:GetText()
        if not IsSecret(text) and text == "" then
            if ChatFrameEditBoxMixin and ChatFrameEditBoxMixin.OnEscapePressed then
                ChatFrameEditBoxMixin.OnEscapePressed(editBox)
            elseif ChatEdit_OnEscapePressed then
                ChatEdit_OnEscapePressed(editBox)
            end
        end
    end
    local win = ns.GetWindow(last)
    -- "select" so tab mode switches to this conversation's tab. Focus a frame
    -- late: the keypress that fired the binding would otherwise also arrive in
    -- the freshly focused edit box as a typed "r".
    if ns.ShowWindow(win, "select") then
        C_Timer.After(0, function()
            if win:IsVisible() then win.editBox:SetFocus() end
        end)
    end
end

local function HookReply(name, legacyName, getLast)
    local hook = function() OnReply(getLast()) end
    if ChatFrameUtil and type(ChatFrameUtil[name]) == "function" then
        hooksecurefunc(ChatFrameUtil, name, hook)
    elseif type(_G[legacyName]) == "function" then
        hooksecurefunc(legacyName, hook)  -- older-client fallback
    end
end
HookReply("ReplyTell",  "ChatFrame_ReplyTell",  function() return lastIncoming end)
HookReply("ReplyTell2", "ChatFrame_ReplyTell2", function() return lastOutgoing end)

--=========================================================================
-- Whisper mode -- with the game's "whisperMode" CVar on a pop-out setting,
-- the chat manager opens a dedicated chat tab per whisper target before any
-- filter runs, so with Whispy suppressing the text those tabs open empty.
-- Offer to switch to in-line once; the answer is remembered either way.
--=========================================================================
local function CheckWhisperMode()
    if not ns.db or not ns.db.enabled or ns.db.whisperModeAsked then return end
    if not (GetCVar and SetCVar and StaticPopup_Show) then return end
    if GetCVar("whisperMode") == "inline" then return end
    StaticPopupDialogs["WHISPY_WHISPER_MODE"] = {
        text = ns.T("whisperModeText"),
        button1 = ns.T("whisperModeAccept"),
        button2 = ns.T("whisperModeLater"),
        OnAccept = function() SetCVar("whisperMode", "inline") end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    ns.db.whisperModeAsked = true
    StaticPopup_Show("WHISPY_WHISPER_MODE")
end
ns.CheckWhisperMode = CheckWhisperMode

startHook:HookScript("OnEvent", CheckWhisperMode)

--=========================================================================
-- Test helpers -- inject fake whispers locally (nothing is sent to the server)
--=========================================================================

-- Simulate one incoming whisper from `sender`.
function ns.SimulateIncoming(sender, text)
    RouteIncoming({ name = sender, isBN = false }, text, true)
end

-- Simulate one line you "sent" to `target` (display only -- no SendChatMessage).
function ns.SimulateOutgoing(target, text)
    RouteOutgoing({ name = target, isBN = false }, text)
end

-- Play a short scripted, staggered conversation across two windows so you can
-- eyeball the UI, cascading, class colours, and history/replay offline.
function ns.RunTest()
    if not ns.db then return end
    ns.Print(ns.T("demoRunning"))
    local demo = {
        { 0.0, "in",  "Naowh",     "hey, free for a +18 tonight?" },
        { 0.6, "in",  "Mia",       "ty for the run earlier! that trinket carried" },
        { 1.6, "out", "Naowh",     "yeah give me 10 min to repair" },
        { 2.6, "out", "Mia",       "anytime :) ping me if you need another" },
        { 3.4, "in",  "Naowh",     "sweet, sending invite now" },
        { 4.2, "in",  "Naowh",     "you still on your warrior?" },
    }
    for _, m in ipairs(demo) do
        local delay, dir, who, text = m[1], m[2], m[3], m[4]
        C_Timer.After(delay, function()
            if dir == "in" then
                ns.SimulateIncoming(who, text)
            else
                ns.SimulateOutgoing(who, text)
            end
        end)
    end
end
