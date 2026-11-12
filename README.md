# WeaponStash

A small, dependency-free **World of Warcraft Classic Era** addon for warriors.
It snapshots your currently equipped main hand / off hand into named sets and keeps
your stance swap / weapon swap macros up to date with those item names, so you
never have to retype `/equipslot` lines after an upgrade.

## Usage

1. Equip the weapons you use in a stance, then save them as a set:

   ```
   /ws save defensive     -- e.g. 1H + shield
   /ws save battle        -- e.g. 2H
   /ws save berserker     -- e.g. dual wield
   ```

2. Every save rewrites the managed macros. By default these are three character
   macros, created when their set exists:

   | Macro          | Body                                                            |
   |----------------|-----------------------------------------------------------------|
   | `WS Battle`    | `/cast [nostance:1] Battle Stance` + equip set `battle`         |
   | `WS Defensive` | `/cast [nostance:2] Defensive Stance` + equip set `defensive`   |
   | `WS Berserker` | `/cast [nostance:3] Berserker Stance` + equip set `berserker`   |

3. Drag them onto your bars. When you get a new weapon, equip it and `/ws save <set>` again.

## Custom macros

Write a macro in the normal macro UI using placeholders, then hand it to the addon:

```
#showtooltip
/cast Shield Bash
{equip:defensive}
```

```
/ws adopt My Bash
```

The text is stored as a template and the macro is rewritten from it whenever a set changes.

| Placeholder    | Expands to                                                         |
|----------------|--------------------------------------------------------------------|
| `{mh:<set>}`   | main hand item name                                                |
| `{oh:<set>}`   | off hand item name (empty for a 2H set)                            |
| `{equip:<set>}`| `/equipslot 16 <mh>` and, if the set has one, `/equipslot 17 <oh>` |

A macro whose sets aren't all saved yet is skipped (see `/ws templates`).

## Commands

| Command              | Description                                              |
|----------------------|----------------------------------------------------------|
| `/ws save <set>`     | Snapshot equipped MH/OH into `<set>` and update macros   |
| `/ws sets`           | List saved sets                                          |
| `/ws delete <set>`   | Delete a set                                             |
| `/ws update`         | Rewrite all managed macros                               |
| `/ws templates`      | List managed macros, their templates and status          |
| `/ws adopt <macro>`  | Manage an existing macro containing placeholders         |
| `/ws forget <macro>` | Stop managing a macro (the macro itself stays)           |
| `/ws reset`          | Restore the three default stance templates               |
| `/ws debug`          | Toggle debug output                                      |

## Notes

- Macros can't be edited in combat; a save during combat is applied when combat ends.
- Macro text is limited to 255 characters; long weapon names in big templates may hit it.
- Sets and templates are stored per character in `WeaponStashCharDB`.

## Layout

| File              | Purpose                                         |
|-------------------|-------------------------------------------------|
| `WeaponStash.toc` | Addon manifest + load order                     |
| `Core.lua`        | Init, saved variables, events, slash commands   |
| `Stash.lua`       | Snapshotting equipped weapons into sets         |
| `Macros.lua`      | Template rendering and macro create/edit        |

## Install

Copy (or symlink) the folder into:

```
World of Warcraft/_classic_era_/Interface/AddOns/WeaponStash
```

The folder name must match the `.toc` (`WeaponStash`). Then `/reload`.

`## Interface: 11509, 16001` targets Classic Era 1.15.9 and WoW: Forever 1.60.1; bump these if a client version changes (check in-game with `/dump select(4, GetBuildInfo())`).
