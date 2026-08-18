-- Whispy - Window.lua
-- Modern flat conversation windows (one per conversation) + window manager.

local addonName, ns = ...
local P = ns.P

local HEADER_H = 28
local FOOTER_H = 30

ns.Windows = {}            -- [key] = window frame
local openOrder = {}       -- ordered list of keys for /whispy list
local cascadeStep = 0      -- offsets successive new windows
local winCount = 0         -- monotonic id for unique global frame names
local lastFocusedEB        -- most recently focused Whispy edit box (link routing)

--=========================================================================
-- Conversation key + display helpers
--=========================================================================

-- Canonical player key: always "base-realm", lowercased, realm normalized.
-- This makes "Bob" (from /w, same realm) and "Bob-YourRealm" (from whisper
-- events) resolve to the SAME conversation instead of two windows.
local function CanonName(name)
    if not name or name == "" then return "?" end
    local base, realm = name:match("^(.-)%-(.+)$")
    if not base or base == "" then
        base = name
        realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
    end
    base = base:lower()
    realm = (realm or ""):gsub("[%s'%-]", ""):lower()
    if realm == "" then return base end
    return base .. "-" .. realm
end

-- Build a stable key for a conversation from its descriptor.
local function MakeKey(info)
    if info.isBN then
        return "BN:" .. tostring(info.presenceID or info.name)
    end
    return "W:" .. CanonName(info.name)
end
ns.MakeKey = MakeKey

--=========================================================================
-- Window construction
--=========================================================================

local function PositionNew(win)
    local db = ns.db
    local base = db.lastPos
    win:ClearAllPoints()
    if base then
        win:SetPoint(base.point, UIParent, base.relPoint,
            base.x + cascadeStep * 26, base.y - cascadeStep * 26)
    else
        win:SetPoint("CENTER", UIParent, "CENTER",
            -120 + cascadeStep * 26, 60 - cascadeStep * 26)
    end
    cascadeStep = (cascadeStep + 1) % 6
end

local function SavePos(win)
    local point, _, relPoint, x, y = win:GetPoint()
    ns.db.lastPos = { point = point, relPoint = relPoint, x = x, y = y }
end

--=========================================================================
-- Chat bubbles (WhatsApp-style): mine right + green, theirs left + grey.
--=========================================================================
local BUB_MAXW_FRAC = 0.74   -- max bubble width as fraction of the list width
local BUB_PADX      = 9      -- bubble inner horizontal padding
local BUB_PADY      = 5      -- bubble inner vertical padding
local BUB_GAP       = 6      -- vertical gap between messages
local MSG_PAD       = 8      -- list inset from window edges
local THUMB_W       = 4      -- scrollbar width
local GRIP_W        = 16     -- resize grip, kept clear of the input text

-- A reusable message row: holds both a bubble (in/out) and a centred system
-- line; only one is shown per render. Pooled so windows can re-flow on resize.
local function MakeRowFrame(win)
    local row = CreateFrame("Frame", nil, win.content)

    local bub = CreateFrame("Frame", nil, row, "BackdropTemplate")
    ns.ApplyFlatBg(bub, P.bubIn[1], P.bubIn[2], P.bubIn[3], P.bubIn[4],
                        P.bubIn[1], P.bubIn[2], P.bubIn[3], 0)
    row.bubble = bub

    local text = bub:CreateFontString(nil, "ARTWORK", "ChatFontNormal")
    text:SetTextColor(P.bubTxt[1], P.bubTxt[2], P.bubTxt[3])
    text:SetJustifyH("LEFT")
    text:SetWordWrap(true)
    text:SetPoint("TOPLEFT", bub, "TOPLEFT", BUB_PADX, -BUB_PADY)
    row.text = text

    -- Make item/spell/quest/etc. links in the bubble interactive, like the
    -- default chat: hover shows the tooltip, click routes through SetItemRef
    -- (so shift-click re-links via our router). The bubble is mouse-enabled so
    -- it can detect links, which means it also swallows ordinary clicks and the
    -- wheel -- so both are forwarded by hand to the window and the scroll frame.
    --
    -- Forwarded rather than propagated on purpose: SetPropagateMouseClicks is a
    -- protected method, and these rows are built lazily, so the first whisper
    -- from a new conversation *during combat* would call it from tainted code
    -- and be blocked -- taking the whole window down with it. Nothing here may
    -- assume it runs out of combat.
    bub:EnableMouse(true)
    bub:SetHyperlinksEnabled(true)
    bub:SetScript("OnMouseDown", function()
        local h = win:GetScript("OnMouseDown")
        if h then h(win) end
    end)
    bub:SetScript("OnHyperlinkEnter", function(self, link)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT", 8, 0)
        if pcall(GameTooltip.SetHyperlink, GameTooltip, link) then
            GameTooltip:Show()
        else
            GameTooltip:Hide()
        end
    end)
    bub:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
    bub:SetScript("OnHyperlinkClick", function(self, link, linkText, button)
        row.linkClick = true
        pcall(SetItemRef, link, linkText, button, self)
    end)

    -- Message text is selectable: a read-only edit box is laid over the bubble
    -- so the line can be dragged across and copied (see Copy.lua). Hovering is
    -- enough to arm it, so the first drag already selects -- except on messages
    -- carrying a hyperlink, where the box would swallow the link's tooltip and
    -- click, so those arm on a click instead.
    bub:SetScript("OnEnter", function()
        if not ns.HasLink(row.rawText) then ns.SelectMessage(win, row) end
    end)
    bub:SetScript("OnLeave", function() ns.MaybeEndSelection(win) end)

    -- A click that landed on a hyperlink belongs to the link, not to selection.
    -- The two scripts can fire in either order, so the decision waits one frame.
    bub:SetScript("OnMouseUp", function(_, button)
        C_Timer.After(0, function()
            local onLink = row.linkClick
            row.linkClick = nil
            if onLink or button ~= "LeftButton" then return end
            ns.SelectMessage(win, row)
        end)
    end)
    bub:EnableMouseWheel(true)
    bub:SetScript("OnMouseWheel", function(_, delta)
        local sf = win.scrollFrame
        local h = sf and sf:GetScript("OnMouseWheel")
        if h then h(sf, delta) end
    end)

    local tm = bub:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    tm:SetTextColor(P.bubTime[1], P.bubTime[2], P.bubTime[3])
    tm:SetPoint("BOTTOMRIGHT", bub, "BOTTOMRIGHT", -BUB_PADX, BUB_PADY)
    row.time = tm

    local sys = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    sys:SetTextColor(P.dim[1], P.dim[2], P.dim[3])
    sys:SetPoint("TOP", row, "TOP", 0, 0)
    row.sys = sys

    return row
end

-- Acquire the next pooled row for the current layout pass.
local function AcquireRow(win)
    win.poolUsed = win.poolUsed + 1
    local row = win.pool[win.poolUsed]
    if not row then
        row = MakeRowFrame(win)
        win.pool[win.poolUsed] = row
    end
    row:Show()
    return row
end

-- Render one message at the current stacking offset (win.msgY).
-- dir = "out" (me, right/green) | "in" (them, left/grey) | "system" (centred).
local function RenderMessage(win, dir, text, epoch)
    local content = win.content
    local row = AcquireRow(win)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -win.msgY)
    row:SetWidth(content:GetWidth())

    row.rawText = text

    if dir == "system" then
        row.bubble:Hide()
        row.sys:Show()
        row.sys:SetText(text)
        local h = math.max(12, math.ceil(row.sys:GetStringHeight())) + 2
        row:SetHeight(h)
        win.msgY = win.msgY + h + BUB_GAP
        content:SetHeight(win.msgY)
        return
    end

    row.sys:Hide()
    local bub = row.bubble
    bub:Show()
    local isOut = (dir == "out")
    local bg = isOut and P.bubOut or P.bubIn
    bub:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])

    local fs = row.text
    fs:Show()   -- a recycled row may have been hidden by a selection box
    fs:SetWidth(win.maxTextW)
    fs:SetText(text)
    local naturalW = fs:GetUnboundedStringWidth() or win.maxTextW
    local textW = math.max(8, math.min(math.ceil(naturalW), win.maxTextW))
    fs:SetWidth(textW)
    local textH = math.max(12, math.ceil(fs:GetStringHeight()))

    local tm = row.time
    tm:SetText(ns.Date("%H:%M", epoch))
    local timeW = math.ceil(tm:GetUnboundedStringWidth())
    local timeH = math.max(10, math.ceil(tm:GetStringHeight()))

    local innerW = math.max(textW, timeW)
    fs:SetWidth(innerW)
    bub:SetSize(innerW + BUB_PADX * 2, textH + timeH + BUB_PADY * 2)
    bub:ClearAllPoints()
    if isOut then
        bub:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, 0)
    else
        bub:SetPoint("TOPLEFT", row, "TOPLEFT", 2, 0)
    end

    row:SetHeight(textH + timeH + BUB_PADY * 2)
    win.msgY = win.msgY + row:GetHeight() + BUB_GAP
    content:SetHeight(win.msgY)
end

-- Divider label for a day boundary: "Today" for the current day, else the date.
local function DayLabel(epoch)
    if date("%Y-%m-%d", epoch) == date("%Y-%m-%d") then
        return ns.T("today")
    end
    return ns.Date(ns.T("dateFmt"), epoch)
end

local function CreateWindow(key, info)
    local db = ns.db

    winCount = winCount + 1
    local frameName = "WhispyConvWindow" .. winCount
    local win = CreateFrame("Frame", frameName, UIParent, "BackdropTemplate")
    -- ESC closes the topmost open window (native UISpecialFrames behaviour)
    tinsert(UISpecialFrames, frameName)
    win:SetSize(db.winWidth or 340, db.winHeight or 260)
    win:SetFrameStrata("DIALOG")
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:SetResizable(true)
    if win.SetResizeBounds then win:SetResizeBounds(240, 170, 700, 900) end
    win:SetToplevel(true)   -- auto-raise above sibling windows when clicked
    ns.ApplyFlatBg(win, P.bg[1], P.bg[2], P.bg[3], P.bg[4])
    PositionNew(win)

    win.key = key
    win.info = info

    ------------------------------------------------------------------ header
    local header = CreateFrame("Frame", nil, win, "BackdropTemplate")
    header:SetPoint("TOPLEFT", win, "TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", win, "TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_H)
    ns.ApplyFlatBg(header, P.header[1], P.header[2], P.header[3], P.header[4],
                          P.header[1], P.header[2], P.header[3], 0)
    win.header = header

    -- accent line under header
    local accent = win:CreateTexture(nil, "ARTWORK")
    accent:SetHeight(1)
    accent:SetColorTexture(P.accent[1], P.accent[2], P.accent[3], 0.55)
    accent:SetPoint("TOPLEFT", win, "TOPLEFT", 1, -(HEADER_H + 1))
    accent:SetPoint("TOPRIGHT", win, "TOPRIGHT", -1, -(HEADER_H + 1))

    -- source icon -- class portrait for in-game characters, Battle.net client
    -- icon for BN contacts. Filled in by UpdateHeader once info is known.
    local icon = header:CreateTexture(nil, "OVERLAY")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", header, "LEFT", 8, 0)
    icon:SetTexture("Interface/Buttons/WHITE8X8")
    icon:SetVertexColor(P.accent[1], P.accent[2], P.accent[3], 1)
    win.icon = icon

    -- title (conversation name, class coloured if known)
    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    title:SetJustifyH("LEFT")
    win.title = title

    -- close button
    local close = CreateFrame("Button", nil, header)
    close:SetSize(26, HEADER_H)
    close:SetPoint("RIGHT", header, "RIGHT", -2, 0)
    local closeLbl = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeLbl:SetAllPoints()
    closeLbl:SetJustifyH("CENTER")
    closeLbl:SetText("|cff777799x|r")
    close:SetScript("OnEnter", function() closeLbl:SetText("|cffee6666x|r") end)
    close:SetScript("OnLeave", function() closeLbl:SetText("|cff777799x|r") end)
    close:SetScript("OnClick", function() win:Hide() end)

    -- keep the title from running under the close button
    title:SetPoint("RIGHT", close, "LEFT", -4, 0)
    title:SetWordWrap(false)

    -- drag via header
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnMouseDown", function() win:Raise() end)
    header:SetScript("OnDragStart", function()
        win:Raise()
        win:StartMoving()
    end)
    header:SetScript("OnDragStop", function()
        win:StopMovingOrSizing()
        SavePos(win)
    end)

    ------------------------------------------------------------------ footer
    local footer = CreateFrame("Frame", nil, win, "BackdropTemplate")
    footer:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 1, 1)
    footer:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -1, 1)
    footer:SetHeight(FOOTER_H)
    ns.ApplyFlatBg(footer, P.footer[1], P.footer[2], P.footer[3], P.footer[4],
                          P.footer[1], P.footer[2], P.footer[3], 0)

    local footerLine = win:CreateTexture(nil, "ARTWORK")
    footerLine:SetHeight(1)
    footerLine:SetColorTexture(P.sep[1], P.sep[2], P.sep[3], P.sep[4])
    footerLine:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 1, FOOTER_H + 1)
    footerLine:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -1, FOOTER_H + 1)

    -- edit box (styled) -- spans the full window width
    local ebHolder = CreateFrame("Frame", nil, footer, "BackdropTemplate")
    ebHolder:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
    ebHolder:SetPoint("BOTTOMRIGHT", footer, "BOTTOMRIGHT", 0, 0)
    ns.ApplyFlatBg(ebHolder, 0.10, 0.10, 0.15, 1, P.sep[1], P.sep[2], P.sep[3], 1)

    local eb = CreateFrame("EditBox", nil, ebHolder)
    eb:SetPoint("LEFT", ebHolder, "LEFT", 7, 0)
    eb:SetPoint("RIGHT", ebHolder, "RIGHT", -(7 + GRIP_W), 0)
    eb:SetHeight(FOOTER_H - 8)
    eb:SetAutoFocus(false)
    eb:SetFontObject("ChatFontNormal")
    eb:SetTextColor(P.text[1], P.text[2], P.text[3])
    eb:SetMaxLetters(255)
    eb:SetTextInsets(0, 0, 0, 0)
    win.editBox = eb

    -- placeholder text
    local ph = ebHolder:CreateFontString(nil, "ARTWORK", "ChatFontNormal")
    ph:SetPoint("LEFT", ebHolder, "LEFT", 7, 0)
    ph:SetTextColor(P.dim[1], P.dim[2], P.dim[3])
    ph:SetText(ns.T("typeHint"))
    local function UpdatePlaceholder()
        ph:SetShown(eb:GetText() == "" and not eb:HasFocus())
    end
    eb:SetScript("OnEditFocusGained", function()
        lastFocusedEB = eb          -- remember for shift-click link routing
        UpdatePlaceholder()
    end)
    eb:SetScript("OnEditFocusLost", UpdatePlaceholder)
    eb:SetScript("OnTextChanged", UpdatePlaceholder)
    UpdatePlaceholder()

    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        if text and text:gsub("%s", "") ~= "" then
            ns.SendFromWindow(win, text)
        end
        self:SetText("")
        -- keep focus so you can keep typing; Escape unfocuses
    end)

    ------------------------------------------------------ message scroll area
    local LIST_TOP = HEADER_H + 6
    local scrollFrame = CreateFrame("ScrollFrame", nil, win)
    scrollFrame:SetPoint("TOPLEFT", win, "TOPLEFT", MSG_PAD, -LIST_TOP)
    scrollFrame:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -(MSG_PAD + THUMB_W), FOOTER_H + 6)
    scrollFrame:EnableMouseWheel(true)
    win.scrollFrame = scrollFrame

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)
    win.content = content
    win.msgY = 0
    win.lastDay = nil   -- day-key of the last message added (for date dividers)
    win.pool = {}       -- reusable row frames
    win.poolUsed = 0    -- rows used in the current layout
    win.messages = {}   -- recorded messages { dir, text, epoch } for re-flow

    -- content width derived from the fixed window size
    local contentW = (win:GetWidth() or 340) - MSG_PAD - (MSG_PAD + THUMB_W)
    content:SetWidth(contentW)
    win.maxTextW = math.floor(contentW * BUB_MAXW_FRAC) - BUB_PADX * 2

    -- thin scrollbar (track + proportional thumb)
    local track = CreateFrame("Frame", nil, win, "BackdropTemplate")
    track:SetWidth(THUMB_W)
    track:SetPoint("TOPRIGHT", win, "TOPRIGHT", -3, -LIST_TOP)
    track:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -3, FOOTER_H + 6)
    ns.ApplyFlatBg(track, 0.10, 0.10, 0.15, 0.6, 0, 0, 0, 0)
    local thumb = CreateFrame("Frame", nil, track, "BackdropTemplate")
    thumb:SetWidth(THUMB_W)
    ns.ApplyFlatBg(thumb, P.border[1], P.border[2], P.border[3], 1, 0, 0, 0, 0)
    thumb:Hide()
    win.track, win.thumb = track, thumb

    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local range = math.max(0, content:GetHeight() - self:GetHeight())
        local new = math.max(0, math.min(range, self:GetVerticalScroll() - delta * 40))
        self:SetVerticalScroll(new)
        win:UpdateThumb()
    end)
    scrollFrame:SetScript("OnScrollRangeChanged", function() win:UpdateThumb() end)

    -- Clicking the body only raises the window: clicks on the message list
    -- belong to text selection now, so they must not pull focus into the
    -- input. Clicking the input strip still focuses it.
    win:SetScript("OnMouseDown", function() win:Raise() end)
    ebHolder:EnableMouse(true)
    ebHolder:SetScript("OnMouseDown", function()
        win:Raise()
        eb:SetFocus()
    end)

    -- resize grip (bottom-right)
    local grip = CreateFrame("Button", nil, win)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -1, 1)
    -- the grip sits inside the footer, so it has to outrank the input backdrop
    -- or the edit box paints over it and swallows the clicks
    grip:SetFrameLevel(ebHolder:GetFrameLevel() + 2)
    grip:SetNormalTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function()
        win:Raise()
        win:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        win:StopMovingOrSizing()
        ns.db.winWidth = win:GetWidth()
        ns.db.winHeight = win:GetHeight()
    end)

    -- re-flow bubbles whenever the window width changes
    win:SetScript("OnSizeChanged", function(self)
        if self.content and self.messages then self:Relayout() end
    end)

    ------------------------------------------------------------------ methods

    -- Update the header title / class colour from current info.
    function win:UpdateHeader()
        local disp = ns.ShortName(self.info.name)
        local cc = self.info.isBN and nil or ns.ClassColorFromGUID(self.info.guid, self.info.class)
        ns.SetSourceIcon(self.icon, self.info)
        if cc then
            self.title:SetText(cc:WrapTextInColorCode(disp))
        elseif self.info.isBN then
            self.title:SetText(ns.Hex(0.32, 0.68, 1.00) .. disp .. "|r")
        else
            self.title:SetText(ns.Hex(P.text[1], P.text[2], P.text[3]) .. disp .. "|r")
        end
    end

    -- Recompute thumb size/position from content vs viewport.
    function win:UpdateThumb()
        local sf, c = self.scrollFrame, self.content
        local viewH, contentH = sf:GetHeight(), c:GetHeight()
        if viewH <= 0 or contentH <= viewH then self.thumb:Hide(); return end
        self.thumb:Show()
        local trackH = self.track:GetHeight()
        local th = math.max(20, trackH * (viewH / contentH))
        self.thumb:SetHeight(th)
        local range = contentH - viewH
        local frac = range > 0 and (sf:GetVerticalScroll() / range) or 0
        self.thumb:ClearAllPoints()
        self.thumb:SetPoint("TOP", self.track, "TOP", 0, -frac * (trackH - th))
    end

    function win:ScrollToBottom()
        local sf, c = self.scrollFrame, self.content
        sf:SetVerticalScroll(math.max(0, c:GetHeight() - sf:GetHeight()))
        self:UpdateThumb()
    end

    -- Insert a centred date divider if this message crosses into a new day.
    function win:MaybeDateDivider(epoch)
        local dayKey = date("%Y-%m-%d", epoch)
        if dayKey ~= self.lastDay then
            self.lastDay = dayKey
            RenderMessage(self, "system", DayLabel(epoch), epoch)
        end
    end

    -- Append one message bubble. dir = "in"|"out"|"system".
    function win:AddChat(dir, who, text, epoch)
        epoch = epoch or time()
        self.messages[#self.messages + 1] = { dir = dir, text = text, epoch = epoch }
        self:MaybeDateDivider(epoch)
        RenderMessage(self, dir, text, epoch)
        self:ScrollToBottom()
    end

    -- Replay stored history into a freshly opened window.
    function win:ReplayHistory()
        local recent = ns.History:GetRecent(self.key, ns.db.replayLimit or 30)
        if #recent == 0 then return end
        for _, e in ipairs(recent) do
            self.messages[#self.messages + 1] = { dir = e.dir, text = e.text, epoch = e.t }
            self:MaybeDateDivider(e.t)
            RenderMessage(self, e.dir, e.text, e.t)
        end
        self:ScrollToBottom()
    end

    -- Throw away everything rendered and replay the stored history from
    -- scratch (used when the underlying history table is swapped out).
    function win:Reload()
        ns.EndSelection(self)   -- rows are about to be re-used underneath it
        wipe(self.messages)
        self.poolUsed = 0
        self.msgY     = 0
        self.lastDay  = nil
        self.content:SetHeight(1)
        self:ReplayHistory()
        for i = self.poolUsed + 1, #self.pool do self.pool[i]:Hide() end
        self:ScrollToBottom()
    end

    -- Re-flow all messages for the current window width (called on resize).
    function win:Relayout()
        ns.EndSelection(self)   -- bubbles move; the overlay would be stranded
        local sfW = self.scrollFrame:GetWidth()
        if sfW and sfW > 0 then self.content:SetWidth(sfW) end
        self.maxTextW = math.floor(self.content:GetWidth() * BUB_MAXW_FRAC) - BUB_PADX * 2
        self.poolUsed = 0
        self.msgY = 0
        self.lastDay = nil
        for _, m in ipairs(self.messages) do
            self:MaybeDateDivider(m.epoch)
            RenderMessage(self, m.dir, m.text, m.epoch)
        end
        for i = self.poolUsed + 1, #self.pool do self.pool[i]:Hide() end
        self:ScrollToBottom()
    end

    -- Becoming visible is what counts as "read" -- this covers every route a
    -- window can open by (alert, chat list, combat restore, /whispy <name>).
    win:SetScript("OnShow", function(self)
        self:ScrollToBottom()
        ns.ClearUnread(self.key)
    end)

    win:UpdateHeader()
    win:ReplayHistory()
    win:Hide()  -- created hidden; visibility is controlled via ns.ShowWindow
    return win
end

--=========================================================================
-- Window manager
--=========================================================================

-- Get (or create) the window for a conversation descriptor.
-- info = { name=, isBN=, presenceID=, guid= }
function ns.GetWindow(info)
    local key = MakeKey(info)
    local win = ns.Windows[key]
    if not win then
        win = CreateWindow(key, info)
        ns.Windows[key] = win
        openOrder[#openOrder + 1] = key
    else
        -- refresh descriptor details we may have learned (guid, presenceID)
        if info.guid and info.guid ~= "" then win.info.guid = info.guid end
        if info.presenceID then win.info.presenceID = info.presenceID end
        if info.name then win.info.name = info.name end
        if info.class then win.info.class = info.class end
        win:UpdateHeader()
    end

    -- persist identity so the chat list can show/reopen it after a reload
    if ns.db.meta then
        local m = ns.db.meta[key] or {}
        m.name = win.info.name or m.name
        m.isBN = win.info.isBN or m.isBN
        if win.info.presenceID then m.presenceID = win.info.presenceID end
        if win.info.guid and win.info.guid ~= "" then m.guid = win.info.guid end
        if win.info.class then m.class = win.info.class end
        ns.db.meta[key] = m
    end
    return win
end

--=========================================================================
-- Unread tracking -- whispers that landed while their window was not on
-- screen (normally because we were in combat). Drives the minimap badge.
--
-- Deliberately session-only: an unread counter that survives a /reload is
-- noise, not information.
--=========================================================================
ns.unread = {}        -- [key] = number of unseen incoming lines
ns.unreadTotal = 0

local function BadgeChanged()
    -- ChatList.lua owns the visuals and may not have built the button yet.
    if ns.UpdateMinimapBadge then ns.UpdateMinimapBadge() end
end

function ns.MarkUnread(win)
    ns.unread[win.key] = (ns.unread[win.key] or 0) + 1
    ns.unreadTotal = ns.unreadTotal + 1
    BadgeChanged()
end

function ns.ClearUnread(key)
    local n = ns.unread[key]
    if not n then return end
    ns.unread[key] = nil
    ns.unreadTotal = math.max(0, ns.unreadTotal - n)
    BadgeChanged()
end

--=========================================================================
-- Combat auto-hide -- windows are hidden during combat and restored after.
--=========================================================================
local combatRestore = {}   -- [key] = true : windows to re-show when combat ends

-- Mark a window to be shown once combat ends (used while in combat).
function ns.QueueCombatRestore(win)
    combatRestore[win.key] = true
end

-- Show a window, unless we are in combat -- then queue it for after combat.
-- Returns true if actually shown now.
function ns.ShowWindow(win, focus)
    if ns.inCombat then
        ns.QueueCombatRestore(win)
        return false
    end
    if not win:IsShown() then win:Show() end
    win:Raise()
    if focus then win.editBox:SetFocus() end
    return true
end

local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        ns.inCombat = true
        for key, win in pairs(ns.Windows) do
            if win:IsShown() then
                combatRestore[key] = true
                win:Hide()
            end
        end
    else -- PLAYER_REGEN_ENABLED
        ns.inCombat = false
        for key in pairs(combatRestore) do
            local win = ns.Windows[key]
            if win then win:Show() end
        end
        wipe(combatRestore)
    end
end)

-- Hide every conversation window (and drop any pending combat restores).
function ns.HideAllWindows()
    for _, win in pairs(ns.Windows) do win:Hide() end
    wipe(combatRestore)
end

-- Re-read stored history into every existing window.
function ns.ReloadAllWindows()
    for _, win in pairs(ns.Windows) do win:Reload() end
end

-- A Battle.net contact can switch games (or log off) mid-conversation, so keep
-- the header icon of open BN windows in step with their presence.
local bnWatch = CreateFrame("Frame")
bnWatch:RegisterEvent("BN_FRIEND_INFO_CHANGED")
bnWatch:SetScript("OnEvent", function()
    for _, win in pairs(ns.Windows) do
        if win.info.isBN then win:UpdateHeader() end
    end
end)

-- Open a conversation by typed name (regular whisper target).
function ns.OpenConversation(target)
    if not target or target == "" then return end
    local win = ns.GetWindow({ name = target, isBN = false })
    if not ns.ShowWindow(win, true) then
        ns.Print(ns.T("combatDefer", ns.ShortName(target)))
    end
end

function ns.ListWindows()
    local n = 0
    for _, key in ipairs(openOrder) do
        local win = ns.Windows[key]
        if win and win:IsShown() then
            n = n + 1
            ns.Print("  " .. ns.ShortName(win.info.name))
        end
    end
    if n == 0 then ns.Print(ns.T("noOpenConvos")) end
end

--=========================================================================
-- Shift-click item linking -- drop item/spell/quest/achievement/etc. links
-- into a Whispy edit box, exactly like the default chat frame. Works from
-- anywhere you can shift-click: bags, character window, bank, merchant, mail,
-- tooltips, quest log, profession windows, ... -- all of which route through
-- HandleModifiedItemClick, which in retail 12.x calls ChatFrameUtil.InsertLink
-- (the old ChatEdit_InsertLink is now only a deprecated alias that nothing
-- internal calls -- which is why hooking it did nothing).
--
-- So we wrap ChatFrameUtil.InsertLink itself (falling back to the legacy
-- global on older clients). Target selection, in order:
--   1. A Whispy box with keyboard focus (you're actively typing) always wins.
--   2. Otherwise let the game handle its own contexts -- default chat edit box,
--      macro editor, profession/auction search, communities, ... -- by calling
--      the original.
--   3. If nothing there claimed the link, drop it into the Whispy window you
--      used most recently (if still open). This is what lets you shift-click a
--      bag or character item with a conversation open but not focused, without
--      ever stealing a link one of the game's own frames wanted.
--
-- InsertLink is insecure (no taint concern) and we must *return* true to stop
-- Blizzard's fallback from also inserting elsewhere, so we can't use
-- hooksecurefunc -- we capture the original and call through.
--=========================================================================

-- The edit box of the Whispy window that currently has keyboard focus, or nil.
local function FocusedWhispyEditBox()
    for _, win in pairs(ns.Windows) do
        local eb = win.editBox
        if eb and eb:IsShown() and eb:HasFocus() then
            return eb
        end
    end
    return nil
end
ns.FocusedWhispyEditBox = FocusedWhispyEditBox

-- Install the link router by wrapping the game's link-insertion function.
-- Deferred to PLAYER_LOGIN so the target exists regardless of addon load order
-- (Blizzard's chat code lives in its own addon that may load after us).
local function InstallLinkRouter()
    local host, field
    if type(ChatFrameUtil) == "table" and type(ChatFrameUtil.InsertLink) == "function" then
        host, field = ChatFrameUtil, "InsertLink"        -- retail 12.x
    elseif type(ChatEdit_InsertLink) == "function" then
        host, field = _G, "ChatEdit_InsertLink"          -- legacy fallback
    else
        return
    end
    if host[field] == ns._linkRouter then return end     -- already installed

    local original = host[field]
    local function router(text, ...)
        if text then
            -- 1) A Whispy box you're typing in always wins.
            local eb = FocusedWhispyEditBox()
            if eb then
                eb:Insert(text)
                eb:SetFocus()   -- keep typing / hit Enter to send
                return true
            end
            -- 2) Let the game route to its own edit boxes / search fields first.
            if original(text, ...) then
                return true
            end
            -- 3) Nobody else took it: hand it to the last Whispy window we used.
            if lastFocusedEB and lastFocusedEB:IsVisible() then
                lastFocusedEB:Insert(text)
                lastFocusedEB:SetFocus()
                return true
            end
            return false
        end
        return original(text, ...)
    end

    ns._linkRouter = router
    host[field] = router
    -- Keep the deprecated global alias pointing at the live router as well, so
    -- any older code that still calls ChatEdit_InsertLink benefits too.
    if host == ChatFrameUtil and type(ChatEdit_InsertLink) == "function" then
        ChatEdit_InsertLink = router
    end
end

local linkInstaller = CreateFrame("Frame")
linkInstaller:RegisterEvent("PLAYER_LOGIN")
linkInstaller:SetScript("OnEvent", InstallLinkRouter)

-- Open a conversation from a stored key (used by the minimap chat lists).
function ns.OpenFromKey(key)
    local m = ns.db.meta and ns.db.meta[key]
    local info
    if m then
        info = { name = m.name, isBN = m.isBN, presenceID = m.presenceID,
                 guid = m.guid, class = m.class }
    else
        info = { name = key:gsub("^W:", ""), isBN = key:sub(1, 3) == "BN:" }
    end
    local win = ns.GetWindow(info)
    ns.ShowWindow(win, true)
end
