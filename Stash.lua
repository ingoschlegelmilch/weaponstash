-- Stash.lua
-- Snapshotting equipped weapons into named sets.

local _, ns = ...
local WS = ns.addon

local SLOT_MH = INVSLOT_MAINHAND or 16
local SLOT_OH = INVSLOT_OFFHAND or 17

WS.SLOT_MH = SLOT_MH
WS.SLOT_OH = SLOT_OH

-- Returns the plain item name equipped in `slot`, or nil if the slot is empty.
local function equippedName(slot)
    local link = GetInventoryItemLink("player", slot)
    if not link then
        return nil
    end
    -- Equipped items are always cached, but fall back to parsing the link anyway.
    return GetItemInfo(link) or link:match("%[(.-)%]")
end

local function validSetName(name)
    return name and name ~= "" and name:match("^[%w_%-]+$") ~= nil
end

function WS:Snapshot(setName)
    if not validSetName(setName) then
        self:Print("Usage: /ws save <set>  (letters, digits, _ and - only)")
        return
    end

    local mh = equippedName(SLOT_MH)
    if not mh then
        self:Print("Nothing equipped in your main hand.")
        return
    end
    local oh = equippedName(SLOT_OH)

    self.db.sets[setName] = { mh = mh, oh = oh }
    self:Print(("Saved |cffffff00%s|r: %s%s"):format(setName, mh, oh and (" + " .. oh) or ""))

    self:RequestMacroUpdate()
end

function WS:DeleteSet(setName)
    if not self.db.sets[setName] then
        self:Print(("No set named '%s'."):format(setName or ""))
        return
    end
    self.db.sets[setName] = nil
    self:Print(("Deleted set '%s'."):format(setName))
end

function WS:ListSets()
    local names = {}
    for name in pairs(self.db.sets) do
        names[#names + 1] = name
    end
    if #names == 0 then
        self:Print("No sets saved yet. Equip your weapons and use /ws save <set>.")
        return
    end
    table.sort(names)
    self:Print("sets:")
    for _, name in ipairs(names) do
        local set = self.db.sets[name]
        print(("  |cffffff00%s|r: %s%s"):format(name, set.mh, set.oh and (" + " .. set.oh) or ""))
    end
end
