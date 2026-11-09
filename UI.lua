-- UI.lua
-- Popup window: pick a stance/set from the dropdown, drag weapons onto the
-- Main Hand / Off Hand slots, and check which macros should follow that set.

local _, ns = ...
local WS = ns.addon

local STANCE_SETS = { "battle", "defensive", "berserker" }
local STANCE_BY_SPELL = { [2457] = "battle", [71] = "defensive", [2458] = "berserker" }
local STANCE_INFO = {
    battle    = { label = "Battle Stance",    icon = "Interface\\Icons\\Ability_Warrior_OffensiveStance" },
    defensive = { label = "Defensive Stance", icon = "Interface\\Icons\\Ability_Warrior_DefensiveStance" },
    berserker = { label = "Berserker Stance", icon = "Interface\\Icons\\Ability_Racial_Avatar" },
}
local SET_ICON = "Interface\\Icons\\INV_Sword_04"
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local SLOT_INFO = {
    mh = { label = "Main Hand", empty = "Interface\\Paperdoll\\UI-PaperDoll-Slot-MainHand" },
    oh = { label = "Off Hand",  empty = "Interface\\Paperdoll\\UI-PaperDoll-Slot-SecondaryHand" },
}

local FRAME_W, FRAME_H = 360, 520
local ROW_H = 22
local LIST_W = FRAME_W - 12 - 34 -- scroll frame insets (left, right incl. scrollbar)

local frame
local selected = "battle"
local rows = {}

local function setLabel(name)
    local info = STANCE_INFO[name]
    return info and info.label or (name:sub(1, 1):upper() .. name:sub(2))
end

-- Macro text can contain "|", which tooltips would read as an escape sequence.
local function escape(text)
    return (text:gsub("|", "||"))
end

-- Sets worth offering: the three stances, then any saved or linked set.
function WS:GetSetNames()
    local names, seen = {}, {}
    for _, name in ipairs(STANCE_SETS) do
        names[#names + 1], seen[name] = name, true
    end
    local extra = {}
    local function add(name)
        if not seen[name] then
            seen[name] = true
            extra[#extra + 1] = name
        end
    end
    for name in pairs(self.db.sets) do
        add(name)
    end
    for _, name in pairs(self.db.links) do
        add(name)
    end
    table.sort(extra)
    for _, name in ipairs(extra) do
        names[#names + 1] = name
    end
    return names
end

-- ---------------------------------------------------------------------------
-- Item slots
-- ---------------------------------------------------------------------------

local function dropOnSlot(button)
    local kind, itemID, itemLink = GetCursorInfo()
    if kind ~= "item" then
        return
    end
    ClearCursor() -- the item goes back where it came from; we only record it
    local ok, err = WS:SetSlot(selected, button.key, itemID, itemLink)
    if not ok then
        WS:Print(err)
    end
end

local function slotOnEnter(button)
    local set = WS.db.sets[selected]
    local name = set and set[button.key]
    local itemID = set and set[button.key .. "ID"]

    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if itemID then
        GameTooltip:SetHyperlink("item:" .. itemID)
    elseif name then
        GameTooltip:SetText(name)
    else
        GameTooltip:SetText(SLOT_INFO[button.key].label)
        GameTooltip:AddLine("Drag a weapon here.", 1, 1, 1)
    end
    if name then
        GameTooltip:AddLine("Right-click to clear.", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function createSlot(parent, key)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(44, 44)
    b.key = key

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    b.label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.label:SetPoint("BOTTOM", b, "TOP", 0, 4)
    b.label:SetText(SLOT_INFO[key].label)

    b.itemName = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.itemName:SetPoint("TOP", b, "BOTTOM", 0, -4)
    b.itemName:SetSize(140, 26)
    b.itemName:SetJustifyV("TOP")

    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnReceiveDrag", dropOnSlot)
    b:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" then
            WS:SetSlot(selected, self.key, nil)
            slotOnEnter(self)
        else
            dropOnSlot(self)
        end
    end)
    b:SetScript("OnEnter", slotOnEnter)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

-- ---------------------------------------------------------------------------
-- Macro list
-- ---------------------------------------------------------------------------

local function rowOnEnter(row)
    local macro = row.macro
    if not macro then
        return
    end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(escape(macro.name))
    for _, line in ipairs(ns.SplitLines(macro.body)) do
        GameTooltip:AddLine(line == "" and " " or escape(line), 1, 1, 1)
    end

    local set = WS.db.sets[selected]
    if set then
        local preview = ns.RewriteBody(macro.body, set)
        if preview ~= macro.body then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("With " .. setLabel(selected) .. ":", 1, 0.82, 0)
            for _, line in ipairs(ns.SplitLines(preview)) do
                GameTooltip:AddLine(line == "" and " " or escape(line), 0.5, 1, 0.5)
            end
        end
    end
    local note
    if macro.duplicate then
        note = "Another macro in this tab has the same name. Rename one of them so WeaponStash knows which to update."
    elseif row.scan and row.scan.mixed then
        note = "Its /equipslot lines use different conditions (e.g. one per stance), so it can't follow a single set and is left alone."
    elseif row.scan and row.scan.multi > 0 then
        note = "/equipslot lines with several ; clauses are left alone."
    end
    if note then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(note, 0.6, 0.6, 0.6, true)
    end
    if macro.perChar == false then
        GameTooltip:AddLine("General macros are shared by all your characters.", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

local function createRow(index)
    local row = CreateFrame("Button", nil, frame.content)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", 0, -(index - 1) * ROW_H)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    row.header = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.header:SetPoint("LEFT", 4, 0)

    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(22, 22)
    row.check:SetPoint("LEFT", 0, 0)
    row.check:SetScript("OnClick", function(self)
        -- Rows for links whose macro no longer exists can only be unchecked.
        local keep = self:GetChecked() and not row.macro.missing
        WS:SetLink(row.macro.key, keep and selected or nil)
    end)
    row.check:SetScript("OnEnter", function()
        rowOnEnter(row)
    end)
    row.check:SetScript("OnLeave", GameTooltip_Hide)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", row.check, "RIGHT", 2, 0)

    row.info = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.info:SetPoint("RIGHT", -4, 0)
    row.info:SetJustifyH("RIGHT")

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.info, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row:SetScript("OnClick", function(self)
        if self.macro and self.check:IsEnabled() then
            self.check:Click()
        end
    end)
    row:SetScript("OnEnter", rowOnEnter)
    row:SetScript("OnLeave", GameTooltip_Hide)

    rows[index] = row
    return row
end

local function showHeaderRow(row, text)
    row.macro, row.scan = nil, nil
    row.header:SetText(text)
    row.header:Show()
    row.check:Hide()
    row.icon:Hide()
    row.name:Hide()
    row.info:Hide()
    row:EnableMouse(false)
end

local function showMacroRow(row, macro)
    local scan = ns.ScanMacro(macro.body)
    local link = WS.db.links[macro.key]
    local usable = scan.mh + scan.oh > 0 and not scan.mixed and not macro.duplicate

    row.macro, row.scan = macro, scan
    row.header:Hide()
    row.check:Show()
    row.icon:Show()
    row.name:Show()
    row.info:Show()
    row:EnableMouse(true)

    row.check:SetChecked(link == selected or (macro.missing and link ~= nil))
    -- Linked rows stay clickable so they can always be unchecked.
    row.check:SetEnabled(usable or link ~= nil)
    row.icon:SetTexture(macro.icon or UNKNOWN_ICON)
    row.icon:SetDesaturated(not usable)
    row.name:SetText(macro.name)
    row.name:SetTextColor(usable and 1 or 0.5, usable and 1 or 0.5, usable and 1 or 0.5)

    local info
    local problem = WS.problems and WS.problems[macro.key]
    if macro.missing then
        info = "|cffff5555not found|r -> " .. setLabel(link)
    elseif problem then
        info = "|cffff5555" .. problem .. "|r"
    elseif link and link ~= selected then
        info = "|cffffd100" .. setLabel(link) .. "|r"
    elseif macro.duplicate then
        info = "duplicate name"
    elseif scan.mixed then
        info = "per-stance lines"
    elseif usable then
        local parts = {}
        if scan.mh > 0 then parts[#parts + 1] = "MH" end
        if scan.oh > 0 then parts[#parts + 1] = "OH" end
        info = table.concat(parts, "+") .. (scan.multi > 0 and " *" or "")
    else
        info = "no /equipslot"
    end
    row.info:SetText(info)
end

-- Rebuilds the list; returns how many macros are actually kept in sync with the
-- selected set (links that resolve to exactly one existing macro).
local function refreshMacroList()
    local entries, lastScope, present, synced = {}, nil, {}, 0
    for _, macro in ipairs(WS:GetMacros()) do
        if macro.perChar ~= lastScope then
            lastScope = macro.perChar
            entries[#entries + 1] = { header = macro.perChar and "Character macros" or "General macros" }
        end
        entries[#entries + 1] = macro
        if not present[macro.key] then
            present[macro.key] = true
            if WS.db.links[macro.key] == selected and not macro.duplicate then
                synced = synced + 1
            end
        end
    end
    if #entries == 0 then
        entries[1] = { header = "You don't have any macros yet." }
    end

    -- Links whose macro was renamed or deleted, so they can be removed here.
    local missing = {}
    for key in pairs(WS.db.links) do
        if not present[key] then
            local name, perChar = ns.MacroKeyName(key)
            missing[#missing + 1] = { key = key, name = name, perChar = perChar, body = "", missing = true }
        end
    end
    if #missing > 0 then
        table.sort(missing, function(x, y) return x.key < y.key end)
        entries[#entries + 1] = { header = "Linked macros that no longer exist" }
        for _, macro in ipairs(missing) do
            entries[#entries + 1] = macro
        end
    end

    for i, entry in ipairs(entries) do
        local row = rows[i] or createRow(i)
        if entry.header then
            showHeaderRow(row, entry.header)
        else
            showMacroRow(row, entry)
        end
        row:Show()
    end
    for i = #entries + 1, #rows do
        rows[i]:Hide()
    end
    frame.content:SetHeight(math.max(#entries * ROW_H, 1))
    return synced
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------

local function selectSet(name)
    selected = name
    CloseDropDownMenus()
    WS:RefreshUI()
end

local function initDropdown(_, level)
    for _, name in ipairs(WS:GetSetNames()) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = setLabel(name)
        info.checked = (name == selected)
        info.func = function()
            selectSet(name)
        end
        UIDropDownMenu_AddButton(info, level)
    end
end

local function createFrame()
    local f = CreateFrame("Frame", "WeaponStashFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, "WeaponStashFrame") -- close on Escape

    local title = f.TitleText
    if not title then
        title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOP", 0, -5)
    end
    title:SetText("WeaponStash")

    -- Stance icon + set dropdown
    f.setIcon = f:CreateTexture(nil, "ARTWORK")
    f.setIcon:SetSize(32, 32)
    f.setIcon:SetPoint("TOPLEFT", 18, -36)

    f.dropdown = CreateFrame("Frame", "WeaponStashSetDropDown", f, "UIDropDownMenuTemplate")
    f.dropdown:SetPoint("LEFT", f.setIcon, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(f.dropdown, 200)
    UIDropDownMenu_Initialize(f.dropdown, initDropdown)

    -- Weapon slots
    f.slots = {
        mh = createSlot(f, "mh"),
        oh = createSlot(f, "oh"),
    }
    f.slots.mh:SetPoint("TOP", f, "TOP", -75, -104)
    f.slots.oh:SetPoint("TOP", f, "TOP", 75, -104)

    -- Actions
    f.snapshotButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.snapshotButton:SetSize(128, 22)
    f.snapshotButton:SetPoint("TOPRIGHT", f, "TOP", -4, -186)
    f.snapshotButton:SetText("Use Equipped")
    f.snapshotButton:SetScript("OnClick", function()
        WS:Snapshot(selected)
    end)

    f.equipButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.equipButton:SetSize(128, 22)
    f.equipButton:SetPoint("TOPLEFT", f, "TOP", 4, -186)
    f.equipButton:SetText("Equip Set")
    f.equipButton:SetScript("OnClick", function()
        WS:EquipSet(selected)
    end)

    -- Macro list
    f.listHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.listHeader:SetPoint("TOPLEFT", 16, -222)
    f.listHeader:SetText("Macros to keep in sync")

    f.listHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.listHint:SetPoint("TOPLEFT", f.listHeader, "BOTTOMLEFT", 0, -3)
    f.listHint:SetPoint("RIGHT", -16, 0)
    f.listHint:SetJustifyH("LEFT")
    f.listHint:SetText("Checked macros get their /equipslot 16 and 17 item names replaced. Nothing else is changed.")

    f.listBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.listBg:SetColorTexture(0, 0, 0, 0.3)

    f.scroll = CreateFrame("ScrollFrame", "WeaponStashMacroScroll", f, "UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", 12, -264)
    f.scroll:SetPoint("BOTTOMRIGHT", -34, 34)
    f.listBg:SetPoint("TOPLEFT", f.scroll, "TOPLEFT", -2, 2)
    f.listBg:SetPoint("BOTTOMRIGHT", f.scroll, "BOTTOMRIGHT", 2, -2)

    f.content = CreateFrame("Frame", nil, f.scroll)
    f.content:SetSize(LIST_W, 1)
    f.scroll:SetScrollChild(f.content)

    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.status:SetPoint("BOTTOMLEFT", 16, 13)
    f.status:SetPoint("BOTTOMRIGHT", -16, 13)
    f.status:SetJustifyH("LEFT")

    f:SetScript("OnShow", function()
        -- Open on the stance you're currently in. The form index is a stance-bar
        -- position (it shifts if a stance isn't learned), so map by spell ID.
        local _, class = UnitClass("player")
        local form = GetShapeshiftForm()
        if class == "WARRIOR" and form and form > 0 then
            local spellID = select(4, GetShapeshiftFormInfo(form))
            selected = STANCE_BY_SPELL[spellID] or selected
        end
        -- Item names/qualities may arrive late; macros can change while we're open.
        WS:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        WS:RegisterEvent("UPDATE_MACROS")
        WS:RefreshUI()
    end)
    f:SetScript("OnHide", function()
        WS:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
        WS:UnregisterEvent("UPDATE_MACROS")
        CloseDropDownMenus()
    end)

    f:Hide()
    return f
end

-- Fires for every item the client loads (bags, chat links, AH scans...); only
-- refresh when it's one of the selected set's weapons.
function WS:GET_ITEM_INFO_RECEIVED(itemID, success)
    local set = self.db.sets[selected]
    if success and set and (itemID == set.mhID or itemID == set.ohID) then
        self:RefreshUI()
    end
end

function WS:UPDATE_MACROS()
    self:RefreshUI()
end

function WS:RefreshUI()
    if not frame or not frame:IsShown() then
        return
    end

    local set = self.db.sets[selected]
    UIDropDownMenu_SetText(frame.dropdown, setLabel(selected))
    frame.setIcon:SetTexture(STANCE_INFO[selected] and STANCE_INFO[selected].icon or SET_ICON)

    for key, b in pairs(frame.slots) do
        local name = set and set[key]
        if name then
            local itemID = set[key .. "ID"]
            b.icon:SetTexture(self:ItemIcon(itemID, name) or UNKNOWN_ICON)
            b.itemName:SetText(self:ColoredItemName(itemID, name))
        else
            b.icon:SetTexture(SLOT_INFO[key].empty)
            local twoHanded = key == "oh" and set and set.mh2h
            b.itemName:SetText(twoHanded and "|cff888888(two-hander)|r" or "|cff888888empty|r")
        end
    end
    frame.equipButton:SetEnabled(set ~= nil and set.mh ~= nil)

    local linked = refreshMacroList()

    local status
    if self.pendingUpdate then
        status = "Macros will update when combat ends."
    elseif not set then
        status = "Add weapons to this set to start updating macros."
    elseif linked == 0 then
        status = "Check the macros that should use these weapons."
    else
        status = ("%d macro(s) kept in sync with %s."):format(linked, setLabel(selected))
    end
    frame.status:SetText(status)
end

function WS:ToggleUI()
    frame = frame or createFrame()
    frame:SetShown(not frame:IsShown())
end
