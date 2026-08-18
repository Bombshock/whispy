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
local function BNName(presenceID, fallback)
    if presenceID and C_BattleNet and C_BattleNet.GetAccountInfoByID then
        local ai = C_BattleNet.GetAccountInfoByID(presenceID)
        if ai then
            if ai.accountName and ai.accountName ~= "" then return ai.accountName end
            if ai.battleTag then return ai.battleTag:match("^(.-)#") or ai.battleTag end
        end
    end
    return fallback or ("BN:" .. tostring(presenceID))
end

--=========================================================================
-- Incoming / outgoing routing (fires once per event)
--=========================================================================

local function Alert(win)
    ns.AlertSound("in", win.info)
    -- ShowWindow keeps the window hidden (and queues it) while in combat.
    if ns.ShowWindow(win) and not win:IsMouseOver() then
        FlashClientIcon()
    end
end

-- Shared routing core. Both the live event handlers and the /whispy test
-- simulator go through these two functions, so there is one code path.

-- info = { name=, isBN=, presenceID=, guid= }
local function RouteIncoming(info, text, alert)
    local win = ns.GetWindow(info)
    win:AddChat("in", info.name, text)
    ns.History:Add(ns.MakeKey(win.info), "in", info.name, text)
    if alert ~= false then Alert(win) end
    -- Still hidden after the alert: combat (or a window the user closed).
    -- Count it so the minimap badge can say something arrived.
    if not win:IsShown() then ns.MarkUnread(win) end
    return win
end

local function RouteOutgoing(info, text)
    local win = ns.GetWindow(info)
    win:AddChat("out", nil, text)
    ns.History:Add(ns.MakeKey(win.info), "out", nil, text)
    ns.AlertSound("out", win.info)
    ns.ShowWindow(win)
    return win
end

local handlers = {}

-- Regular incoming whisper: arg1=text, arg2=author(Name-Realm), arg12=guid
function handlers.CHAT_MSG_WHISPER(...)
    local text, author = ...
    local guid = select(12, ...)
    RouteIncoming({ name = author, isBN = false, guid = guid }, text)
end

-- Regular outgoing whisper you sent: arg1=text, arg2=target, arg12=guid
function handlers.CHAT_MSG_WHISPER_INFORM(...)
    local text, target = ...
    local guid = select(12, ...)
    RouteOutgoing({ name = target, isBN = false, guid = guid }, text)
end

-- BattleNet incoming: arg1=text, arg2=name, arg13=presenceID
function handlers.CHAT_MSG_BN_WHISPER(...)
    local text, author = ...
    local presenceID = select(13, ...)
    RouteIncoming({ name = BNName(presenceID, author), isBN = true, presenceID = presenceID }, text)
end

-- BattleNet outgoing: arg1=text, arg2=target, arg13=presenceID
function handlers.CHAT_MSG_BN_WHISPER_INFORM(...)
    local text = ...
    local presenceID = select(13, ...)
    local name = BNName(presenceID, (select(2, ...)))
    RouteOutgoing({ name = name, isBN = true, presenceID = presenceID }, text)
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

--=========================================================================
-- Event frame (routing) -- runs once per event, independent of chat frames
--=========================================================================
local ef = CreateFrame("Frame")
for event in pairs(handlers) do
    ef:RegisterEvent(event)
end
ef:SetScript("OnEvent", function(_, event, ...)
    if not ns.db or not ns.db.enabled then return end
    local h = handlers[event]
    if h then h(...) end
end)

--=========================================================================
-- Suppression -- hide the default chat copy while Whispy is handling whispers
--=========================================================================
local function suppress()
    return ns.db and ns.db.enabled == true  -- true = block from default chat frames
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
        presenceID = BNet_GetBNetIDAccount and BNet_GetBNetIDAccount(tellTarget) or nil
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
    if issecretvalue and issecretvalue(tellTarget) then
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
