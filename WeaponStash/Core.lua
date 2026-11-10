-- Core.lua
-- Entry point: addon namespace, saved variables, event handling, slash commands.

local addonName, ns = ...

local WS = {}
ns.addon = WS

function WS:Print(...)
    print("|cff33ff99" .. addonName .. "|r:", ...)
end

function WS:Debug(...)
    if self.db and self.db.debug then
        self:Print("|cffff9900[debug]|r", ...)
    end
end

-- Called once SavedVariables are available (ADDON_LOADED).
-- Layout of WeaponStashCharDB:
--   sets  = { [setName] = { mh, mhID, mh2h, oh, ohID } }   (see Stash.lua)
--   links = { ["c:Macro Name" | "a:Macro Name"] = setName } (see Macros.lua)
--   debug = boolean
function WS:OnInitialize()
    WeaponStashCharDB = WeaponStashCharDB or {}
    local db = WeaponStashCharDB
    db.sets = db.sets or {}
    db.links = db.links or {}
    db.templates = nil -- pre-0.2 template system, superseded by links
    self.db = db
end

-- ---------------------------------------------------------------------------
-- Event frame plumbing
-- ---------------------------------------------------------------------------

local frame = CreateFrame("Frame")

function WS:RegisterEvent(event)
    frame:RegisterEvent(event)
end

function WS:UnregisterEvent(event)
    frame:UnregisterEvent(event)
end

frame:RegisterEvent("ADDON_LOADED")

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... == addonName then
            WS:OnInitialize()
            frame:UnregisterEvent("ADDON_LOADED")
        end
        return
    end

    -- Dispatch any other registered event to a same-named method.
    local handler = WS[event]
    if handler then
        handler(WS, ...)
    end
end)

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------

local function trim(s)
    return (s or ""):gsub("^%s*(.-)%s*$", "%1")
end

local function printHelp()
    WS:Print("commands:")
    print("  /ws                    - open the weapon set window")
    print("  /ws save <set>         - snapshot equipped MH/OH into <set>, then update macros")
    print("  /ws sets               - list saved sets")
    print("  /ws delete <set>       - delete a set")
    print("  /ws link <set> <macro> - keep a macro's /equipslot 16/17 lines in sync with <set>")
    print("  /ws unlink <macro>     - stop updating a macro")
    print("  /ws links              - list linked macros")
    print("  /ws update             - rewrite all linked macros now")
    print("  /ws debug              - toggle debug output")
end

SLASH_WEAPONSTASH1 = "/ws"
SLASH_WEAPONSTASH2 = "/weaponstash"

SlashCmdList["WEAPONSTASH"] = function(msg)
    local cmd, rest = trim(msg):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    rest = trim(rest)

    if cmd == "" or cmd == "show" then
        WS:ToggleUI()
    elseif cmd == "save" then
        WS:Snapshot(rest:lower())
    elseif cmd == "sets" or cmd == "list" then
        WS:ListSets()
    elseif cmd == "delete" or cmd == "del" then
        WS:DeleteSet(rest:lower())
    elseif cmd == "link" then
        local setName, macroName = rest:match("^(%S+)%s+(.+)$")
        WS:LinkByName(setName and setName:lower(), macroName)
    elseif cmd == "unlink" then
        WS:UnlinkByName(rest)
    elseif cmd == "links" then
        WS:ListLinks()
    elseif cmd == "update" then
        WS:RequestMacroUpdate()
    elseif cmd == "debug" then
        WS.db.debug = not WS.db.debug
        WS:Print("debug: " .. tostring(WS.db.debug))
    else
        printHelp()
    end
end
