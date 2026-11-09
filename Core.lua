-- Core.lua
-- Entry point: addon namespace, saved variables, event handling, slash commands.

local addonName, ns = ...

local WS = {}
ns.addon = WS

-- Shallow-enough copy for the template table (string values only).
function ns.CopyTable(src)
    local out = {}
    for k, v in pairs(src) do
        out[k] = v
    end
    return out
end

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
--   sets      = { [setName] = { mh = "Item Name", oh = "Item Name" or nil } }
--   templates = { [macroName] = "macro body with {placeholders}" }
--   debug     = boolean
function WS:OnInitialize()
    WeaponStashCharDB = WeaponStashCharDB or {}
    local db = WeaponStashCharDB
    db.sets = db.sets or {}
    if db.templates == nil then
        db.templates = ns.CopyTable(ns.DEFAULT_TEMPLATES)
    end
    self.db = db
end

function WS:OnEnable()
    local _, class = UnitClass("player")
    if class ~= "WARRIOR" then
        self:Debug("Not a warrior; default stance templates won't be useful here.")
    end
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
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... == addonName then
            WS:OnInitialize()
            frame:UnregisterEvent("ADDON_LOADED")
        end
        return
    elseif event == "PLAYER_LOGIN" then
        WS:OnEnable()
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
    print("  /ws save <set>        - snapshot equipped MH/OH into <set>, then update macros")
    print("  /ws sets              - list saved sets")
    print("  /ws delete <set>      - delete a set")
    print("  /ws update            - rewrite all managed macros from their templates")
    print("  /ws templates         - list managed macro templates")
    print("  /ws adopt <macro>     - use an existing macro's text (with placeholders) as a template")
    print("  /ws forget <macro>    - stop managing a macro (the macro itself is kept)")
    print("  /ws reset             - restore the default stance templates")
    print("  /ws debug             - toggle debug output")
end

SLASH_WEAPONSTASH1 = "/ws"
SLASH_WEAPONSTASH2 = "/weaponstash"

SlashCmdList["WEAPONSTASH"] = function(msg)
    local cmd, rest = trim(msg):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    rest = trim(rest)

    if cmd == "save" then
        WS:Snapshot(rest:lower())
    elseif cmd == "sets" or cmd == "list" then
        WS:ListSets()
    elseif cmd == "delete" or cmd == "del" then
        WS:DeleteSet(rest:lower())
    elseif cmd == "update" then
        WS:RequestMacroUpdate()
    elseif cmd == "templates" then
        WS:ListTemplates()
    elseif cmd == "adopt" then
        WS:AdoptMacro(rest)
    elseif cmd == "forget" then
        WS:ForgetTemplate(rest)
    elseif cmd == "reset" then
        WS.db.templates = ns.CopyTable(ns.DEFAULT_TEMPLATES)
        WS:Print("Default templates restored.")
    elseif cmd == "debug" then
        WS.db.debug = not WS.db.debug
        WS:Print("debug: " .. tostring(WS.db.debug))
    else
        printHelp()
    end
end
