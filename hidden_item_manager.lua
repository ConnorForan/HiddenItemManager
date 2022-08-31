-- Hidden Item Manager, by Connor (aka Ghostbroster)
-- Version 1.2
-- 
-- Manages a system of hidden Lemegeton Item Wisps to simulate the effects of passive items without actually granting the player those items (so they can't be removed or rerolled!).
-- Good for giving the effect of an item temporarily, making an item effect "innate" to a character, and all sorts of other stuff, probably.
-- Please keep in mind that the game has a TOTAL FAMILIAR LIMIT of 64 at a time! Each item provided by this is a wisp familiar!
-- So given that, please be careful and considerate when using this.
-- 
-- GitHub Page: https://github.com/ConnorForan/PauseScreenCompletionMarksAPI
-- Please refer to the GitHub page or the README file for more information and a guide.
-- 
-- Thanks Cake, DeadInfinity, Erfly, Taiga, and anyone else who might have helped figure out these wisp tricks.
--
-- Let me know if you have any problems or would like to suggest additional features/functions.
-- Discord: Connor#2143
-- Steam: Ghostbroster Connor
-- Email: ghostbroster@gmail.com
-- Twitter: @Ghostbroster

local HiddenItemManager = {}

local game = Game()

local kWispPos = Vector(-1000, -1000)
local kZeroVector = Vector.Zero

--------------------------------------------------
-- Initialization

local Callbacks = {}

local function AddCallback(callbackID, func, param)
	table.insert(Callbacks, {
		Callback = callbackID,
		Func = func,
		Param = param,
	})
end

local initialized = false
function HiddenItemManager:Init(mod)
	if not initialized then
		HiddenItemManager.Mod = mod
		
		for _, tab in pairs(Callbacks) do
			mod:AddCallback(tab.Callback, tab.Func, tab.Param)
		end
		
		initialized = true
	end
	return HiddenItemManager
end

--------------------------------------------------
-- Storage/Utility

local function LOG_ERROR(str)
	local prefix = ""
	if HiddenItemManager.Mod then
		prefix = "" .. HiddenItemManager.Mod.Name .. "."
	end
	local fullStr = "[" .. prefix .. "HiddenItemManager] ERROR: " .. str
	print(fullStr)
	Isaac.DebugString(fullStr)
end

local function LOG(str)
	local prefix = ""
	if HiddenItemManager.Mod then
		prefix = "" .. HiddenItemManager.Mod.Name .. "."
	end
	local fullStr = "[" .. prefix .. "HiddenItemManager]: " .. str
	Isaac.DebugString(fullStr)
end

local kDefaultGroup = "HIDDEN_ITEM_MANAGER_DEFAULT"

local function GetGroup(group)
	if group then
		return ""..group
	else
		return kDefaultGroup
	end
end

-- Hidden item wisp data sorted into a nested table.
-- player.InitSeed -> groupName -> CollectibleType -> wisp.InitSeed -> dataTable
-- This table is good for API lookups like checking if an item effect is active, or counting them.
local DATA = {}

-- Info on ALL hidden item wisps, simply just mapped by their InitSeeds.
-- This table is good for wisps looking up their own data, as well as for SaveData.
local INDEX = {}

-- Wisps slated for removal, by InitSeed key.
local WISPS_TO_REMOVE = {}

-- Removes all empty subtables from a given table.
local function CleanUp(tab)
	for k, v in pairs(tab) do
		if type(v) == "table" then
			if next(v) then
				CleanUp(v)
			else
				tab[k] = nil
			end
		end
	end
end
AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function()
	CleanUp(DATA)
end)

-- Find the DATA table entry for the given playerKey+group+itemID.
-- If allowInit is true, will initialize any missing subtables to empty.
-- Otherwise, returns nil if a subtable is not found.
local function FindData(playerKey, group, itemID, allowInit)
	group = GetGroup(group)
	if not DATA[playerKey] then
		if not allowInit then
			return
		end
		DATA[playerKey] = {}
	end
	if not group then
		return DATA[playerKey]
	end
	if not DATA[playerKey][group] then
		if not allowInit then
			return
		end
		DATA[playerKey][group] = {}
	end
	if not itemID then
		return DATA[playerKey][group]
	end
	if not DATA[playerKey][group][itemID] then
		if not allowInit then
			return
		end
		DATA[playerKey][group][itemID] = {}
	end
	return DATA[playerKey][group][itemID]
end

-- Insert new data into the DATA table.
local function InsertData(playerKey, group, itemID, wispKey, data)
	local tab = FindData(playerKey, group, itemID, true)
	tab[wispKey] = data
end

-- Removes data from the DATA table, if it exists.
local function ClearData(playerKey, group, itemID, wispKey)
	local tab = FindData(playerKey, group, itemID, false)
	if tab then
		tab[wispKey] = nil
	end
end

-- Strings are used for keys to be SaveData-friendly.
local function GetKey(entity)
	return ""..entity.InitSeed
end

-- Given the data entry for a hidden item, gets the wisp from the contained EntityPtr, if possible.
local function GetWisp(tab)
	if not tab or not tab.Wisp or not tab.Wisp.Ref or not tab.Wisp.Ref:Exists() then
		return nil
	end
	return tab.Wisp.Ref:ToFamiliar()
end

-- Given the data entry for a hidden item, gets the player from the contained EntityPtr.
-- If it's not found, tries checking the Player of the wisp too.
local function GetPlayer(tab)
	if not tab then return end
	
	if not tab.Player or not tab.Player.Ref or not tab.Player.Ref:Exists() then
		local wisp = GetWisp(tab)
		if wisp and wisp.Player and wisp.Player:Exists() then
			tab.Player = EntityPtr(wisp.Player)
			return wisp.Player
		end
		return nil
	end
	return tab.Player.Ref:ToPlayer()
end

local function KillWisp(wisp)
	if not wisp then return end
	
	if wisp.Player and wisp.SubType == CollectibleType.COLLECTIBLE_MARS then
		player:TryRemoveNullCostume(NullItemID.ID_MARS)
	end
	
	-- Kill() after Remove() makes sure the effects of wisps are removed properly while still skipping the death animation/sounds.
	wisp:Remove()
	wisp:Kill()
end

-- Removes the hidden item wisp from both data tables with the given key.
local function RemoveWisp(key)
	local tab = INDEX[key]
	local player = GetPlayer(tab)
	local item = tab.Item
	
	WISPS_TO_REMOVE[key] = true
	
	if player then
		ClearData(GetKey(player), tab.Group, item, key)
	else
		-- Failed to find the player. Whatever, just make certain the data for this wisp gone.
		for playerKey, playerData in pairs(DATA) do
			ClearData(playerKey, tab.Group, item, key)
		end
	end
	
	INDEX[key] = nil
end

-- Called continuously on item wisps to make sure they STAY hidden.
local function KeepWispHidden(wisp)
	wisp.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
	wisp.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
	wisp.Visible = false
	wisp.Position = kWispPos
	wisp.Velocity = kZeroVector
end

-- Initializes (or re-initializes) an item wisp to be one of our hidden ones.
local function InitializeWisp(wisp)
	wisp:AddEntityFlags(EntityFlag.FLAG_NO_QUERY | EntityFlag.FLAG_NO_REWARD)
	wisp:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
	KeepWispHidden(wisp)
	wisp:RemoveFromOrbit()
	wisp:GetData().isHiddenItemManagerWisp = true
	
	local wispKey = GetKey(wisp)
	local tab = INDEX[wispKey]
	tab.WispKey = wispKey
	tab.Wisp = EntityPtr(wisp)
	tab.PlayerKey = GetKey(wisp.Player)
	tab.Player = EntityPtr(wisp.Player)
	tab.Initialized = true
end

-- Spawns a hidden item wisp.
local function SpawnWisp(player, itemID, duration, group, removeOnNewRoom, removeOnNewLevel)
	group = GetGroup(group)
	if not itemID or itemID < 1 then
		LOG_ERROR("Attempted to add invalid CollectibleType `" .. (itemID or "NULL") .. "` to group: " .. group)
	end
	if duration and duration < 1 then
		duration = nil
	end
	local wisp = player:AddItemWisp(itemID, kWispPos)
	local wispKey = GetKey(wisp)
	local tab = {
		Item = itemID,
		Group = group,
		Duration = duration,
		RemoveOnNewRoom = removeOnNewRoom,
		RemoveOnNewLevel = removeOnNewLevel,
		ErrorCount = 0,
		AddTime = game:GetFrameCount(),
	}
	InsertData(GetKey(player), group, itemID, wispKey, tab)
	INDEX[wispKey] = tab
	InitializeWisp(wisp)
	HiddenItemManager:ItemWispUpdate(wisp)
end

local function AddInternal(player, itemID, duration, group, removeOnNewRoom, removeOnNewLevel, numToAdd)
	if numToAdd < 1 then return end
	for i=1, numToAdd do
		SpawnWisp(player, itemID, duration, group, removeOnNewRoom, removeOnNewLevel)
	end
end

--------------------------------------------------
-- API Functions

-- Add a hidden item(s) that will persist through room and floor transitions.
function HiddenItemManager:Add(player, itemID, duration, numToAdd, group)
	AddInternal(player, itemID, duration, group, false, false, numToAdd or 1)
end

-- Add a hidden item(s) that will automatically expire when changing rooms.
function HiddenItemManager:AddForRoom(player, itemID, duration, numToAdd, group)
	AddInternal(player, itemID, duration, group, true, true, numToAdd or 1)
end

-- Add a hidden item(s) that will automatically expire when changing floors.
function HiddenItemManager:AddForFloor(player, itemID, duration, numToAdd, group)
	AddInternal(player, itemID, duration, group, false, true, numToAdd or 1)
end

-- Adds or removes copies of a hidden item within the group so that the total number of stacks is equal to targetStack.
function HiddenItemManager:CheckStack(player, itemID, targetStack, group)
	local currentStack = HiddenItemManager:CountStack(player, itemID, group)
	local diff = math.abs(currentStack - targetStack)
	
	if currentStack > targetStack then
		for i=1, diff do
			HiddenItemManager:Remove(player, itemID, group)
		end
	elseif currentStack < targetStack then
		HiddenItemManager:Add(player, itemID, -1, diff, group)
	end
end

-- Removes the oldest of a particular hidden item from the specified group.
function HiddenItemManager:Remove(player, itemID, group)
	local tab = FindData(GetKey(player), group, itemID)
	if tab then
		local removalCandidate
		for wispKey, data in pairs(tab) do
			if not removalCandidate or data.AddTime < removalCandidate.AddTime then
				removalCandidate = data
			end
		end
		RemoveWisp(removalCandidate.WispKey)
	end
end

-- Removes all copies of a particular item from the specified group.
function HiddenItemManager:RemoveStack(player, itemID, group)
	local tab = FindData(GetKey(player), group, itemID)
	if tab then
		for wispKey, _ in pairs(tab) do
			RemoveWisp(wispKey)
		end
	end
end

-- Removes all hidden items from the specified group.
function HiddenItemManager:RemoveAll(player, group)
	group = GetGroup(group)
	local pKey = GetKey(player)
	if DATA[pKey] then
		for itemID, wispList in pairs(DATA[pKey][group]) do
			for wispKey, _ in pairs(wispList) do
				RemoveWisp(wispKey)
			end
		end
	end
end

-- Returns true if the player has the given item within the specified group.
function HiddenItemManager:Has(player, itemID, group)
	local tab = FindData(GetKey(player), group, itemID)
	return tab ~= nil and next(tab) ~= nil
end

-- Returns how many hidden copies of a given item the player has within the specified group.
function HiddenItemManager:CountStack(player, itemID, group)
	local tab = FindData(GetKey(player), group, itemID)
	if not tab then return 0 end
	
	local count = 0
	for key, data in pairs(tab) do
		count = count + 1
	end
	return count
end

-- Returns a table representing all of the item effects a player currently has from a specified group.
function HiddenItemManager:GetStacks(player, group)
	local tab = FindData(GetKey(player), group)
	
	local output = {}
	
	for itemID, _ in pairs(tab) do
		local count = HiddenItemManager:CountStack(player, itemID, group)
		if count > 0 then
			output[itemID] = count
		end
	end
	
	return output
end

--------------------------------------------------
-- Save/Load

local function TableSize(tab)
	local count = 0
	for k, v in pairs(tab) do
		count = count + 1
	end
	return count
end

-- Returns the table that should be included in your SaveData when you save the game.
-- Pass this table into HiddenItemManager:LoadData() when you load your SaveData.
function HiddenItemManager:GetSaveData()
	LOG("Saving INDEX of size: " .. TableSize(INDEX))
	LOG("Saving WISPS_TO_REMOVE of size: " .. TableSize(WISPS_TO_REMOVE))
	
	return {
		INDEX = INDEX,
		WISPS_TO_REMOVE = WISPS_TO_REMOVE,
	}
end

-- Should be called whenever you load the SaveData for your mod to re-initialize any existing item wisps.
-- Give it the table returned by HiddenItemManager:GetSaveData().
function HiddenItemManager:LoadData(saveData)
	if saveData then
		INDEX = saveData.INDEX or {}
		WISPS_TO_REMOVE = saveData.WISPS_TO_REMOVE or {}
		for _, data in pairs(INDEX) do
			data.Initialized = false
		end
	else
		INDEX = {}
		WISPS_TO_REMOVE = {}
	end
	DATA = {}
	HiddenItemManager:CheckAllWisps()
end

--------------------------------------------------
-- Wisp Handling

function HiddenItemManager:CheckWisp(wisp)
	local wispKey = GetKey(wisp)
	local wispData = INDEX[wispKey]
	
	if not wisp:GetData().isHiddenItemManagerWisp and wispData then
		-- This wisp isn't marked as one of our wisps, but we're supposed to have a wisp with this InitSeed.
		KeepWispHidden(wisp)
		
		-- Check if there's already an active wisp for this effect.
		local existingWisp = GetWisp(wispData)
		if existingWisp then
			-- Another wisp with this InitSeed already exists.
			-- This can happen with Bazarus - familiars seem to get recreated to some extend when he flips.
			-- Remove this one regardless, we don't want two wisps with the same seed.
			wisp:GetData().isDuplicateHiddenItemManagerWisp = true
			return
		end
		
		if not wisp.Player then
			LOG_ERROR("Re-initialization of a wisp failed - no Player??")
			RemoveWisp(wispKey)
			return
		end
		
		-- Most likely, we've quit and continued a run. Re-initialize this wisp as a hidden one.
		InsertData(GetKey(wisp.Player), wispData.Group, wispData.Item, wispData)
		InitializeWisp(wisp)
	end
end
AddCallback(ModCallbacks.MC_FAMILIAR_INIT, HiddenItemManager.CheckWisp, FamiliarVariant.ITEM_WISP)

function HiddenItemManager:CheckAllWisps()
	for _, wisp in pairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, FamiliarVariant.ITEM_WISP)) do
		HiddenItemManager:CheckWisp(wisp:ToFamiliar())
	end
end

AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, continuing)
	if continuing then
		HiddenItemManager:CheckAllWisps()
	else
		DATA = {}
		INDEX = {}
	end
end)

function HiddenItemManager:PlayerUpdate(player)
	player:GetData().hiddenItemManagerLastUpdate = game:GetFrameCount()
end
AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, HiddenItemManager.PlayerUpdate)

local function IsHiddenBazarus(player)
	local lastUpdate = player:GetData().hiddenItemManagerLastUpdate
	return player and (not lastUpdate or game:GetFrameCount() - lastUpdate > 1)
			and (player:GetPlayerType() == PlayerType.PLAYER_LAZARUS_B or player:GetPlayerType() == PlayerType.PLAYER_LAZARUS2_B)
end

-- The keys of any wisps we've removed this frame.
local RemovedWisps = {}

function HiddenItemManager:ItemWispUpdate(wisp)
	if wisp:GetData().isDuplicateHiddenItemManagerWisp then
		KeepWispHidden(wisp)
		KillWisp(wisp)
		return
	end
	
	local key = GetKey(wisp)
	
	if wisp:GetData().isHiddenItemManagerWisp then
		KeepWispHidden(wisp)
		
		local data = INDEX[key]
		
		if not data then
			-- Tagged as a hidden item wisp, but no associated data.
			-- A weird case (aside from luamod) but not really a concern. Remove it.
			-- Make certain there's no data left over for this wisp, though.
			for playerKey, playerData in pairs(DATA) do
				for groupName, groupData in pairs(playerData) do
					ClearData(playerKey, groupName, wisp.SubType, key)
				end
			end
			wisp:GetData().isHiddenItemManagerWisp = false
			WISPS_TO_REMOVE[key] = true
		elseif data.Duration and data.AddTime + data.Duration < game:GetFrameCount() then
			-- Timed out.
			RemoveWisp(key)
		end
	end
	
	-- Kill the wisp if we're expecting to do so.
	-- Trying to account for some weird issues where Bazarus's inactive flip's wisps update once, the first time you change rooms.
	-- The hidden Bazarus' wisps will also still respawn even if the game "successfully" Remove()'d them post-flip.
	-- So don't try to remove wisps attached to hidden Bazarus.
	-- Also it looks like certain familiars get re-initialized somehow when Bazarus flips? Or something like that.
	-- This ends up triggering twice in one frame, same initseed/data, but different pointer address and FrameCount is reset.
	if WISPS_TO_REMOVE[key] then
		KeepWispHidden(wisp)
		if not IsHiddenBazarus(wisp.Player) then
			KillWisp(wisp)
			-- Don't actually unset WISPS_TO_REMOVE yet, since Bazarus does weird things where it seems like
			-- two nigh-identical versions a familiar update during the same frame during a flip.
			-- We want to catch and remove both versions, so just mark that a removal has been done for now.
			RemovedWisps[key] = true
		end
	end
end
AddCallback(ModCallbacks.MC_FAMILIAR_UPDATE, HiddenItemManager.ItemWispUpdate, FamiliarVariant.ITEM_WISP)

-- Clear any keys from WISPS_TO_REMOVE if we have removed those wisps this frame.
-- We can potentially remove more than one wisp for the same InitSeed in the same frame due to Bazarus flip shenanigans.
function HiddenItemManager:ResolveRemovedWisps()
	for key, _ in pairs(RemovedWisps) do
		WISPS_TO_REMOVE[key] = nil
	end
	RemovedWisps = {}
end

function HiddenItemManager:PostUpdate()
	HiddenItemManager:ResolveRemovedWisps()
	
	local wispsToRespawn = {}
	
	for key, data in pairs(INDEX) do
		local wisp = GetWisp(data)
		local player = GetPlayer(data)
		if data.Initialized and not wisp then
			if not player then
				--LOG_ERROR("Wisp `" .. key .. "` disappeared and player could not be found. Giving up on item #" .. data.Item .. " from group: " .. data.Group)
				RemoveWisp(key)
			elseif data.ErrorCount >= 10 then
				-- We tried to respawn a wisp like 10 times in a row, just give up.
				LOG_ERROR("Something is constantly removing the Item Wisps or preventing them from spawning! Giving up on item #" .. data.Item .. " from group: " .. data.Group)
				RemoveWisp(key)
			else
				if data.ErrorCount == 0 then
					LOG_ERROR("Wisp disappeared unexpectedly! Respawning wisp for item #" .. data.Item .. " from group: " .. data.Group)
				end
				wispsToRespawn[key] = data
				data.ErrorCount = data.ErrorCount + 1
			end
		end
	end
	
	-- When wisps disappear unexpectedly, try to respawn them at least a few times.
	-- We won't try forever, however, to avoid infinite fights with another mod.
	for oldKey, data in pairs(wispsToRespawn) do
		local player = GetPlayer(data)
		RemoveWisp(oldKey)
		local wisp = player:AddItemWisp(data.Item, kWispPos)
		local newKey = GetKey(wisp)
		InsertData(GetKey(player), data.Group, data.Item, newKey, data)
		INDEX[newKey] = data
		InitializeWisp(wisp)
	end
end
AddCallback(ModCallbacks.MC_POST_UPDATE, HiddenItemManager.PostUpdate)

function HiddenItemManager:PostNewRoom()
	for key, data in pairs(INDEX) do
		if data.RemoveOnNewRoom and data.AddTime < game:GetFrameCount() then
			RemoveWisp(key)
		else
			data.ErrorCount = 0
		end
	end
end
AddCallback(ModCallbacks.MC_POST_NEW_ROOM, HiddenItemManager.PostNewRoom)

function HiddenItemManager:PostNewLevel()
	for key, data in pairs(INDEX) do
		if data.RemoveOnNewLevel and data.AddTime < game:GetFrameCount() then
			RemoveWisp(key)
		end
	end
end
AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, HiddenItemManager.PostNewLevel)

-- Disables collisions for wisps.
function HiddenItemManager:ItemWispCollision(wisp)
	if wisp:GetData().isHiddenItemManagerWisp then
		return true
	end
end
AddCallback(ModCallbacks.MC_PRE_FAMILIAR_COLLISION, HiddenItemManager.ItemWispCollision, FamiliarVariant.ITEM_WISP)

-- Prevents wisps from taking or dealing damage.
function HiddenItemManager:ItemWispDamage(entity, damage, damageFlags, damageSourceRef, damageCountdown)
	if entity and entity.Type == EntityType.ENTITY_FAMILIAR and entity.Variant == FamiliarVariant.ITEM_WISP and entity:GetData().isHiddenItemManagerWisp then
		return false
	end
	
	if damageSourceRef.Type == EntityType.ENTITY_FAMILIAR and damageSourceRef.Variant == FamiliarVariant.ITEM_WISP
			and damageSourceRef.Entity and damageSourceRef.Entity:GetData().isHiddenItemManagerWisp then
		return false
	end
end
AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, HiddenItemManager.ItemWispDamage)

-- Prevents wisps from firing tears with book of virtues.
function HiddenItemManager:ItemWispTears(tear)
	if tear.SpawnerEntity and tear.SpawnerEntity.Type == EntityType.ENTITY_FAMILIAR
			and tear.SpawnerEntity.Variant == FamiliarVariant.ITEM_WISP
			and tear.SpawnerEntity:GetData().isHiddenItemManagerWisp then
		tear:Remove()
	end
end
AddCallback(ModCallbacks.MC_POST_TEAR_INIT, HiddenItemManager.ItemWispTears)

-- Protect the wisp from Sacrificial Altar by breaking its connection to the player briefly.
-- Thanks DeadInfinity for coming up with this trick.
AddCallback(ModCallbacks.MC_PRE_USE_ITEM, function()
	for _, data in pairs(INDEX) do
		local wisp = GetWisp(data)
		
		if wisp then
			-- Should already be removed from the orbit, but call RemoveFromOrbit again just to be sure.
			-- Setting the player to nil for a wisp thats currently in orbit crashes the game!
			wisp:RemoveFromOrbit()
			wisp.Player = nil
		end
	end
end, CollectibleType.COLLECTIBLE_SACRIFICIAL_ALTAR)

-- Restore the wisp's player connection after Sacrificial Altar is done (thanks again, Dead).
AddCallback(ModCallbacks.MC_USE_ITEM, function()
	for key, data in pairs(INDEX) do
		local wisp = GetWisp(data)
		local player = GetPlayer(data)
		
		if not player then
			LOG_ERROR("Somehow lost track of player during Sacrificial Altar protection. Giving up on item #" .. data.Item .. " from group: " .. data.Group)
			RemoveWisp(key)
		elseif wisp then
			wisp.Player = player
		end
	end
end, CollectibleType.COLLECTIBLE_SACRIFICIAL_ALTAR)

return HiddenItemManager
