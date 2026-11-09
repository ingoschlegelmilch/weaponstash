-- Stash.lua
-- Weapon sets: snapshotting equipped weapons, assigning items to slots, equipping.
--
-- A set looks like:
--   { mh = "Name", mhID = 12345, mh2h = true|nil, oh = "Name"|nil, ohID = 12345|nil }
-- Only `mh`/`oh` (names) are needed for macros; IDs are used for icons and tooltips.

local _, ns = ...
local WS = ns.addon

local SLOT_MH = INVSLOT_MAINHAND or 16
local SLOT_OH = INVSLOT_OFFHAND or 17

WS.SLOT_MH = SLOT_MH
WS.SLOT_OH = SLOT_OH

-- Which equip locations each slot accepts.
local ALLOWED = {
    mh = { INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true },
    oh = { INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true },
}
local SLOT_LABEL = { mh = "main hand", oh = "off hand" }

-- 1.15.x moved these into C_Item; the bare globals only exist through Blizzard's
-- deprecation shim (loadDeprecationFallbacks CVar), so prefer the namespaced ones.
local C = C_Item or {}
local GetItemInfo = C.GetItemInfo or GetItemInfo
local GetItemInfoInstant = C.GetItemInfoInstant or GetItemInfoInstant
local EquipItemByName = C.EquipItemByName or EquipItemByName
local GetIconByID = C.GetItemIconByID or GetItemIcon

-- Name from item info, or from the link text when the item cache is still cold.
local function itemName(itemID, link)
    local name = GetItemInfo(itemID)
    if not name and link then
        name = link:match("%[(.-)%]")
    end
    if name ~= "" then
        return name
    end
end

local function equipLoc(itemID)
    return (select(4, GetItemInfoInstant(itemID)))
end

function WS:ItemIcon(itemID, name)
    if itemID then
        local icon = GetIconByID(itemID)
        if icon then
            return icon
        end
    end
    if name then
        return (select(10, GetItemInfo(name)))
    end
end

-- Item name wrapped in its quality color, when the item is cached.
function WS:ColoredItemName(itemID, name)
    local _, _, quality = GetItemInfo(itemID or name)
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color and color.hex then
        return color.hex .. name .. "|r"
    end
    return name
end

function WS:OnSetsChanged()
    self:RequestMacroUpdate()
    if self.RefreshUI then
        self:RefreshUI()
    end
end

local function validSetName(name)
    return name and name ~= "" and name:match("^[%w_%-]+$") ~= nil
end

function WS:Snapshot(setName)
    if not validSetName(setName) then
        self:Print("Usage: /ws save <set>  (letters, digits, _ and - only)")
        return
    end

    local mhID = GetInventoryItemID("player", SLOT_MH)
    if not mhID then
        self:Print("Nothing equipped in your main hand.")
        return
    end
    local ohID = GetInventoryItemID("player", SLOT_OH)

    local mh = itemName(mhID, GetInventoryItemLink("player", SLOT_MH))
    local oh = ohID and itemName(ohID, GetInventoryItemLink("player", SLOT_OH))
    if not mh or (ohID and not oh) then
        self:Print("Item info isn't loaded yet; try again in a moment.")
        return
    end

    self.db.sets[setName] = {
        mh = mh, mhID = mhID, mh2h = (equipLoc(mhID) == "INVTYPE_2HWEAPON") or nil,
        oh = oh or nil, ohID = ohID,
    }
    self:Print(("Saved |cffffff00%s|r: %s%s"):format(setName, mh, oh and (" + " .. oh) or ""))

    self:OnSetsChanged()
end

-- Put an item (by ID, with its link if known) into one slot of a set, or clear the
-- slot when itemID is nil. Returns true, or false plus a message.
function WS:SetSlot(setName, slot, itemID, itemLink)
    local set = self.db.sets[setName] or {}

    if itemID then
        local name = itemName(itemID, itemLink)
        if not name then
            return false, "Item info isn't loaded yet; try again in a moment."
        end
        local loc = equipLoc(itemID)
        if not ALLOWED[slot][loc] then
            return false, ("%s can't go in the %s."):format(name, SLOT_LABEL[slot])
        end

        set[slot], set[slot .. "ID"] = name, itemID
        if slot == "mh" then
            set.mh2h = (loc == "INVTYPE_2HWEAPON") or nil
            if set.mh2h then
                set.oh, set.ohID = nil, nil -- a 2H leaves no room for an off hand
            end
        elseif set.mh2h then
            set.mh, set.mhID, set.mh2h = nil, nil, nil -- off hand displaces a 2H
        end
    else
        set[slot], set[slot .. "ID"] = nil, nil
        if slot == "mh" then
            set.mh2h = nil
        end
    end

    self.db.sets[setName] = (set.mh or set.oh) and set or nil
    self:OnSetsChanged()
    return true
end

function WS:EquipSet(setName)
    local set = self.db.sets[setName]
    if not set or not set.mh then
        self:Print(("Set '%s' has no main hand."):format(setName))
        return
    end
    if InCombatLockdown() then
        self:Print("Can't swap from the window in combat; use the macro.")
        return
    end
    EquipItemByName(set.mhID or set.mh, SLOT_MH)
    if set.oh then
        EquipItemByName(set.ohID or set.oh, SLOT_OH)
    end
end

function WS:DeleteSet(setName)
    if not self.db.sets[setName] then
        self:Print(("No set named '%s'."):format(setName or ""))
        return
    end
    self.db.sets[setName] = nil
    self:Print(("Deleted set '%s'."):format(setName))
    if self.RefreshUI then
        self:RefreshUI()
    end
end

function WS:ListSets()
    local names = {}
    for name in pairs(self.db.sets) do
        names[#names + 1] = name
    end
    if #names == 0 then
        self:Print("No sets saved yet. Equip your weapons and use /ws save <set>, or open /ws.")
        return
    end
    table.sort(names)
    self:Print("sets:")
    for _, name in ipairs(names) do
        local set = self.db.sets[name]
        print(("  |cffffff00%s|r: %s%s"):format(name, set.mh or "(no main hand)", set.oh and (" + " .. set.oh) or ""))
    end
end
