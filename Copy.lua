-- Whispy - Copy.lua
-- Selectable message text.
--
-- Font strings cannot be selected, so the text of the message under the mouse
-- is swapped for a read-only edit box laid over it, which can: drag across it
-- to mark any part of the line, Ctrl+C to copy. One box per window, moved to
-- whichever message the cursor is on.
--
-- Plain messages arm on hover, so the very first drag already selects. Ones
-- containing a hyperlink arm on click instead -- the box would otherwise cover
-- the bubble and swallow the link's tooltip and click.

local addonName, ns = ...
local P = ns.P

--=========================================================================
-- Plain text
--
-- What is on screen is full of escape sequences (colour codes, hyperlinks).
-- Pasting those into Discord is useless, so strip them down to the visible
-- characters -- which is also why the box still wraps identically: everything
-- removed here had zero width to begin with.
--=========================================================================
function ns.PlainText(s)
    if not s or s == "" then return "" end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")   -- colour open
    s = s:gsub("|r", "")                   -- colour close
    s = s:gsub("|H.-|h(.-)|h", "%1")       -- hyperlink -> its label
    s = s:gsub("|T.-|t", "")               -- inline texture
    s = s:gsub("|A.-|a", "")               -- inline atlas
    s = s:gsub("||", "|")                  -- unescape literal pipes
    return s
end

-- Messages with a link keep the bubble's own mouse handling, so their box only
-- appears on demand.
function ns.HasLink(text)
    return text ~= nil and text:find("|H", 1, true) ~= nil
end

--=========================================================================
-- The selection box -- one shared read-only edit box per window.
--=========================================================================

-- Keep the contents fixed: an edit box has no read-only flag, so undo anything
-- typed into it. Programmatic SetText passes userInput=false and is left alone.
local function LockText(self, userInput)
    if not userInput or self.guard then return end
    self.guard = true
    self:SetText(self.locked or "")
    self.guard = false
end

local function MakeSelectBox(win)
    local eb = CreateFrame("EditBox", nil, win.content)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject("ChatFontNormal")
    eb:SetTextColor(P.bubTxt[1], P.bubTxt[2], P.bubTxt[3])
    eb:SetTextInsets(0, 0, 0, 0)
    eb:EnableMouse(true)
    eb:Hide()

    eb:SetScript("OnTextChanged", LockText)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusLost", function() ns.EndSelection(win) end)

    -- Hovering armed it; leaving disarms again -- unless it is holding a live
    -- selection, which the user still has to Ctrl+C.
    eb:SetScript("OnLeave", function() ns.MaybeEndSelection(win) end)

    -- Raise on mouse *up*: the press and the drag that follows belong to the
    -- edit box's own selection handling and are left untouched.
    eb:SetScript("OnMouseUp", function() win:Raise() end)

    -- the box covers the bubble, so the wheel has to reach the list by hand
    eb:EnableMouseWheel(true)
    eb:SetScript("OnMouseWheel", function(_, delta)
        local sf = win.scrollFrame
        local h = sf and sf:GetScript("OnMouseWheel")
        if h then h(sf, delta) end
    end)

    win.selectBox = eb
    return eb
end

-- Put the shared box over one message row. Nothing is pre-selected and focus
-- is left alone: the drag that follows is what selects, and what focuses.
function ns.SelectMessage(win, row)
    if not row or not row.rawText or not win.content then return end
    if win.selectRow == row and win.selectBox and win.selectBox:IsShown() then
        return
    end
    ns.EndSelection(win)

    local eb = win.selectBox or MakeSelectBox(win)
    local fs = row.text
    local text = ns.PlainText(row.rawText)

    eb:ClearAllPoints()
    eb:SetPoint("TOPLEFT", fs, "TOPLEFT", 0, 0)
    eb:SetWidth(fs:GetWidth())
    eb:SetHeight(math.max(12, math.ceil(fs:GetStringHeight())))
    -- above the bubble, which is mouse-enabled and would eat the clicks
    eb:SetFrameLevel(row.bubble:GetFrameLevel() + 5)

    eb.locked = text
    eb.guard = true
    eb:SetText(text)
    eb.guard = false

    fs:Hide()             -- the box draws the same text, in the same place
    win.selectRow = row
    eb:Show()
end

-- Disarm on mouse-out, but only once the cursor has left both the box and the
-- message it sits on -- the two hand the cursor back and forth as the box is
-- shown and hidden, and disarming mid-handover flickers. A box holding a
-- selection keeps its focus, and stays until that focus is lost.
function ns.MaybeEndSelection(win)
    local eb, row = win.selectBox, win.selectRow
    if not eb or not row then return end
    if eb:HasFocus() or eb:IsMouseOver() or row.bubble:IsMouseOver() then return end
    ns.EndSelection(win)
end

-- Take the box away again and put the rendered message back.
function ns.EndSelection(win)
    local eb = win.selectBox
    if not eb or win.endingSelection then return end
    win.endingSelection = true
    if win.selectRow and win.selectRow.text then win.selectRow.text:Show() end
    win.selectRow = nil
    eb:Hide()             -- hiding drops focus, which re-enters here
    eb:ClearFocus()
    win.endingSelection = false
end
