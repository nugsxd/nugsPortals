# nugsPortals

Every Mythic+ dungeon teleport in one list, named for the **dungeon** it takes you to.

The game files them the other way round. Each expansion has a spellbook group called
*Hero's Path: \<expansion\>*, and inside it the portals carry lore names — *Path of the
Ruined City* is the one to Ara-Kara. Finding the portal for the dungeon your group just
formed for means knowing which expansion it came from and then which name is which.
This puts the dungeon first.

## What it shows

- **The current expansion and season** at the top.
- **This season** — the dungeons in the current Mythic+ rotation, each with its portal,
  wherever in the game that portal lives.
- **Dungeons** and **Raids**, each grouped by expansion, newest first, with every portal
  listed by where it goes.

Every section and every expansion folds with a click, and stays how you left it.

## Beside the Mythic+ page

Open the **Mythic+ Dungeons** tab of the Group Finder and a narrow panel docks on its
right with this season's dungeons, one row each. Click one to teleport. It goes away
with the page, and its own **x** hides it just for this visit. Turn it off with the
switch at the bottom of the main window, or `/np attach`.

It only reads the Group Finder's position to line up beside it — it never moves,
rescales or otherwise changes Blizzard's window, which is protected and would be
tainted by that.

Click a portal you have earned to teleport. The ones you have not are listed greyed out
so you can see what exists; **Hide unearned** takes them away. The search box matches
dungeon names, portal names and expansions.

## Where the names come from

Nothing is hard-coded. The portals are read from the game's own Hero's Path groups, and
each dungeon name is read from the portal's own description — *Teleport to the entrance
to …*. A new season or expansion shows up without an update.

The one cost: that description is English. On a client in another language the rows
fall back to the portal's own name, which is still right, just less helpful.

## Commands

```
/np                  open or close the list
/np attach           the panel beside the Mythic+ page, on or off
/np minimap          show or hide the minimap button
/np dump             record what the game says about every portal
```

There is also a keybinding under Key Bindings, AddOns.

## Notes

- **Not in combat.** The buttons that cast portals are locked by the game during a
  fight, so the list closes when combat starts and will not open during one. A portal
  cannot be cast in combat anyway.
- If a dungeon name comes out wrong, `/np dump` then `/reload` writes everything
  the game said into the saved variables, which is what it gets fixed from.
