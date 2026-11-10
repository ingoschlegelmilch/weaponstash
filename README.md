# WeaponStash

A small, dependency-free **World of Warcraft Classic Era** addon for warriors.
It stores your main hand / off hand weapons per stance and keeps the
`/equipslot` lines in your own stance swap / weapon swap macros up to date,
so you never have to retype item names after an upgrade.

## Window

`/ws` opens the window:

- **Dropdown**: pick a stance (Battle / Defensive / Berserker) or any custom set.
  It opens on the stance you're currently in.
- **Main Hand / Off Hand slots**: drag a weapon from your bags or character pane onto
  a slot to assign it (the item stays where it was; only its name is recorded).
  Right-click a slot to clear it. A two-hander in the main hand clears the off hand.
- **Use Equipped**: snapshot what you're wielding right now into the selected set.
- **Equip Set**: equip the selected set (out of combat; use your macros in combat).
- **Macros to keep in sync**: every General and Character macro you have. Check the
  ones that should follow the selected set. Hover a macro to see its text and what
  it will look like with this set's weapons.

## What gets changed in a macro

Only lines of the form `/equipslot [conditions] 16 <item>` and
`/equipslot [conditions] 17 <item>` are touched, and only the item name on them.
Everything else (`#showtooltip`, `/cast`, the conditions themselves) stays as written.

```
#showtooltip Shield Bash
/cast [nostance:2] Defensive Stance
/equipslot 16 Old Sword         -> /equipslot 16 Quel'Serrar
/equipslot 17 Old Shield        -> /equipslot 17 Draconian Deflector
/cast Shield Bash
```

Two-handers need special handling:

- If the set is a **two-hander** and the macro has a `16` line, its `17` lines are
  removed, because equipping an off hand would knock the two-hander back off.
- If the set has an **off hand** but the macro has no `17` line (e.g. it was removed
  for a two-hander earlier), one is added after each `16` line, with the same conditions.
- With a one-hander and an empty off hand, `17` lines are left alone.

Not touched: `/equip` lines, other slots, and `/equipslot` lines with several
`;`-separated clauses (marked with `*` in the list).

Some macros are shown but can't be checked, because rewriting them would break them:

- **Per-stance lines**: e.g. `/equipslot [stance:1] 16 A` plus `/equipslot [stance:2] 16 B`.
  The macro switches weapons by stance on its own, so it can't follow a single set.
- **Duplicate name**: another macro in the same tab has the same name. Macros have
  no stable ID, so WeaponStash can't tell which one you meant. Rename one of them.

A linked macro that has been renamed or deleted shows up at the bottom of the list
under "Linked macros that no longer exist"; uncheck it there to drop the link.

## Slash commands

| Command                  | Description                                            |
|--------------------------|--------------------------------------------------------|
| `/ws`                    | Toggle the window (`/ws help` lists commands)          |
| `/ws save <set>`         | Snapshot equipped MH/OH into `<set>` and update macros |
| `/ws sets`               | List saved sets                                        |
| `/ws delete <set>`       | Delete a set                                           |
| `/ws link <set> <macro>` | Keep a macro in sync with `<set>`                      |
| `/ws unlink <macro>`     | Stop updating a macro                                  |
| `/ws links`              | List linked macros                                     |
| `/ws update`             | Rewrite all linked macros now                          |
| `/ws debug`              | Toggle debug output                                    |

The stance sets are named `battle`, `defensive` and `berserker`.

## Notes

- Macros can't be edited in combat; changes made in combat apply when combat ends.
- Macro text is limited to 255 characters; a macro that would exceed it is skipped.
- Sets and links are stored per character in `WeaponStashCharDB`. General macros
  are shared by all your characters, so linking one from two characters means
  whichever character updates last wins.

## Install

The addon itself is the `WeaponStash/` folder. Copy that whole folder into your
client's `Interface/AddOns`:

```
World of Warcraft/
└── _classic_era_/            (or _anniversary_, ...)
    └── Interface/
        └── AddOns/
            └── WeaponStash/  <- this repo's WeaponStash/ folder
                ├── WeaponStash.toc
                └── *.lua
```

Then `/reload` in game. Keep the folder name `WeaponStash`; it must match the `.toc`.

Or let the script do it (macOS, default install location; set `WOW_DIR` otherwise):

```sh
scripts/install.sh _classic_era_          # copy (run again after changes)
scripts/install.sh --link _classic_era_   # symlink: repo edits show up after /reload
```

`## Interface: 11509, 16001, 20506` covers Classic Era 1.15.9, WoW Forever 1.60.1
(folder `_forever_`) and TBC Anniversary 2.5.6. The numbers change with each client
patch; check one in game with `/dump select(4, GetBuildInfo())`.

WoW Forever runs on the modern (Mainline, Midnight-era) client. The code has been
checked against Blizzard's Forever 1.60.1 UI source: every API, template, event and
`/equipslot` behaviour it relies on is present and unrestricted there, and the warrior
stances keep their classic spell IDs. It hasn't been run in the Forever client yet.

## Layout

| Path                          | Purpose                                              |
|-------------------------------|------------------------------------------------------|
| `WeaponStash/WeaponStash.toc` | Addon manifest + load order                          |
| `WeaponStash/Core.lua`        | Init, saved variables, events, slash commands        |
| `WeaponStash/Stash.lua`       | Weapon sets: snapshot, slot assignment, equipping    |
| `WeaponStash/Macros.lua`      | Macro listing, linking, `/equipslot` line rewriting  |
| `WeaponStash/UI.lua`          | Window: set dropdown, weapon slots, macro checklist  |
| `scripts/install.sh`          | Copy or symlink the addon into a client's AddOns     |
