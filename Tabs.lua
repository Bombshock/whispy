-- Whispy - Tabs.lua
-- Tab mode: every conversation lives in ONE shared window, with a strip of
-- tabs on top switching between them.
--
-- The per-conversation windows from Window.lua are reused whole: in tab mode
-- a window is re-parented into the host and anchored to fill it below the
-- strip, and only the active tab's window is shown. That keeps the header,
-- bubbles, text selection, link handling, and per-conversation input drafts
-- working unchanged -- switching tabs never loses a half-typed message.
-- Window.lua redirects a tabbed window's drag/resize/close to the host via
-- the win.isTab flag.

local addonName, ns = ...
local P = ns.P

local TAB_H      = 28    -- tab strip height (the window body hangs below it)
local TAB_MIN    = 72    -- tabs shrink to this before the strip overflows
local TAB_MAX    = 170
local TAB_GAP    = 1     -- strip background showing between tabs
local STRIP_PAD  = 3     -- strip inset left/right
local OVERFLOW_W = 20    -- the >> button
local BURGER_W   = 20    -- character-menu button in the strip
local CLOSE_W    = 14    -- window-close button in the strip
local BADGE_H    = 13    -- per-tab unread badge (matches the minimap badge)

local host                -- the shared window (created lazily)
local tabOrder = {}       -- ordered conversation keys with an open tab
local activeKey           -- key of the conversation currently displayed
local firstVis = 1        -- first visible tab once they overflow the strip

local LayoutTabs, ActivateTab, EnsureHost   -- forward declarations

local function IndexOf(key)
    for i, k in ipairs(tabOrder) do
        if k == key then return i end
    end
    return nil
end

-- Name coloured the same way the window header and chat list colour it.
local function ColoredName(info)
    local disp = ns.ShortName(info.name)
    local cc = (not info.isBN) and ns.ClassColorFromGUID(info.guid, info.class) or nil
    if cc then return cc:WrapTextInColorCode(disp) end
    if info.isBN then return ns.Hex(0.32, 0.68, 1.00) .. disp .. "|r" end
    return ns.Hex(P.text[1], P.text[2], P.text[3]) .. disp .. "|r"
end

--=========================================================================
-- Attaching / detaching conversation windows
--=========================================================================

-- Put a conversation window inside the host, filling it below the strip. Its
-- own header is dropped -- the active tab already names the conversation, and
-- the strip carries the burger and close buttons instead.
local function AttachWin(win)
    if win.isTab then return end
    win.isTab = true
    win:SetToplevel(false)          -- the host raises as one unit
    win:SetParent(host)
    win:SetFrameStrata("DIALOG")    -- SetParent resets the strata
    win:ClearAllPoints()
    win:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -(TAB_H + 1))
    win:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    win:SetTabChrome(true)
end

-- Give a window back its life as a floating window.
local function DetachWin(win)
    if not win.isTab then return end
    win.isTab = nil
    win:SetParent(UIParent)
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:ClearAllPoints()
    win:SetSize(ns.db.winWidth or 340, ns.db.winHeight or 260)
    win:SetTabChrome(false)
    ns.PositionNewWindow(win)
end
ns.DetachTabWindow = DetachWin

--=========================================================================
-- Host position / size persistence (kept apart from the floating windows'
-- lastPos/winWidth, so flipping modes never fights over either)
--=========================================================================

function ns.SaveTabHostPos()
    if not host then return end
    local point, _, relPoint, x, y = host:GetPoint()
    ns.db.tabPos = { point = point, relPoint = relPoint, x = x, y = y }
end

function ns.SaveTabHostSize()
    if not host then return end
    ns.db.tabWidth, ns.db.tabHeight = host:GetWidth(), host:GetHeight()
end

--=========================================================================
-- Tab cycling (mouse wheel over the strip)
--=========================================================================

local function CycleTab(dir)
    local n = #tabOrder
    if n < 2 or not activeKey then return end
    local i = IndexOf(activeKey) or 1
    ActivateTab(tabOrder[(i - 1 + dir) % n + 1])
end

--=========================================================================
-- Overflow menu -- lists every open tab when the strip runs out of room
--=========================================================================

local ofMenu
local OF_ROW_H = 20
local OF_W     = 170

local function EnsureOverflowMenu()
    if ofMenu then return ofMenu end
    ofMenu = CreateFrame("Frame", "WhispyTabOverflow", UIParent, "BackdropTemplate")
    ofMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    ns.ApplyFlatBg(ofMenu, P.bg[1], P.bg[2], P.bg[3], 0.98)
    ofMenu.rows = {}
    ofMenu:Hide()
    tinsert(UISpecialFrames, "WhispyTabOverflow")

    -- same dismissal rule as the minimap flyouts
    ofMenu:SetScript("OnShow", function(self) self.outside = 0 end)
    ofMenu:SetScript("OnUpdate", function(self, e)
        if self:IsMouseOver() or (host and host.overflow:IsMouseOver()) then
            self.outside = 0
        else
            self.outside = (self.outside or 0) + e
            if self.outside >= 0.5 then self:Hide() end
        end
    end)
    return ofMenu
end

local function BuildOverflowMenu()
    EnsureOverflowMenu()
    for i, key in ipairs(tabOrder) do
        local row = ofMenu.rows[i]
        if not row then
            row = CreateFrame("Button", nil, ofMenu)
            row:SetHeight(OF_ROW_H)
            row:SetPoint("TOPLEFT", ofMenu, "TOPLEFT", 2, -(2 + (i - 1) * OF_ROW_H))
            row:SetPoint("TOPRIGHT", ofMenu, "TOPRIGHT", -2, -(2 + (i - 1) * OF_ROW_H))
            row:SetHighlightTexture("Interface/Buttons/WHITE8X8")
            row:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)

            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("LEFT", row, "LEFT", 8, 0)
            fs:SetPoint("RIGHT", row, "RIGHT", -26, 0)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            row.label = fs

            local unread = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            unread:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            unread:SetTextColor(P.badgeEd[1], P.badgeEd[2], P.badgeEd[3])
            row.unread = unread

            row:SetScript("OnClick", function(self)
                ofMenu:Hide()
                local win = self.key and ns.Windows[self.key]
                if win then ns.ShowWindow(win, true) end
            end)
            ofMenu.rows[i] = row
        end
        row.key = key
        local win = ns.Windows[key]
        row.label:SetText(win and ColoredName(win.info) or "?")
        local n = ns.unread[key]
        row.unread:SetText((n and n > 0) and tostring(n) or "")
        row:Show()
    end
    for i = #tabOrder + 1, #ofMenu.rows do ofMenu.rows[i]:Hide() end
    ofMenu:SetSize(OF_W, #tabOrder * OF_ROW_H + 4)
end

local function ToggleOverflowMenu()
    EnsureOverflowMenu()
    if ofMenu:IsShown() then ofMenu:Hide(); return end
    BuildOverflowMenu()
    ofMenu:ClearAllPoints()
    ofMenu:SetPoint("TOPRIGHT", host.overflow, "BOTTOMRIGHT", 0, -2)
    ofMenu:Show()
    ofMenu:Raise()
end

--=========================================================================
-- Tab buttons
--=========================================================================

-- A tab's right edge holds either the close x or the unread badge. The x is
-- always up on the active tab and revealed on hover elsewhere (so it can't be
-- hit by accident while switching); the badge yields while the x is up.
local function UpdateTabRight(tab)
    local showClose = tab.isActive or tab:IsMouseOver()
    tab.close:SetShown(showClose)
    local badge = tab.badge
    if tab.hasUnread and not showClose then
        badge:Show()
        if not badge.pulse:IsPlaying() then badge.pulse:Play() end
    else
        badge.pulse:Stop()
        badge:SetAlpha(1)
        badge:Hide()
    end
end

local function MakeTab()
    local strip = host.strip
    local tab = CreateFrame("Button", nil, strip, "BackdropTemplate")
    tab:SetHeight(TAB_H)
    tab:RegisterForClicks("LeftButtonUp", "MiddleButtonUp")
    tab:RegisterForDrag("LeftButton")     -- the strip doubles as a drag handle
    ns.ApplyFlatBg(tab, P.tabBg[1], P.tabBg[2], P.tabBg[3], P.tabBg[4], 0, 0, 0, 0)

    -- accent line marking the active tab
    local accent = tab:CreateTexture(nil, "OVERLAY")
    accent:SetHeight(2)
    accent:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, 0)
    accent:SetPoint("TOPRIGHT", tab, "TOPRIGHT", 0, 0)
    accent:SetColorTexture(P.accent[1], P.accent[2], P.accent[3], 0.9)
    tab.accent = accent

    -- source icon (class portrait / Battle.net client), since the window
    -- header that used to carry it is hidden in tab mode
    local icon = tab:CreateTexture(nil, "OVERLAY")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", tab, "LEFT", 5, 0)
    tab.icon = icon

    local label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    label:SetPoint("RIGHT", tab, "RIGHT", -16, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    tab.label = label

    -- close x (see UpdateTabRight for when it shows; middle-click closes too)
    local close = CreateFrame("Button", nil, tab)
    close:SetSize(14, TAB_H)
    close:SetPoint("RIGHT", tab, "RIGHT", -2, 0)
    close:SetFrameLevel(tab:GetFrameLevel() + 2)
    local cl = close:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cl:SetAllPoints()
    cl:SetJustifyH("CENTER")
    cl:SetText("|cff777799x|r")
    close:SetScript("OnEnter", function() cl:SetText("|cffee6666x|r") end)
    close:SetScript("OnLeave", function()
        cl:SetText("|cff777799x|r")
        if tab:IsMouseOver() then return end   -- back onto the tab body
        UpdateTabRight(tab)
        local bg = (tab.key == activeKey) and P.header or P.tabBg
        tab:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    end)
    close:SetScript("OnClick", function()
        local win = tab.key and ns.Windows[tab.key]
        if win then ns.CloseTab(win) end
    end)
    tab.close = close

    -- unread badge on background tabs, pulsing like the minimap one
    local badge = CreateFrame("Frame", nil, tab, "BackdropTemplate")
    badge:SetFrameLevel(tab:GetFrameLevel() + 2)
    badge:SetSize(14, BADGE_H)
    badge:SetPoint("RIGHT", tab, "RIGHT", -3, 0)
    badge:EnableMouse(false)      -- clicks belong to the tab underneath
    ns.ApplyFlatBg(badge, P.badge[1], P.badge[2], P.badge[3], P.badge[4],
                          P.badgeEd[1], P.badgeEd[2], P.badgeEd[3], P.badgeEd[4])
    local count = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    count:SetPoint("CENTER", badge, "CENTER", 0, 0)
    count:SetTextColor(1, 1, 1)
    badge.count = count
    local pulse = badge:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.35)
    fade:SetDuration(0.8)
    badge.pulse = pulse
    badge:Hide()
    tab.badge = badge

    tab:SetScript("OnClick", function(self, button)
        local win = self.key and ns.Windows[self.key]
        if not win then return end
        if button == "MiddleButton" then
            ns.CloseTab(win)
        else
            ns.ShowWindow(win, true)
        end
    end)
    tab:SetScript("OnDragStart", function()
        host:Raise()
        host:StartMoving()
    end)
    tab:SetScript("OnDragStop", function()
        host:StopMovingOrSizing()
        ns.SaveTabHostPos()
    end)
    tab:SetScript("OnEnter", function(self)
        if self.key ~= activeKey then
            self:SetBackdropColor(P.btnBg[1], P.btnBg[2], P.btnBg[3], P.btnBg[4])
        end
        UpdateTabRight(self)
        local win = self.key and ns.Windows[self.key]
        if win then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(ns.ShortName(win.info.name), 1, 1, 1)
            GameTooltip:AddLine(ns.T("tipTabClose"))
            GameTooltip:Show()
        end
    end)
    tab:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        if self:IsMouseOver() then return end   -- moved onto the close x
        UpdateTabRight(self)
        local bg = (self.key == activeKey) and P.header or P.tabBg
        self:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    end)
    tab:EnableMouseWheel(true)
    tab:SetScript("OnMouseWheel", function(_, delta)
        CycleTab(delta > 0 and -1 or 1)
    end)
    return tab
end

--=========================================================================
-- The host window
--=========================================================================

function EnsureHost()
    if host then return host end
    local db = ns.db
    host = CreateFrame("Frame", "WhispyTabHost", UIParent, "BackdropTemplate")
    ns.TabHost = host
    tinsert(UISpecialFrames, "WhispyTabHost")
    host:SetFrameStrata("DIALOG")
    host:SetClampedToScreen(true)
    host:EnableMouse(true)
    host:SetMovable(true)
    host:SetResizable(true)
    host:SetToplevel(true)
    if host.SetResizeBounds then
        host:SetResizeBounds(240, 170 + TAB_H, 700, 900 + TAB_H)
    end
    host:SetSize(db.tabWidth or db.winWidth or 340,
                 db.tabHeight or ((db.winHeight or 260) + TAB_H))
    ns.ApplyFlatBg(host, P.bg[1], P.bg[2], P.bg[3], P.bg[4])
    local pos = db.tabPos or db.lastPos
    if pos then
        host:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        host:SetPoint("CENTER", UIParent, "CENTER", -120, 60)
    end

    -- the strip behind the tabs
    local strip = CreateFrame("Frame", nil, host, "BackdropTemplate")
    strip:SetPoint("TOPLEFT", host, "TOPLEFT", 1, -1)
    strip:SetPoint("TOPRIGHT", host, "TOPRIGHT", -1, -1)
    strip:SetHeight(TAB_H)
    ns.ApplyFlatBg(strip, P.tabStrip[1], P.tabStrip[2], P.tabStrip[3], P.tabStrip[4],
                          P.tabStrip[1], P.tabStrip[2], P.tabStrip[3], 0)
    strip:EnableMouse(true)
    strip:RegisterForDrag("LeftButton")
    strip:SetScript("OnMouseDown", function() host:Raise() end)
    strip:SetScript("OnDragStart", function()
        host:Raise()
        host:StartMoving()
    end)
    strip:SetScript("OnDragStop", function()
        host:StopMovingOrSizing()
        ns.SaveTabHostPos()
    end)
    strip:EnableMouseWheel(true)
    strip:SetScript("OnMouseWheel", function(_, delta)
        CycleTab(delta > 0 and -1 or 1)
    end)
    host.strip = strip
    host.tabs = {}

    -- hidden measuring string for natural tab widths
    local measure = strip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    measure:Hide()
    host.measure = measure

    -- close button -- hides the whole tab window (tabs survive, like ESC)
    local close = CreateFrame("Button", nil, strip)
    close:SetSize(CLOSE_W, TAB_H)
    close:SetPoint("RIGHT", strip, "RIGHT", -4, 0)
    close:SetFrameLevel(strip:GetFrameLevel() + 3)
    local closeLbl = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeLbl:SetAllPoints()
    closeLbl:SetJustifyH("CENTER")
    closeLbl:SetText("|cff777799x|r")
    close:SetScript("OnEnter", function() closeLbl:SetText("|cffee6666x|r") end)
    close:SetScript("OnLeave", function() closeLbl:SetText("|cff777799x|r") end)
    close:SetScript("OnClick", function() host:Hide() end)
    host.closeBtn = close

    -- burger button -- the character menu for the ACTIVE conversation, taking
    -- over from the hidden window header (same three-line drawing)
    local burger = ns.MakeFlatBtn(strip, "", BURGER_W, TAB_H - 6)
    burger:SetPoint("RIGHT", close, "LEFT", -3, 0)
    burger:SetFrameLevel(strip:GetFrameLevel() + 3)
    burger.lines = {}
    for i = -1, 1 do
        local line = burger:CreateTexture(nil, "OVERLAY")
        line:SetSize(9, 1)
        line:SetColorTexture(P.text[1], P.text[2], P.text[3], 0.9)
        line:SetPoint("CENTER", burger, "CENTER", 0, i * 3)
        burger.lines[#burger.lines + 1] = line
    end
    burger:SetScript("OnClick", function()
        local win = activeKey and ns.Windows[activeKey]
        if win and ns.OpenCharacterMenu then ns.OpenCharacterMenu(win) end
    end)
    local bEnter, bLeave = burger:GetScript("OnEnter"), burger:GetScript("OnLeave")
    burger:SetScript("OnEnter", function(self)
        bEnter(self)
        for _, line in ipairs(self.lines) do line:SetColorTexture(1, 1, 1, 1) end
        local win = activeKey and ns.Windows[activeKey]
        if win then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(ns.T("tipMenu", ns.ShortName(win.info.name)), 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    burger:SetScript("OnLeave", function(self)
        bLeave(self)
        for _, line in ipairs(self.lines) do
            line:SetColorTexture(P.text[1], P.text[2], P.text[3], 0.9)
        end
        GameTooltip:Hide()
    end)
    host.burger = burger

    -- >> button, shown when the tabs no longer fit
    local overflow = ns.MakeFlatBtn(strip, ">>", OVERFLOW_W, TAB_H - 6)
    overflow:SetPoint("RIGHT", burger, "LEFT", -2, 0)
    overflow:SetFrameLevel(strip:GetFrameLevel() + 3)
    overflow:SetScript("OnClick", ToggleOverflowMenu)
    -- MakeFlatBtn owns OnEnter/OnLeave for the hover colours; chain the tooltip
    local enter, leave = overflow:GetScript("OnEnter"), overflow:GetScript("OnLeave")
    overflow:SetScript("OnEnter", function(self)
        enter(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(ns.T("tipMoreTabs"), 1, 1, 1)
        GameTooltip:Show()
    end)
    overflow:SetScript("OnLeave", function(self)
        leave(self)
        GameTooltip:Hide()
    end)
    overflow:Hide()
    host.overflow = overflow

    host:SetScript("OnSizeChanged", function() LayoutTabs() end)
    host:Hide()
    return host
end

--=========================================================================
-- Tab layout
--=========================================================================

-- Lay the tabs out over the strip. Widths are natural (text-sized) up to a
-- shared cap that shrinks until everything fits; when even TAB_MIN does not,
-- the strip windows over the list (firstVis follows the active tab) and the
-- >> button lists everything.
function LayoutTabs()
    if not host then return end
    local strip = host.strip
    local n = #tabOrder

    local stripW = strip:GetWidth()
    if not stripW or stripW <= 0 then stripW = (host:GetWidth() or 340) - 2 end
    -- the close and burger buttons own the strip's right edge
    local availTotal = stripW - STRIP_PAD - (CLOSE_W + BURGER_W + 12)

    local nat = {}
    for i, key in ipairs(tabOrder) do
        local win = ns.Windows[key]
        host.measure:SetText(win and ColoredName(win.info) or "?")
        -- icon (5+14+4) on the left, close x / badge reserve on the right
        local w = math.ceil(host.measure:GetUnboundedStringWidth() or 0) + 23 + 16
        nat[i] = math.max(TAB_MIN, math.min(TAB_MAX, w))
    end
    local function Total(cap)
        if n == 0 then return 0 end
        local s = 0
        for i = 1, n do s = s + math.min(nat[i], cap) end
        return s + (n - 1) * TAB_GAP
    end

    local cap = TAB_MAX
    while cap > TAB_MIN and Total(cap) > availTotal do cap = cap - 4 end
    if cap < TAB_MIN then cap = TAB_MIN end

    local overflowing = Total(cap) > availTotal
    local visCount, uniformW = n, nil
    if overflowing then
        local avail = availTotal - (OVERFLOW_W + 4)
        visCount = math.max(1, math.floor((avail + TAB_GAP) / (TAB_MIN + TAB_GAP)))
        visCount = math.min(visCount, n)
        uniformW = math.floor((avail - (visCount - 1) * TAB_GAP) / visCount)
        -- keep the active tab inside the visible window
        local ai = (activeKey and IndexOf(activeKey)) or 1
        if firstVis > ai then firstVis = ai end
        if ai > firstVis + visCount - 1 then firstVis = ai - visCount + 1 end
        firstVis = math.max(1, math.min(firstVis, n - visCount + 1))
    else
        firstVis = 1
    end

    local x = STRIP_PAD
    for j = 1, visCount do
        local oi = firstVis + j - 1
        local key = tabOrder[oi]
        local tab = host.tabs[j]
        if not tab then
            tab = MakeTab()
            host.tabs[j] = tab
        end
        local w = uniformW or math.min(nat[oi], cap)
        tab.key = key
        tab:SetWidth(w)
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", strip, "TOPLEFT", x, 0)

        local win = ns.Windows[key]
        tab.label:SetText(win and ColoredName(win.info) or "?")
        if win then ns.SetSourceIcon(tab.icon, win.info) end
        local active = (key == activeKey)
        tab.isActive = active
        tab.accent:SetShown(active)
        tab.label:SetAlpha(active and 1 or 0.6)
        tab.icon:SetAlpha(active and 1 or 0.6)
        local bg = active and P.header or P.tabBg
        tab:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])

        local unread = (not active) and ns.unread[key] or nil
        tab.hasUnread = (unread and unread > 0) or false
        if tab.hasUnread then
            local badge = tab.badge
            badge.count:SetText(unread > 99 and "99+" or tostring(unread))
            badge:SetWidth(math.max(14, math.ceil(badge.count:GetStringWidth()) + 8))
        end
        UpdateTabRight(tab)
        tab:Show()
        x = x + w + TAB_GAP
    end
    for j = visCount + 1, #host.tabs do host.tabs[j]:Hide() end
    if n == 0 then
        for j = 1, #host.tabs do host.tabs[j]:Hide() end
    end
    host.overflow:SetShown(overflowing)
    if not overflowing and ofMenu then ofMenu:Hide() end
end

--=========================================================================
-- Activation / opening / closing
--=========================================================================

function ActivateTab(key)
    local win = ns.Windows[key]
    if not win then return end
    EnsureHost()
    if not IndexOf(key) then tabOrder[#tabOrder + 1] = key end
    local old = (activeKey and activeKey ~= key) and ns.Windows[activeKey] or nil
    activeKey = key
    if old and old.isTab and old:IsShown() then old:Hide() end
    AttachWin(win)
    if not host:IsShown() then host:Show() end
    if not win:IsShown() then win:Show() end
    host:Raise()
    LayoutTabs()
end

-- Bring a conversation up in tab mode (called via ns.ShowWindow). `activate`
-- switches to its tab; otherwise it becomes/stays a background tab -- unless
-- the host is hidden or empty, where whatever arrives takes the stage.
-- Returns true when the conversation is visible afterwards.
function ns.TabShow(win, activate)
    EnsureHost()
    local key = win.key
    if not IndexOf(key) then
        tabOrder[#tabOrder + 1] = key
    end
    if activate or key == activeKey or not host:IsShown()
        or not (activeKey and ns.Windows[activeKey]) then
        ActivateTab(key)
        return true
    end
    LayoutTabs()   -- new background tab / badge update
    return false
end

-- Close one tab. A neighbouring tab takes over; closing the last one hides
-- the whole window.
function ns.CloseTab(win)
    local key = win.key
    local idx = IndexOf(key)
    win:Hide()
    if not idx then return end
    table.remove(tabOrder, idx)
    if activeKey == key then
        activeKey = nil
        local nextKey = tabOrder[math.min(idx, #tabOrder)]
        if nextKey then
            ActivateTab(nextKey)
            return
        end
        if host then host:Hide() end
    end
    LayoutTabs()
end

-- Drop every tab (hide-everything paths such as screenshot mode).
function ns.CloseAllTabs()
    wipe(tabOrder)
    activeKey = nil
    firstVis = 1
    if host then
        host:Hide()
        LayoutTabs()
    end
    if ofMenu then ofMenu:Hide() end
end

-- Re-show the tab window (after combat) on whatever tab was active.
function ns.ShowTabHost()
    if not ns.db.tabMode or #tabOrder == 0 then return end
    local key = (activeKey and ns.Windows[activeKey] and activeKey)
        or tabOrder[#tabOrder]
    ActivateTab(key)
end

-- Repaint the strip (names, class colours, unread badges). Called whenever
-- unread counts or conversation identities change.
function ns.RefreshTabStrip()
    if host and host:IsShown() then LayoutTabs() end
end

-- Is this conversation an open tab? (Counts even while the host is hidden --
-- the tab set survives ESC and combat, and comes back with the window.)
function ns.IsOpenTab(key)
    return ns.db.tabMode == true and IndexOf(key) ~= nil
end

--=========================================================================
-- Mode switch -- converts whatever is on screen live, in either direction
--=========================================================================

function ns.SetTabMode(on)
    on = on and true or false
    if (ns.db.tabMode and true or false) == on then return end

    if on then
        local shown = ns.ShownWindows()
        ns.db.tabMode = true
        for _, w in ipairs(shown) do w:Hide() end
        for _, w in ipairs(shown) do ns.ShowWindow(w) end
        -- the newest conversation ends up selected, like the top window was
        local last = shown[#shown]
        if last and not (ns.inCombat and ns.db.combatHide) then
            ActivateTab(last.key)
        end
    else
        local wasShown = host and host:IsShown()
        local wins = {}
        for _, key in ipairs(tabOrder) do
            local w = ns.Windows[key]
            if w then wins[#wins + 1] = w end
        end
        ns.db.tabMode = false
        wipe(tabOrder)
        activeKey = nil
        firstVis = 1
        if host then host:Hide() end
        if ofMenu then ofMenu:Hide() end
        for _, w in ipairs(wins) do
            if w:IsShown() then w:Hide() end
            DetachWin(w)
            if wasShown then ns.ShowWindow(w) end
        end
        if host then LayoutTabs() end
    end
end
