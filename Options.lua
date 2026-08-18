-- Whispy - Options.lua
-- The options window (minimap right-click -> Options).
--
-- Small hand-rolled widgets in the addon's flat-dark style rather than
-- Blizzard's templates, so the panel matches the whisper windows.

local addonName, ns = ...
local P = ns.P

local WIN_W   = 360
local PAD     = 12
local ROW_H   = 22
local GAP     = 6
local SEC_GAP = 12
local INDENT  = 18
local DD_W    = 150

--=========================================================================
-- Checkbox
--   get() -> bool, set(bool). :Refresh() re-reads get().
--=========================================================================
local function MakeCheck(parent, text, get, set)
    local c = CreateFrame("Button", nil, parent)
    c:SetHeight(ROW_H)

    local box = CreateFrame("Frame", nil, c, "BackdropTemplate")
    box:SetSize(14, 14)
    box:SetPoint("LEFT", c, "LEFT", 0, 0)
    ns.ApplyFlatBg(box, P.btnBg[1], P.btnBg[2], P.btnBg[3], P.btnBg[4],
                        P.sep[1], P.sep[2], P.sep[3], P.sep[4])

    local fill = box:CreateTexture(nil, "OVERLAY")
    fill:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3)
    fill:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)
    fill:SetColorTexture(P.accent[1], P.accent[2], P.accent[3], 1)

    local fs = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", box, "RIGHT", 6, 0)
    fs:SetPoint("RIGHT", c, "RIGHT", 0, 0)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    c.label = fs

    function c:Refresh()
        fill:SetShown(get() and true or false)
        local dim = not self.enabled
        fs:SetTextColor(dim and P.dim[1] or P.text[1],
                        dim and P.dim[2] or P.text[2],
                        dim and P.dim[3] or P.text[3])
        box:SetAlpha(dim and 0.5 or 1)
    end

    function c:SetEnabledState(on)
        self.enabled = on and true or false
        self:EnableMouse(self.enabled)
        self:Refresh()
    end

    c:SetScript("OnClick", function()
        set(not get())
        ns.RefreshOptions()
    end)
    c:SetScript("OnEnter", function(self)
        if self.enabled then fs:SetTextColor(1, 1, 1) end
    end)
    c:SetScript("OnLeave", function(self) self:Refresh() end)

    c.enabled = true
    return c
end

--=========================================================================
-- Sound picker: a flat dropdown plus a preview button
--   get() -> sound key, set(key)
--
-- The popup shows at most MENU_ROWS rows and scrolls with the mouse wheel;
-- its contents are rebuilt from ns.SoundMenu() every time it opens, so
-- sounds registered late (LibSharedMedia) still show up.
--=========================================================================
local MENU_ROWS = 14
local MENU_W    = 210

local function MakeSoundPicker(parent, get, set)
    local dd = ns.MakeFlatBtn(parent, "", DD_W, ROW_H)
    dd.label:ClearAllPoints()
    dd.label:SetPoint("LEFT", dd, "LEFT", 6, 0)
    dd.label:SetPoint("RIGHT", dd, "RIGHT", -16, 0)
    dd.label:SetJustifyH("LEFT")

    local arrow = dd:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    arrow:SetPoint("RIGHT", dd, "RIGHT", -5, 0)
    arrow:SetTextColor(P.dim[1], P.dim[2], P.dim[3])
    arrow:SetText("v")

    local play = ns.MakeFlatBtn(parent, ">", ROW_H, ROW_H)
    play:SetPoint("LEFT", dd, "RIGHT", 4, 0)
    play:SetScript("OnClick", function() ns.PlayWhispySound(get()) end)
    play:SetScript("OnEnter", function(self)
        self:SetBackdropColor(P.btnHov[1], P.btnHov[2], P.btnHov[3], P.btnHov[4])
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ns.T("optPreview"), 1, 1, 1)
        GameTooltip:Show()
    end)
    play:SetScript("OnLeave", function(self)
        self:SetBackdropColor(P.btnBg[1], P.btnBg[2], P.btnBg[3], P.btnBg[4])
        GameTooltip:Hide()
    end)
    dd.play = play

    -- the popup list
    local list = CreateFrame("Frame", nil, dd, "BackdropTemplate")
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetWidth(MENU_W)
    ns.ApplyFlatBg(list, P.bg[1], P.bg[2], P.bg[3], 0.98)
    list:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -2)
    list:EnableMouseWheel(true)
    list:Hide()

    -- close once the cursor has been off both the list and its button a moment
    list:SetScript("OnShow", function(self) self.outside = 0 end)
    list:SetScript("OnUpdate", function(self, e)
        if self:IsMouseOver() or dd:IsMouseOver() then
            self.outside = 0
        else
            self.outside = (self.outside or 0) + e
            if self.outside >= 0.6 then self:Hide() end
        end
    end)

    -- thin scroll indicator along the right edge
    local thumb = list:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(3)
    thumb:SetColorTexture(P.accent[1], P.accent[2], P.accent[3], 0.4)

    local menu, offset = {}, 0
    local rows = {}

    local function Redraw()
        local shown = math.min(#menu, MENU_ROWS)
        list:SetHeight(shown * ROW_H + 4)
        for i = 1, MENU_ROWS do
            local row, item = rows[i], menu[i + offset]
            if i <= shown and item then
                row.item = item
                row.label:SetText(item.text)
                if item.header then
                    row.label:SetTextColor(P.accent[1], P.accent[2], P.accent[3])
                    row:EnableMouse(false)
                elseif item.key == get() then
                    row.label:SetTextColor(P.accent[1], P.accent[2], P.accent[3])
                    row:EnableMouse(true)
                else
                    row.label:SetTextColor(P.text[1], P.text[2], P.text[3])
                    row:EnableMouse(true)
                end
                row:Show()
            else
                row.item = nil
                row:Hide()
            end
        end
        if #menu > MENU_ROWS then
            local trackH = shown * ROW_H
            thumb:SetHeight(math.max(12, trackH * shown / #menu))
            thumb:ClearAllPoints()
            thumb:SetPoint("TOPRIGHT", list, "TOPRIGHT", -2,
                -(2 + (trackH - thumb:GetHeight()) * offset / (#menu - MENU_ROWS)))
            thumb:Show()
        else
            thumb:Hide()
        end
    end

    list:SetScript("OnMouseWheel", function(self, delta)
        local maxOff = math.max(0, #menu - MENU_ROWS)
        offset = math.min(maxOff, math.max(0, offset - delta * 3))
        Redraw()
    end)

    for i = 1, MENU_ROWS do
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 2, -(2 + (i - 1) * ROW_H))
        row:SetPoint("TOPRIGHT", list, "TOPRIGHT", -7, -(2 + (i - 1) * ROW_H))
        row:SetHighlightTexture("Interface/Buttons/WHITE8X8")
        row:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)

        local rl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        rl:SetPoint("LEFT", row, "LEFT", 6, 0)
        rl:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        rl:SetJustifyH("LEFT")
        rl:SetWordWrap(false)
        row.label = rl

        row:SetScript("OnClick", function(self)
            if not self.item or self.item.header then return end
            set(self.item.key)
            ns.PlayWhispySound(self.item.key)   -- WIM previews on pick; so do we
            list:Hide()
            ns.RefreshOptions()
        end)
        rows[i] = row
    end

    dd:SetScript("OnClick", function()
        if list:IsShown() then list:Hide() return end
        menu = ns.SoundMenu()
        -- open scrolled so the current pick is in view
        offset = 0
        for i, item in ipairs(menu) do
            if item.key == get() then
                offset = math.min(math.max(0, i - math.floor(MENU_ROWS / 2)),
                                  math.max(0, #menu - MENU_ROWS))
                break
            end
        end
        Redraw()
        list:Show()
        list:Raise()
    end)

    function dd:Refresh()
        self.label:SetText(ns.SoundLabel(get()))
        local dim = not self.enabled
        self.label:SetTextColor(dim and P.dim[1] or P.text[1],
                                dim and P.dim[2] or P.text[2],
                                dim and P.dim[3] or P.text[3])
    end

    function dd:SetEnabledState(on)
        self.enabled = on and true or false
        self:EnableMouse(self.enabled)
        play:EnableMouse(self.enabled)
        self:SetAlpha(self.enabled and 1 or 0.4)
        play:SetAlpha(self.enabled and 1 or 0.4)
        if not self.enabled then list:Hide() end
        self:Refresh()
    end

    dd.enabled = true
    return dd
end

--=========================================================================
-- The window
--=========================================================================
local win

local function EnsureWindow()
    if win then return win end

    local w = CreateFrame("Frame", "WhispyOptionsWindow", UIParent, "BackdropTemplate")
    w:SetWidth(WIN_W)
    w:SetFrameStrata("DIALOG")
    w:SetClampedToScreen(true)
    w:SetMovable(true)
    w:EnableMouse(true)
    w:SetToplevel(true)
    w:SetPoint("CENTER")
    ns.ApplyFlatBg(w, P.bg[1], P.bg[2], P.bg[3], P.bg[4])
    tinsert(UISpecialFrames, "WhispyOptionsWindow")

    -- header (built like the chat list window's)
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
    title:SetText(ns.T("optTitle"))

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

    --------------------------------------------------------------------
    -- body -- everything stacks downwards from `y`
    --------------------------------------------------------------------
    local y = 38
    local widgets = {}

    local function Section(key)
        if #widgets > 0 then y = y + SEC_GAP end
        local fs = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", w, "TOPLEFT", PAD, -y)
        fs:SetTextColor(P.accent[1], P.accent[2], P.accent[3])
        fs:SetText(ns.T(key))

        local line = w:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetColorTexture(P.sep[1], P.sep[2], P.sep[3], 1)
        line:SetPoint("TOPLEFT", w, "TOPLEFT", PAD, -(y + 16))
        line:SetPoint("TOPRIGHT", w, "TOPRIGHT", -PAD, -(y + 16))
        y = y + 22
    end

    local function Check(textKey, get, set, indent)
        local c = MakeCheck(w, ns.T(textKey), get, set)
        c:SetPoint("TOPLEFT", w, "TOPLEFT", PAD + (indent or 0), -y)
        c:SetPoint("RIGHT", w, "RIGHT", -PAD, 0)
        y = y + ROW_H + GAP
        widgets[#widgets + 1] = c
        return c
    end

    local function Picker(get, set, indent)
        local dd = MakeSoundPicker(w, get, set)
        dd:SetPoint("TOPLEFT", w, "TOPLEFT", PAD + (indent or 0), -y)
        y = y + ROW_H + GAP
        widgets[#widgets + 1] = dd
        return dd
    end

    local function db() return ns.db end

    Section("optGeneral")
    Check("optRouting",
        function() return db().enabled end,
        function(v) db().enabled = v end)
    Check("optCombatHide",
        function() return db().combatHide end,
        function(v) db().combatHide = v end)
    Check("optMinimapBtn",
        function() return not db().minimap.hide end,
        function(v) ns.SetMinimapShown(v) end)

    Section("optSounds")
    Check("optSndIn",
        function() return db().sound.incoming end,
        function(v) db().sound.incoming = v end)
    w.ddIn = Picker(
        function() return db().sound.incomingKey end,
        function(v) db().sound.incomingKey = v end, INDENT)

    w.cBnet = Check("optSndBnet",
        function() return db().sound.bnet end,
        function(v) db().sound.bnet = v end, INDENT)
    w.ddBnet = Picker(
        function() return db().sound.bnetKey end,
        function(v) db().sound.bnetKey = v end, INDENT * 2)

    Check("optSndOut",
        function() return db().sound.outgoing end,
        function(v) db().sound.outgoing = v end)
    w.ddOut = Picker(
        function() return db().sound.outgoingKey end,
        function(v) db().sound.outgoingKey = v end, INDENT)

    Check("optSndForce",
        function() return db().sound.force end,
        function(v) db().sound.force = v end)

    w:SetHeight(y + PAD - GAP)
    w.widgets = widgets
    win = w
    return w
end

-- Re-read every widget from the DB, applying the parent/child enable rules:
-- a sound picker is only live while the option it belongs to is on.
function ns.RefreshOptions()
    if not win then return end
    local s = ns.db.sound
    win.ddIn:SetEnabledState(s.incoming)
    win.cBnet:SetEnabledState(s.incoming)
    win.ddBnet:SetEnabledState(s.incoming and s.bnet)
    win.ddOut:SetEnabledState(s.outgoing)
    for _, wdg in ipairs(win.widgets) do
        wdg:Refresh()
    end
end

function ns.ToggleOptions()
    local w = EnsureWindow()
    if w:IsShown() then w:Hide(); return end
    ns.RefreshOptions()
    w:Show()
    w:Raise()
end
