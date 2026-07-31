-- Whispy - ChatList.lua
-- Minimap button + recent-chats flyout (left click) + full chat list (right click).

local addonName, ns = ...
local P = ns.P

local ROW_H     = 34
local TITLE_H   = 20
local FLY_W     = 240
local FLY_MAX   = 8

--=========================================================================
-- Helpers
--=========================================================================

-- Compact relative time: "now", "5m", "3h", "2d", or a date.
local function RelTime(t)
    if not t or t == 0 then return "" end
    local d = time() - t
    if d < 60      then return ns.T("now") end
    if d < 3600    then return math.floor(d / 60) .. "m" end
    if d < 86400   then return math.floor(d / 3600) .. "h" end
    if d < 604800  then return math.floor(d / 86400) .. "d" end
    return ns.Date("%b %d", t)
end

-- A clickable conversation row (name + time + preview). Caller anchors it.
local function MakeRow(parent, onClick)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetHeight(ROW_H)
    row:SetHighlightTexture("Interface/Buttons/WHITE8X8")
    row:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.07)

    local tm = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tm:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -5)
    tm:SetJustifyH("RIGHT")
    tm:SetTextColor(P.dim[1], P.dim[2], P.dim[3])
    row.time = tm

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -4)
    name:SetPoint("RIGHT", tm, "LEFT", -6, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    row.name = name

    local prev = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    prev:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
    prev:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    prev:SetJustifyH("LEFT")
    prev:SetWordWrap(false)
    prev:SetTextColor(P.dim[1], P.dim[2], P.dim[3])
    row.preview = prev

    function row:SetData(c)
        self.key = c.key
        local disp = ns.ShortName(c.name)
        local cc = (not c.isBN) and ns.ClassColorFromGUID(c.guid, c.class) or nil
        if cc then
            self.name:SetText(cc:WrapTextInColorCode(disp))
        elseif c.isBN then
            self.name:SetText(ns.Hex(0.32, 0.68, 1.00) .. disp .. "|r")
        else
            self.name:SetText(ns.Hex(P.text[1], P.text[2], P.text[3]) .. disp .. "|r")
        end
        self.time:SetText(RelTime(c.last))
        self.preview:SetText(c.preview or "")
    end

    row:SetScript("OnClick", function(self)
        if self.key then onClick(self.key) end
    end)
    return row
end

--=========================================================================
-- Recent-chats flyout (left click)
--=========================================================================
local flyout

local function EnsureFlyout()
    if flyout then return flyout end
    flyout = CreateFrame("Frame", "WhispyRecentFlyout", UIParent, "BackdropTemplate")
    flyout:SetFrameStrata("DIALOG")
    flyout:SetSize(FLY_W, 60)
    ns.ApplyFlatBg(flyout, P.bg[1], P.bg[2], P.bg[3], 0.98)
    flyout.rows = {}

    local title = flyout:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", flyout, "TOPLEFT", 8, -5)
    title:SetTextColor(P.accent[1], P.accent[2], P.accent[3])
    title:SetText(ns.T("recentChats"))

    local empty = flyout:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    empty:SetPoint("TOPLEFT", flyout, "TOPLEFT", 8, -(TITLE_H + 4))
    empty:SetTextColor(P.dim[1], P.dim[2], P.dim[3])
    empty:SetText(ns.T("noChats"))
    flyout.empty = empty

    flyout:Hide()
    tinsert(UISpecialFrames, "WhispyRecentFlyout")

    -- auto-close only after the cursor has been off both the flyout and the
    -- minimap button continuously for 0.5s (so slow travel across the gap is ok)
    flyout:SetScript("OnShow", function(self) self.outside = 0 end)
    flyout:SetScript("OnUpdate", function(self, e)
        if self:IsMouseOver()
           or (ns.minimapBtn and ns.minimapBtn:IsMouseOver()) then
            self.outside = 0
        else
            self.outside = (self.outside or 0) + e
            if self.outside >= 0.5 then self:Hide() end
        end
    end)
    return flyout
end

local function OpenFromList(key)
    ns.OpenFromKey(key)
end

local function BuildFlyout()
    EnsureFlyout()
    local convos = ns.History:GetConversations()
    local n = math.min(#convos, FLY_MAX)

    for i = 1, n do
        local row = flyout.rows[i]
        if not row then
            row = MakeRow(flyout, function(key) OpenFromList(key); flyout:Hide() end)
            flyout.rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", flyout, "TOPLEFT", 4, -(TITLE_H + 2 + (i - 1) * ROW_H))
        row:SetPoint("TOPRIGHT", flyout, "TOPRIGHT", -4, -(TITLE_H + 2 + (i - 1) * ROW_H))
        row:SetData(convos[i])
        row:Show()
    end
    for i = n + 1, #flyout.rows do flyout.rows[i]:Hide() end

    flyout.empty:SetShown(n == 0)
    local bodyH = (n > 0) and (n * ROW_H) or ROW_H
    flyout:SetSize(FLY_W, TITLE_H + 4 + bodyH + 4)
end

function ns.ToggleRecentFlyout()
    EnsureFlyout()
    if flyout:IsShown() then flyout:Hide(); return end
    GameTooltip:Hide()   -- clear the button tooltip so it doesn't overlap the flyout
    BuildFlyout()
    flyout:ClearAllPoints()
    flyout:SetPoint("TOPRIGHT", ns.minimapBtn, "TOPLEFT", -4, 0)
    flyout:Show()
    flyout:Raise()
end

--=========================================================================
-- Full chat list window (right click)
--=========================================================================
local listWin

local function EnsureListWindow()
    if listWin then return listWin end

    local w = CreateFrame("Frame", "WhispyChatListWindow", UIParent, "BackdropTemplate")
    w:SetSize(300, 400)
    w:SetFrameStrata("DIALOG")
    w:SetClampedToScreen(true)
    w:SetMovable(true)
    w:EnableMouse(true)
    w:SetToplevel(true)
    w:SetPoint("CENTER")
    ns.ApplyFlatBg(w, P.bg[1], P.bg[2], P.bg[3], P.bg[4])
    tinsert(UISpecialFrames, "WhispyChatListWindow")

    -- header
    local header = CreateFrame("Frame", nil, w, "BackdropTemplate")
    header:SetPoint("TOPLEFT", w, "TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", w, "TOPRIGHT", -1, -1)
    header:SetHeight(28)
    ns.ApplyFlatBg(header, P.header[1], P.header[2], P.header[3], P.header[4],
                          P.header[1], P.header[2], P.header[3], 0)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() w:StartMoving() end)
    header:SetScript("OnDragStop", function() w:StopMovingOrSizing() end)

    local accent = w:CreateTexture(nil, "ARTWORK")
    accent:SetHeight(1)
    accent:SetColorTexture(P.accent[1], P.accent[2], P.accent[3], 0.55)
    accent:SetPoint("TOPLEFT", w, "TOPLEFT", 1, -29)
    accent:SetPoint("TOPRIGHT", w, "TOPRIGHT", -1, -29)

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", header, "LEFT", 10, 0)
    title:SetTextColor(P.accent[1], P.accent[2], P.accent[3])
    title:SetText(ns.T("allChats"))

    local close = CreateFrame("Button", nil, header)
    close:SetSize(26, 28)
    close:SetPoint("RIGHT", header, "RIGHT", -2, 0)
    local cl = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cl:SetAllPoints()
    cl:SetJustifyH("CENTER")
    cl:SetText("|cff777799x|r")
    close:SetScript("OnEnter", function() cl:SetText("|cffee6666x|r") end)
    close:SetScript("OnLeave", function() cl:SetText("|cff777799x|r") end)
    close:SetScript("OnClick", function() w:Hide() end)

    -- scroll area
    local sf = CreateFrame("ScrollFrame", nil, w)
    sf:SetPoint("TOPLEFT", w, "TOPLEFT", 6, -34)
    sf:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -10, 6)
    sf:EnableMouseWheel(true)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(1, 1)
    sf:SetScrollChild(content)
    content:SetWidth(300 - 6 - 10)
    w.sf, w.content = sf, content

    sf:SetScript("OnMouseWheel", function(self, delta)
        local range = math.max(0, content:GetHeight() - self:GetHeight())
        local new = math.max(0, math.min(range, self:GetVerticalScroll() - delta * 40))
        self:SetVerticalScroll(new)
    end)

    local empty = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    empty:SetPoint("TOP", content, "TOP", 0, -10)
    empty:SetTextColor(P.dim[1], P.dim[2], P.dim[3])
    empty:SetText(ns.T("noChats"))
    w.empty = empty

    w.rows = {}
    listWin = w
    return w
end

local function BuildChatList()
    local w = EnsureListWindow()
    local convos = ns.History:GetConversations()

    for i = 1, #convos do
        local row = w.rows[i]
        if not row then
            row = MakeRow(w.content, function(key) OpenFromList(key) end)
            w.rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", w.content, "TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", w.content, "TOPRIGHT", 0, -(i - 1) * ROW_H)
        row:SetData(convos[i])
        row:Show()
    end
    for i = #convos + 1, #w.rows do w.rows[i]:Hide() end

    w.empty:SetShown(#convos == 0)
    w.content:SetHeight(math.max(1, #convos * ROW_H))
    w.sf:SetVerticalScroll(0)
end

function ns.ToggleChatList()
    local w = EnsureListWindow()
    if w:IsShown() then w:Hide(); return end
    BuildChatList()
    w:Show()
    w:Raise()
end

-- Rebuild whichever chat lists are currently on screen (used when the stored
-- history is swapped out from under them).
function ns.RefreshChatLists()
    if flyout and flyout:IsShown() then BuildFlyout() end
    if listWin and listWin:IsShown() then BuildChatList() end
end

--=========================================================================
-- Minimap button
--=========================================================================
-- Gap between the minimap edge and the button ring, matching LibDBIcon. The
-- radius itself is derived from the live minimap size so the button stays
-- flush when Blizzard (or another addon) resizes the minimap.
local MM_INSET = 5

local function MMUpdatePos()
    local btn = ns.minimapBtn
    if not btn then return end
    local angle = math.rad(ns.db.minimap.angle or 205)
    local w = (Minimap:GetWidth()  / 2) + MM_INSET
    local h = (Minimap:GetHeight() / 2) + MM_INSET
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * w, math.sin(angle) * h)
end

-- Keep the button flush if the minimap changes size after login.
Minimap:HookScript("OnSizeChanged", function()
    if ns.minimapBtn then MMUpdatePos() end
end)

local function MMDragUpdate()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    ns.db.minimap.angle = math.deg(math.atan2(cy - my, cx - mx))
    MMUpdatePos()
end

local function CreateMinimapButton()
    if ns.minimapBtn then return end
    local btn = CreateFrame("Button", "WhispyMinimapButton", Minimap)
    ns.minimapBtn = btn
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetSize(31, 31)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface/ICONS/INV_Letter_15")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", btn, "CENTER", 0, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local ring = btn:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface/Minimap/MiniMap-TrackingBorder")
    ring:SetSize(53, 53)
    ring:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)

    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", MMDragUpdate)
    end)
    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    btn:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            if flyout then flyout:Hide() end
            ns.ToggleChatList()
        else
            ns.ToggleRecentFlyout()
        end
    end)

    btn:SetScript("OnEnter", function(self)
        if flyout and flyout:IsShown() then return end  -- don't overlap the flyout
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Whispy")
        GameTooltip:AddLine(ns.T("tipLeft"), 1, 1, 1)
        GameTooltip:AddLine(ns.T("tipRight"), 1, 1, 1)
        GameTooltip:AddLine(ns.T("tipDrag"), 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    MMUpdatePos()
end

--=========================================================================
-- Init (after DB is ready)
--=========================================================================
local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function()
    if ns.db and not (ns.db.minimap and ns.db.minimap.hide) then
        CreateMinimapButton()
    end
end)

-- Slash toggle for the button.
function ns.SetMinimapShown(show)
    ns.db.minimap.hide = not show
    if show then
        CreateMinimapButton()
        if ns.minimapBtn then ns.minimapBtn:Show() end
    elseif ns.minimapBtn then
        ns.minimapBtn:Hide()
    end
end
