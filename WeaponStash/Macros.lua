-- Macros.lua
-- Linking existing macros to weapon sets and rewriting only their
-- "/equipslot ... 16 <item>" and "/equipslot ... 17 <item>" lines.
--
-- Everything else in a linked macro (#showtooltip, /cast lines, conditions on the
-- /equipslot line itself) is left exactly as the player wrote it.

local _, ns = ...
local WS = ns.addon

local MAX_BODY = 255 -- client limit for macro text

-- Character macros start after this index. Forever (Mainline) only has the
-- namespaced constant; Classic Era / Anniversary only have the global.
local ACCOUNT_BASE = (Constants and Constants.MacroConsts and Constants.MacroConsts.MAX_ACCOUNT_MACROS)
    or MAX_ACCOUNT_MACROS or 120

-- ---------------------------------------------------------------------------
-- Line parsing / rewriting (pure functions, no WoW API)
-- ---------------------------------------------------------------------------

local function splitLines(body)
    local lines = {}
    for line in (body .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line
    end
    return lines
end
ns.SplitLines = splitLines

-- Parse "/equipslot [conditions] <slot> <item>".
-- Returns { head, slot, gap, item } for slot 16/17, where head .. slot .. gap .. item
-- reproduces the line (minus trailing whitespace).
-- For lines with several ;-separated clauses (left untouched) returns
-- nil, "multi", { mh = <a clause targets 16>, oh = <a clause targets 17> }.
-- Returns nil otherwise.
function ns.ParseEquipslot(line)
    local _, cmdEnd = line:lower():find("^%s*/equipslot")
    if not cmdEnd then
        return nil
    end
    local pos = cmdEnd + 1
    local nextChar = line:sub(pos, pos)
    if nextChar ~= "" and not nextChar:find("^[%s%[]") then
        return nil -- some other command that merely starts with /equipslot
    end

    if line:find(";", pos, true) then
        local clauses = ";" .. (line:sub(pos):gsub("%b[]", ""))
        return nil, "multi", {
            mh = clauses:find(";%s*16%s") ~= nil,
            oh = clauses:find(";%s*17%s") ~= nil,
        }
    end

    -- Skip whitespace and any number of [condition] blocks.
    while true do
        pos = pos + #line:match("^%s*", pos)
        if line:sub(pos, pos) ~= "[" then
            break
        end
        local block = line:match("^%b[]", pos)
        if not block then
            return nil
        end
        pos = pos + #block
    end

    local slot, gap, item = line:match("^(%d+)(%s+)(.-)%s*$", pos)
    if slot ~= "16" and slot ~= "17" then
        return nil
    end
    return { head = line:sub(1, pos - 1), slot = slot, gap = gap, item = item }
end

-- Parse a whole body once.
--   mh / oh   number of single-clause 16 / 17 lines
--   multi     number of ;-lines with a 16/17 clause (multiMH / multiOH: which slots)
--   mixed     the single-clause lines of one slot use different conditions,
--             e.g. "/equipslot [stance:1] 16 A" and "/equipslot [stance:2] 16 B".
--             Such per-stance macros can't follow one set, so they're never rewritten.
local function analyse(body)
    local a = {
        lines = splitLines(body), parsed = {},
        mh = 0, oh = 0, multi = 0, multiMH = false, multiOH = false, mixed = false,
    }
    local heads = {}
    for i, line in ipairs(a.lines) do
        local p, reason, targets = ns.ParseEquipslot(line)
        a.parsed[i] = p or false
        if p then
            if p.slot == "16" then
                a.mh = a.mh + 1
            else
                a.oh = a.oh + 1
            end
            local head = p.head:gsub("%s+", ""):lower()
            if heads[p.slot] == nil then
                heads[p.slot] = head
            elseif heads[p.slot] ~= head then
                a.mixed = true
            end
        elseif reason == "multi" and (targets.mh or targets.oh) then
            a.multi = a.multi + 1
            a.multiMH = a.multiMH or targets.mh
            a.multiOH = a.multiOH or targets.oh
        end
    end
    return a
end

-- Summary of what we'd touch in a macro, for the UI.
function ns.ScanMacro(body)
    local a = analyse(body)
    return { mh = a.mh, oh = a.oh, multi = a.multi, mixed = a.mixed }
end

-- Rewrite a macro body for `set`. Only single-clause /equipslot 16/17 lines change:
--   16 lines get the set's main hand (left alone if the set has none).
--   17 lines get the set's off hand. If the set is a two-hander and the macro
--   also equips the main hand, they're removed, since equipping an off hand would
--   knock the 2H back off. Otherwise (1H with empty off hand, or an off-hand-only
--   macro) they're left alone.
--   If the set has an off hand but the macro has no 17 line at all (e.g. it was
--   removed for a two-hander earlier), one is added after each 16 line, with its
--   conditions.
-- Returns the new body, plus a reason when the macro has to be left as-is.
function ns.RewriteBody(body, set)
    local a = analyse(body)
    if a.mixed then
        return body, "per-stance lines"
    end
    local dropOH = set.mh2h and set.mh and a.mh > 0
    if dropOH and a.multiOH then
        -- A ;-line we don't touch would still equip an off hand over the 2H.
        return body, "; line equips off hand"
    end

    local out, mhLines = {}, {}
    local hadOH = a.oh > 0 or a.multiOH
    for i, line in ipairs(a.lines) do
        local p = a.parsed[i]
        if p and p.slot == "16" then
            out[#out + 1] = set.mh and (p.head .. p.slot .. p.gap .. set.mh) or line
            mhLines[#mhLines + 1] = { index = #out, head = p.head, gap = p.gap }
        elseif p and p.slot == "17" then
            if set.oh then
                out[#out + 1] = p.head .. p.slot .. p.gap .. set.oh
            elseif not dropOH then
                out[#out + 1] = line
            end
        else
            out[#out + 1] = line
        end
    end

    if set.mh and set.oh and not hadOH then
        for i = #mhLines, 1, -1 do -- back to front so earlier indices stay valid
            local m = mhLines[i]
            table.insert(out, m.index + 1, m.head .. "17" .. m.gap .. set.oh)
        end
    end

    return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------------
-- Macro enumeration
-- ---------------------------------------------------------------------------

-- Links are keyed by scope + name so a General and a Character macro with the
-- same name don't collide: "a:Name" (account/General) or "c:Name" (Character).
-- Macros have no stable ID (indices shift as macros are added or removed), so the
-- name is the identity; two macros with the same name in one tab are flagged as
-- `duplicate` and never rewritten, since we can't tell which one was meant.
local function macroKey(perChar, name)
    return (perChar and "c:" or "a:") .. name
end

function ns.MacroKeyName(key)
    return key:sub(3), key:sub(1, 1) == "c"
end

-- All macros, General first then Character, as
-- { key, index, name, icon, body, perChar, duplicate }.
function WS:GetMacros()
    local list, count = {}, {}
    local numAccount, numChar = GetNumMacros()
    local function add(index, perChar)
        local name, icon, body = GetMacroInfo(index)
        if name then
            local key = macroKey(perChar, name)
            count[key] = (count[key] or 0) + 1
            list[#list + 1] = {
                key = key,
                index = index,
                name = name,
                icon = icon,
                body = body or "",
                perChar = perChar,
            }
        end
    end
    for i = 1, numAccount do
        add(i, false)
    end
    for i = ACCOUNT_BASE + 1, ACCOUNT_BASE + numChar do
        add(i, true)
    end
    for _, macro in ipairs(list) do
        macro.duplicate = count[macro.key] > 1
    end
    return list
end

-- Map of key -> macro (first one, flagged duplicate if the name repeats).
function WS:GetMacrosByKey()
    local byKey = {}
    for _, macro in ipairs(self:GetMacros()) do
        byKey[macro.key] = byKey[macro.key] or macro
    end
    return byKey
end

-- Resolve a plain macro name typed in chat to a link key; Character macros win.
function WS:ResolveMacroName(name)
    local byKey = self:GetMacrosByKey()
    for _, perChar in ipairs({ true, false }) do
        local key = macroKey(perChar, name)
        if byKey[key] then
            return key
        end
    end
end

-- ---------------------------------------------------------------------------
-- Writing
-- ---------------------------------------------------------------------------

-- The macro UI saves its edit box when it closes, which would clobber our change
-- if it happened to be open on the same macro. Close it first.
local function closeMacroFrame()
    if MacroFrame and MacroFrame:IsShown() then
        HideUIPanel(MacroFrame)
    end
end

function WS:UpdateMacros()
    closeMacroFrame()
    local previous = self.problems or {}
    self.problems = {}

    local function problem(key, name, text)
        self.problems[key] = text
        if previous[key] ~= text then -- don't repeat the same warning on every change
            self:Print(("|cffff5555%s|r not updated: %s."):format(name, text))
        end
    end

    local byKey = self:GetMacrosByKey()
    local updated = 0
    for key, setName in pairs(self.db.links) do
        local set = self.db.sets[setName]
        local macro = set and byKey[key]
        if macro and macro.duplicate then
            problem(key, macro.name, "another macro has the same name")
        elseif macro then
            local body, reason = ns.RewriteBody(macro.body, set)
            if reason then
                problem(key, macro.name, reason)
            elseif body ~= macro.body then
                if #body > MAX_BODY then
                    problem(key, macro.name, ("too long (%d/%d)"):format(#body, MAX_BODY))
                else
                    -- Editing the body only (name unchanged) doesn't reorder macros,
                    -- so the indices in byKey stay valid for the rest of the loop.
                    EditMacro(macro.index, nil, nil, body)
                    updated = updated + 1
                end
            end
        end
    end

    if updated > 0 then
        self:Print(("Updated %d macro(s)."):format(updated))
    end
    if self.RefreshUI then
        self:RefreshUI()
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
        if self.RefreshUI then
            self:RefreshUI()
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
-- Links
-- ---------------------------------------------------------------------------

-- Link a macro to a set (or unlink with setName = nil).
function WS:SetLink(key, setName)
    self.db.links[key] = setName
    if self.problems then
        self.problems[key] = nil
    end
    if setName then
        self:RequestMacroUpdate()
    elseif self.RefreshUI then
        self:RefreshUI()
    end
end

function WS:LinkByName(setName, macroName)
    if not setName or not setName:match("^[%w_%-]+$") or not macroName or macroName == "" then
        self:Print("Usage: /ws link <set> <macro name>")
        return
    end
    local key = self:ResolveMacroName(macroName)
    if not key then
        self:Print(("No macro named '%s'."):format(macroName))
        return
    end
    self:Print(("Linked |cffffff00%s|r to set '%s'."):format(macroName, setName))
    self:SetLink(key, setName)
end

function WS:UnlinkByName(macroName)
    for _, perChar in ipairs({ true, false }) do
        local key = macroKey(perChar, macroName)
        if self.db.links[key] then
            self:SetLink(key, nil)
            self:Print(("Unlinked |cffffff00%s|r."):format(macroName))
            return
        end
    end
    self:Print(("'%s' isn't linked."):format(macroName or ""))
end

function WS:ListLinks()
    local keys = {}
    for key in pairs(self.db.links) do
        keys[#keys + 1] = key
    end
    if #keys == 0 then
        self:Print("No linked macros. Open /ws and check the macros to keep in sync.")
        return
    end
    table.sort(keys)
    local byKey = self:GetMacrosByKey()
    self:Print("linked macros:")
    for _, key in ipairs(keys) do
        local name, perChar = ns.MacroKeyName(key)
        local missing = byKey[key] and "" or " |cffff5555(macro not found)|r"
        print(("  |cffffff00%s|r%s -> %s%s"):format(name, perChar and "" or " (general)", self.db.links[key], missing))
    end
end
