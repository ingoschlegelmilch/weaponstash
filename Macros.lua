-- Macros.lua
-- Rendering macro templates from saved weapon sets and writing them to real macros.
--
-- Placeholders (set names are lowercase):
--   {mh:<set>}     main hand item name of <set>
--   {oh:<set>}     off hand item name of <set> (empty if the set has none, e.g. a 2H)
--   {equip:<set>}  "/equipslot 16 <mh>" plus "/equipslot 17 <oh>" when the set has an off hand

local _, ns = ...
local WS = ns.addon

local MAX_BODY = 255                         -- client limit for macro text
local MAX_NAME = 16                          -- client limit for macro names
local MAX_CHAR_MACROS = MAX_CHARACTER_MACROS or 18
local ICON = "INV_MISC_QUESTIONMARK"         -- with #showtooltip the icon follows the spell

ns.DEFAULT_TEMPLATES = {
    ["WS Battle"] = "#showtooltip Battle Stance\n/cast [nostance:1] Battle Stance\n{equip:battle}",
    ["WS Defensive"] = "#showtooltip Defensive Stance\n/cast [nostance:2] Defensive Stance\n{equip:defensive}",
    ["WS Berserker"] = "#showtooltip Berserker Stance\n/cast [nostance:3] Berserker Stance\n{equip:berserker}",
}

local PLACEHOLDER = "{(%a+):([%w_%-]+)}"

local function equipLines(set)
    local lines = ("/equipslot %d %s"):format(WS.SLOT_MH, set.mh)
    if set.oh then
        lines = lines .. ("\n/equipslot %d %s"):format(WS.SLOT_OH, set.oh)
    end
    return lines
end

-- Returns the rendered body, or nil plus a list of missing set names.
function WS:Render(template)
    local sets = self.db.sets
    local missing, seen = {}, {}

    local body = template:gsub(PLACEHOLDER, function(kind, setName)
        kind = kind:lower()
        if kind ~= "mh" and kind ~= "oh" and kind ~= "equip" then
            return nil -- unknown placeholder: leave untouched
        end
        local set = sets[setName:lower()]
        if not set then
            if not seen[setName] then
                seen[setName] = true
                missing[#missing + 1] = setName
            end
            return ""
        end
        if kind == "mh" then
            return set.mh
        elseif kind == "oh" then
            return set.oh or ""
        end
        return equipLines(set)
    end)

    if #missing > 0 then
        return nil, missing
    end
    return body
end

local function templateHasPlaceholder(text)
    for rawKind in text:gmatch(PLACEHOLDER) do
        local kind = rawKind:lower()
        if kind == "mh" or kind == "oh" or kind == "equip" then
            return true
        end
    end
    return false
end

-- The macro UI saves its edit box when it closes, which would clobber our change
-- if it happened to be open on the same macro. Close it first.
local function closeMacroFrame()
    if MacroFrame and MacroFrame:IsShown() then
        HideUIPanel(MacroFrame)
    end
end

function WS:WriteMacro(name, body)
    if #body > MAX_BODY then
        self:Print(("|cffff5555%s|r is %d characters (limit %d); not updated."):format(name, #body, MAX_BODY))
        return false
    end

    local index = GetMacroIndexByName(name)
    if index and index > 0 then
        local _, _, current = GetMacroInfo(index)
        if current == body then
            self:Debug(name, "unchanged")
            return false
        end
        EditMacro(index, nil, nil, body)
        return true
    end

    local _, numChar = GetNumMacros()
    if numChar >= MAX_CHAR_MACROS then
        self:Print(("No free character macro slots; could not create |cffffff00%s|r."):format(name))
        return false
    end
    CreateMacro(name, ICON, body, true)
    return true
end

function WS:UpdateMacros()
    closeMacroFrame()

    local names = {}
    for name in pairs(self.db.templates) do
        names[#names + 1] = name
    end
    table.sort(names)

    local updated = 0
    for _, name in ipairs(names) do
        local body, missing = self:Render(self.db.templates[name])
        if body then
            if self:WriteMacro(name, body) then
                updated = updated + 1
            end
        else
            self:Debug(("skipping %s: missing set(s) %s"):format(name, table.concat(missing, ", ")))
        end
    end

    if updated > 0 then
        self:Print(("Updated %d macro(s)."):format(updated))
    end
end

-- Macros can't be edited in combat; defer until we leave it.
function WS:RequestMacroUpdate()
    if InCombatLockdown() then
        if not self.pendingUpdate then
            self.pendingUpdate = true
            self:RegisterEvent("PLAYER_REGEN_ENABLED")
            self:Print("In combat; macros will update when combat ends.")
        end
        return
    end
    self:UpdateMacros()
end

function WS:PLAYER_REGEN_ENABLED()
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    if self.pendingUpdate then
        self.pendingUpdate = nil
        self:UpdateMacros()
    end
end

-- ---------------------------------------------------------------------------
-- Template management
-- ---------------------------------------------------------------------------

function WS:ListTemplates()
    local names = {}
    for name in pairs(self.db.templates) do
        names[#names + 1] = name
    end
    if #names == 0 then
        self:Print("No managed macros. Use /ws adopt <macro> or /ws reset.")
        return
    end
    table.sort(names)
    self:Print("managed macros:")
    for _, name in ipairs(names) do
        local _, missing = self:Render(self.db.templates[name])
        local status = missing and ("|cffff5555missing: " .. table.concat(missing, ", ") .. "|r") or "|cff55ff55ready|r"
        print(("  |cffffff00%s|r (%s)"):format(name, status))
        for line in self.db.templates[name]:gmatch("[^\n]+") do
            print("      " .. line)
        end
    end
end

-- Store an existing macro's current text as a template. The intended flow:
-- write a macro in the normal macro UI using placeholders, then /ws adopt it.
function WS:AdoptMacro(name)
    if name == "" then
        self:Print("Usage: /ws adopt <macro name>")
        return
    end
    if #name > MAX_NAME then
        self:Print(("Macro names are at most %d characters."):format(MAX_NAME))
        return
    end
    local index = GetMacroIndexByName(name)
    if not index or index == 0 then
        self:Print(("No macro named '%s'."):format(name))
        return
    end
    local _, _, body = GetMacroInfo(index)
    if not body or not templateHasPlaceholder(body) then
        self:Print("That macro has no {mh:set}, {oh:set} or {equip:set} placeholders.")
        return
    end
    self.db.templates[name] = body
    self:Print(("Now managing |cffffff00%s|r."):format(name))
    self:RequestMacroUpdate()
end

function WS:ForgetTemplate(name)
    if not self.db.templates[name] then
        self:Print(("'%s' is not a managed macro."):format(name or ""))
        return
    end
    self.db.templates[name] = nil
    self:Print(("Stopped managing '%s' (macro left as-is)."):format(name))
end
