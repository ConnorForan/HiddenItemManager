# Hidden Item Manager
A library for Binding of Isaac: Repentance mods for granting the effects of passive items to a player without actually giving the player the item.

This means that the player can be given the effect of the item, but it cannot be rerolled or otherwise lost.

Good for giving the effect of an item temporarily, making the effect of an item innate to a character, and probably all sorts of other stuff.

## How does it work?
Hidden Lemegeton Item Wisps. The library automatically handles the spawning of management of the wisps so you only have to tell it what you want.

Many of the possible problems with using these wisps have been solved by various people:

 - The hidden wisps are removed from orbiting the player, so other wisps aren't affected.
 - The hidden wisps are immune to Sacrificial Altar.
 - The hidden wisps do not fire tears if you have Book of Virtues.
 - The hidden wisps remove their effects properly when removed and do not make any effects or noise on "death".
 - The hidden wisps can be properly maintained through quit and continue (assuming SaveData is handled properly and no errors occur).

## A word of warning
Please keep in mind that the game has a TOTAL FAMILIAR LIMIT of 64 at a time! Each item provided by this library is a wisp familiar!

So given that, please be careful and considerate when using this.

## How to use?
There's a bunch of different potential applications for this, so I tried to provide a flexible set of functions.


### Setup

`"include()"` the library once when your mod first loads. Make sure to call its Init function and pass a reference to your mod, as well.

```lua
mod.HiddenItemManager = include("hidden_item_manager"):Init(mod)
```

### What are "Groups?"

Every one of the following functions has an optional "group" parameter.

Essentially, groups are treated as completely seperate instances. If you add an item effect with group "A", you can't remove it from group "B". And if you try to count how many of a particular item is in group "A", it won't include items in group "B".

Note that not providing a group still places it in a group: The "HIDDEN_ITEM_MANAGER_DEFAULT" group.

You should specify groups if you have more than one thing using this library in your mod if they have a chance to overlap.

For example, if you have two different use-cases that may need to manually add/remove or count a stack of item effects, and its possible for both use-cases to choose the same item, they'd end up conflicting with each other if they're in the same group. Say Item "A" wants to give the effects of 2 Mutant Spiders, and item "B" wants to add the effect of 1 Mutant Spider, if they're in the same group they might not stack since they see the effect is already present.

Groups aren't much of a concern if all you're doing is adding effects on a timer or  for the room/floor, or if your different use-cases will never overlap by picking the same items.

Anyway let's just get into the functions.

### Add(For)...

These functions are the best for temporary effects, such as per-room or with a fixed duration.

```lua
-- Adds an item effect that won't remove itself on room or floor change.
HiddenItemManager:Add(player, itemID, duration, numToAdd, group)
-- Adds an item effect for the current room only.
HiddenItemManager:AddForRoom(player, itemID, duration, numToAdd, group)
-- Adds an item effect for the current floor only.
HiddenItemManager:AddForFloor(player, itemID, duration, numToAdd, group)
```

Duration is optional. Defaults to "infinite" if not specified. 0 and -1 are also interpreted as "infinite".

Examples:

```lua
-- Add the Sad Onion effect for 60 seconds (30*60 frames).
HiddenItemManager:Add(player, CollectibleType.COLLECTIBLE_SAD_ONION, 30 * 60)

-- Add the Sad Onion effect for the current room.
HiddenItemManager:AddForRoom(player, CollectibleType.COLLECTIBLE_SAD_ONION)

-- Add the Sad Onion effect for the current floor.
HiddenItemManager:AddForFloor(player, CollectibleType.COLLECTIBLE_SAD_ONION)
```

Mixing permanant and temporary effects in the same group is not reccomended if Removing or Counting permanant effects is needed.

### CheckStack

Inspired by CheckFamiliar, this function is good for continually specifying the number of stacks of an item effect that you want active at the moment.

```lua
HiddenItemManager:(player, itemID, targetStack, group)
```

Effects will be added or removed as needed to meet the desired stack. Good for effects that may need to get added or removed based on logic in your code: You can just call this every frame with whatever the current stack should be.

Not reccomended to use this function in the same group as temporary effects, if the items used might overlap.

Example:

```lua
-- Grants one stack of Caffeine Pill for every nearby enemy. (They'll all be removed if no enemies are nearby).
-- This would be called every frame to keep the stack size updated.
-- This is silly, probably shouldn't do something like this with no upper limit but it's a good example.
local numNearbyEnemies = #Isaac.FindInRadius(player.Position, 125, EntityPartition.ENEMY)
HiddenItemManager:CheckStack(player, CollectibleType.COLLECTIBLE_CAFFEINE_PILL, numNearbyEnemies)
```

### Has / CountStack

```lua
-- Returns true if the player has the given item in the specified group.
HiddenItemManager:Has(player, itemID, group)

-- Returns the number of copies of a given item the player has in the specified group.
HiddenItemManager:CountStack(player, itemID, group)
```

Example:

```lua
-- Adds the effect of "Sad Onion" if it does not already exist in the group "MY_GROUP".
-- Using a group makes sure this stacks properly even if another use-case has applied the Sad Onion as an effect.
if not HiddenItemManager:Has(player, CollectibleType.COLLECTIBLE_SAD_ONION, "MY_GROUP") then
	HiddenItemManager:Add(player, CollectibleType.COLLECTIBLE_SAD_ONION, -1, 1, "MY_GROUP")
end
```

### Remove...

```lua
-- Removes one copy of the given item from the specified group.
HiddenItemManager:Remove(player, itemID, group)
-- Removes ALL copies of the given item from the specified group.
HiddenItemManager:RemoveStack(player, itemID, group)
-- Removes ALL effects from the specified group.
HiddenItemManager:RemoveAll(player, group)
```

Functions for removing effects. Primarily needed for removing otherwise permanant effects (though `"CheckStack()"` works well for that purpose). `"Remove()"` will remove the oldest effect for the given item, so it's not reccomended to put temporary and "permanant" effects in the same group unless they'll never use the same items.

### GetStacks

```lua
HiddenItemManager:GetStacks(player, group)
```

Returns a table containing the counts of all items the player currently has, within the specified group.

Would return a table with a format akin to this:

```lua
{
	[CollectibleType.COLLECTIBLE_SAD_ONION] = 1,
	[CollectibleType.COLLECTIBLE_CAFFEINE_PILL] = 3,
}
```

Note that the table is only accurate to the time when the function was called and does not update automatically.


### (IMPORTANT!!) Saving and Loading

To keep the wisps behaving correctly on quit and continue, you'll need to add its info to your SaveData.

Essentially, whenever you save your mod's data (such as on MC_POST_NEW_LEVEL and MC_PRE_GAME_EXIT), be sure to include this library's data:

```lua
local hiddenItemData = HiddenItemManager:GetSaveData()
-- Include` hiddenItemData` in your SaveData table!
YourSaveDataTable.HIDDEN_ITEM_DATA = hiddenItemData
```

Then, when you Load your SaveData on run continue, make sure to pass the data back to the library:

```lua
HiddenItemManager:LoadData(YourSaveDataTable.HIDDEN_ITEM_DATA)
```

If you don't do this, hidden wisps will probably turn into completely normal Lemegeton wisps on continue.

## Possible issues / concerns

`luamod` will either remove all active wisp effects, or try to re-load the active wisp effects from the most recent save (will most likely result in removing them all anyway since the wisps are gone). Just keep that in mind when testing.

If some kind of conflict causes wisps to disappear unexpectedly, or prevents them from spawning, the library will attempt to respawn the wisps. However, it will only do so 10 times in a row before giving up. It will print errors into the console/logs if this occurs, though.

## Closing thoughts

If you find any bugs, or have requests/suggestions for functions/features to be added to this library, just let me know!

```
Discord: Connor#2143
Steam: Ghostbroster Connor
Email: ghostbroster@gmail.com
Twitter: @Ghostbroster
```

Thanks Cake, DeadInfinity, Erfly, Taiga, and anyone else who might have helped figure out these wisp tricks.
