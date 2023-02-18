-- Hidden Item Manager, by Connor (aka Ghostbroster)
-- Version 2.0
-- 
-- Manages a system of hidden Lemegeton Item Wisps to simulate the effects of passive items without actually granting the player those items (so they can't be removed or rerolled!).
-- Good for giving the effect of an item temporarily, making an item effect "innate" to a character, and all sorts of other stuff, probably.
-- Please keep in mind that the game has a TOTAL FAMILIAR LIMIT of 64 at a time! Each item provided by this is a wisp familiar!
-- So given that, please be careful and considerate when using this.
-- 
-- GitHub Page: https://github.com/ConnorForan/HiddenItemManager
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
local kPersistentWispMarker = 617413666
local kEarlyCallbackPriority = -9999
local kLateCallbackPriority = 9999

--------------------------------------------------
-- Initialization

local Callbacks = {}

local function AddCallback(callbackID, func, param, priority)
	table.insert(Callbacks, {
		Callback = callbackID,
		Func = func,
		Param = param,
		Priority = priority or kEarlyCallbackPriority,
	})
end
local function AddLateCallback(callbackID, func, param)
	AddCallback(callbackID, func, param, kLateCallbackPriority)
end

local initialized = false
function HiddenItemManager:Init(mod)
	if not initialized then
		HiddenItemManager.Mod = mod
		
		for _, tab in ipairs(Callbacks) do
			mod:AddPriorityCallback(tab.Callback, tab.Priority, tab.Func, tab.Param)
		end
		
		HiddenItemManager.WispTag = "HiddenItemManager:" .. mod.Name
		
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

-- Cache for EntityPtrs to wisps.
local WISP_PTRS = {}

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

local function GetWispKey(entity)
	if not entity then return end
	return ""..entity.InitSeed
end

local function GetPlayerKey(player)
	if not player then return end
	if player.Type ~= EntityType.ENTITY_PLAYER then
		LOG_ERROR("Found invalid player reference in GetPlayerKey!")
		return
	end
	
	-- Player InitSeeds are inconsistent with Tainted Lazarus & co-op.
	-- However, using collectible RNG seeds seems to work, even if potentially breakable.
	player = player:ToPlayer()
	if player:GetPlayerType() == PlayerType.PLAYER_LAZARUS2_B then
		return ""..player:GetCollectibleRNG(CollectibleType.COLLECTIBLE_INNER_EYE):GetSeed() -- flip sucks
	end
	return ""..player:GetCollectibleRNG(CollectibleType.COLLECTIBLE_SAD_ONION):GetSeed()
end

-- Given the data entry for a hidden item, gets the wisp.
local function GetWisp(tab)
	if not tab then return end
	
	local ptr = WISP_PTRS[tab.WispKey]
	if ptr and ptr.Ref then
		if ptr.Ref.Type == EntityType.ENTITY_FAMILIAR and ptr.Ref.Variant == FamiliarVariant.ITEM_WISP then
			return ptr.Ref:ToFamiliar()
		end
		LOG_ERROR("Found invalid wisp reference in GetWisp!")
	end
end

-- Given the data entry for a hidden item, gets the player.
local function GetPlayer(tab)
	if not tab then return end
	
	local wisp = GetWisp(tab)
	if wisp and wisp.Player then
		if wisp.Player.Type ~= EntityType.ENTITY_PLAYER then
			LOG_ERROR("Found an invalid Player reference in GetPlayer!")
			return
		end
		return wisp.Player
	end
	
	-- Player wasn't found on the wisp. Might be due to us temporarily nulling `wisp.Player` to avoid Sacrificial Altar. See if we can find the player.
	for i=0, game:GetNumPlayers()-1 do
		local player = game:GetPlayer(i)
		if GetPlayerKey(player) == tab.PlayerKey then
			return player
		end
	end
end

local function KillWisp(wisp)
	if not wisp then return end
	
	if wisp.Player and wisp.Player.Type == EntityType.ENTITY_PLAYER and wisp.Player:Exists() and wisp.SubType == CollectibleType.COLLECTIBLE_MARS then
		wisp.Player:TryRemoveNullCostume(NullItemID.ID_MARS)
	end
	
	wisp:Remove()
	
	if wisp.Player and wisp.Player.Type ~= EntityType.ENTITY_PLAYER then
		LOG_ERROR("Found wisp with an invalid Player reference in KillWisp!")
	elseif wisp.Type == EntityType.ENTITY_FAMILIAR and wisp.Variant == FamiliarVariant.ITEM_WISP then
		-- Kill() after Remove() makes sure the effects of wisps are removed properly while still skipping the death animation/sounds.
		wisp:Kill()
	else
		LOG_ERROR("Found invalid wisp reference in KillWisp!")
	end
end

-- Removes the hidden item wisp from both data tables with the given key.
local function RemoveWisp(key)
	local tab = INDEX[key]
	if not tab then return end
	local player = GetPlayer(tab)
	local item = tab.Item
	
	if player then
		ClearData(GetPlayerKey(player), tab.Group, item, key)
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

local function TagWisp(wisp)
	wisp:GetData().HIDDEN_ITEM_MANAGER_WISP = HiddenItemManager.WispTag
end

-- Returns true if the wisp is one owned by THIS instance of the HiddenItemManager library.
local function IsManagedWisp(wisp)
	return wisp:GetData().HIDDEN_ITEM_MANAGER_WISP == HiddenItemManager.WispTag
end

-- Returns true if the wisp is one owned by ANY instance of the HiddenItemManager library.
local function IsAnyHiddenItemManagerWisp(wisp)
	return wisp:GetData().HIDDEN_ITEM_MANAGER_WISP ~= nil
end

-- Leave behind a very specific value in the coins/keys/hearts fields of our wisps.
-- Only used as a fallback for wisp identification if all else fails, since these
-- fields are actually persistent across quit+continue.
-- Mainly used to delete wisps originally from this library that weren't "claimed" by any instance of it.
local function ApplyPersistentHiddenItemManagerMark(wisp)
	wisp.Coins = kPersistentWispMarker
	wisp.Hearts = kPersistentWispMarker
	wisp.Keys = kPersistentWispMarker
end

local function WasHiddenItemManagerWisp(wisp)
	return wisp.Coins == kPersistentWispMarker
		or wisp.Hearts == kPersistentWispMarker
		or wisp.Keys == kPersistentWispMarker
end

-- Initializes (or re-initializes) an item wisp to be one of our hidden ones.
local function InitializeWisp(wisp)
	wisp:AddEntityFlags(EntityFlag.FLAG_NO_QUERY | EntityFlag.FLAG_NO_REWARD)
	wisp:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
	KeepWispHidden(wisp)
	wisp:RemoveFromOrbit()
	TagWisp(wisp)
	
	local wispKey = GetWispKey(wisp)
	local tab = INDEX[wispKey]
	tab.WispKey = wispKey
	WISP_PTRS[wispKey] = EntityPtr(wisp)
	tab.PlayerKey = GetPlayerKey(wisp.Player)
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
	local wispKey = GetWispKey(wisp)
	local tab = {
		Item = itemID,
		Group = group,
		Duration = duration,
		RemoveOnNewRoom = removeOnNewRoom,
		RemoveOnNewLevel = removeOnNewLevel,
		ErrorCount = 0,
		AddTime = game:GetFrameCount(),
	}
	InsertData(GetPlayerKey(player), group, itemID, wispKey, tab)
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
	local tab = FindData(GetPlayerKey(player), group, itemID)
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
	local tab = FindData(GetPlayerKey(player), group, itemID)
	if tab then
		for wispKey, _ in pairs(tab) do
			RemoveWisp(wispKey)
		end
	end
end

-- Removes all hidden items from the specified group.
function HiddenItemManager:RemoveAll(player, group)
	group = GetGroup(group)
	local pKey = GetPlayerKey(player)
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
	local tab = FindData(GetPlayerKey(player), group, itemID)
	return tab ~= nil and next(tab) ~= nil
end

-- Returns how many hidden copies of a given item the player has within the specified group.
function HiddenItemManager:CountStack(player, itemID, group)
	local tab = FindData(GetPlayerKey(player), group, itemID)
	if not tab then return 0 end
	
	local count = 0
	for key, data in pairs(tab) do
		count = count + 1
	end
	return count
end

-- Returns a table representing all of the item effects a player currently has from a specified group.
function HiddenItemManager:GetStacks(player, group)
	local tab = FindData(GetPlayerKey(player), group)
	
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
	LOG("Saving wisp index of size: " .. TableSize(INDEX))
	
	return {
		INDEX = INDEX,
	}
end

-- Should be called whenever you load the SaveData for your mod to re-initialize any existing item wisps.
-- Give it the table returned by HiddenItemManager:GetSaveData().
function HiddenItemManager:LoadData(saveData)
	if saveData then
		INDEX = saveData.INDEX or {}
		for _, data in pairs(INDEX) do
			data.Initialized = false
		end
	else
		INDEX = {}
	end
	DATA = {}
	HiddenItemManager.INITIALIZING = false
	for _, ptr in pairs(WISP_PTRS) do
		if ptr and ptr.Ref then
			HiddenItemManager:ItemWispUpdate(ptr.Ref:ToFamiliar())
		end
	end
	WISP_PTRS = {}
	HiddenItemManager:CheckWisps()
end

--------------------------------------------------
-- Wisp Handling

function HiddenItemManager:ItemWispUpdate(wisp)
	if HiddenItemManager.INITIALIZING then return end
	
	local wispKey = GetWispKey(wisp)
	local wispData = INDEX[wispKey]
	
	if wispData then
		KeepWispHidden(wisp)
		ApplyPersistentHiddenItemManagerMark(wisp)
		
		local player = wisp.Player
		local playerKey = GetPlayerKey(player)
		
		if not IsManagedWisp(wisp) then
			-- This wisp isn't marked as one of our wisps, but we're supposed to have a wisp with this InitSeed.
			
			-- Check if there's already an active wisp for this effect.
			local existingWisp = GetWisp(wispData)
			if existingWisp or not player or not playerKey then
				-- Another wisp with this InitSeed already exists.
				-- This can happen with Bazarus - familiars seem to get recreated to some extent when he flips.
				-- Remove this one regardless, we don't want two wisps with the same seed.
				KillWisp(wisp)
				return false
			end
			
			-- Most likely, we've quit and continued a run. Re-initialize this wisp as a hidden one.
			InsertData(playerKey, wispData.Group, wispData.Item, wispKey, wispData)
			InitializeWisp(wisp)
		end
		
		-- Check if timed wisp has expired.
		local timedOut = (wispData.Duration and wispData.AddTime + wispData.Duration < game:GetFrameCount())
		-- Remove the wisp if the player disappears or seems to get replaced.
		local playerGone = (not player or playerKey ~= wispData.PlayerKey)
		
		if timedOut or playerGone then
			RemoveWisp(wispKey)
			KillWisp(wisp)
			return false
		end
	elseif IsManagedWisp(wisp) then
		-- No data for this wisp, but it's marked as one of ours. Kill it.
		KeepWispHidden(wisp)
		KillWisp(wisp)
		return false
	end
	
	if IsManagedWisp(wisp) then
		return false
	end
end
AddCallback(ModCallbacks.MC_FAMILIAR_INIT, HiddenItemManager.ItemWispUpdate, FamiliarVariant.ITEM_WISP)
AddCallback(ModCallbacks.MC_FAMILIAR_UPDATE, HiddenItemManager.ItemWispUpdate, FamiliarVariant.ITEM_WISP)

function HiddenItemManager:ItemWispLateUpdate(wisp)
	if HiddenItemManager.INITIALIZING then return end
	
	local wispKey = GetWispKey(wisp)
	local wispData = INDEX[wispKey]
	
	if not wispData and not IsAnyHiddenItemManagerWisp(wisp) and WasHiddenItemManagerWisp(wisp) then
		-- This wisp was at one point a HiddenItemManager wisp, but no instance of HiddenItemManager has claimed it. Kill it.
		KeepWispHidden(wisp)
		KillWisp(wisp)
		return false
	end
end
AddLateCallback(ModCallbacks.MC_FAMILIAR_UPDATE, HiddenItemManager.ItemWispLateUpdate, FamiliarVariant.ITEM_WISP)

function HiddenItemManager:CheckWisps()
	for _, wisp in pairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, FamiliarVariant.ITEM_WISP)) do
		HiddenItemManager:ItemWispUpdate(wisp:ToFamiliar())
	end
end

function HiddenItemManager:PostGameStarted(continuing)
	HiddenItemManager.INITIALIZING = false
	HiddenItemManager:CheckWisps()
	HiddenItemManager:PostNewRoom()
end
AddLateCallback(ModCallbacks.MC_POST_GAME_STARTED, HiddenItemManager.PostGameStarted)

function HiddenItemManager:PostPlayerInit()
	local numPlayers = #Isaac.FindByType(EntityType.ENTITY_PLAYER, -1, -1, false, false)
	
	if numPlayers == 0 then
		-- New run or continued run.
		DATA = {}
		INDEX = {}
		WISP_PTRS = {}
		HiddenItemManager.INITIALIZING = true
	end
end
AddCallback(ModCallbacks.MC_POST_PLAYER_INIT, HiddenItemManager.PostPlayerInit)

function HiddenItemManager:PlayerUpdate(player)
	player:GetData().hiddenItemManagerLastUpdate = game:GetFrameCount()
end
AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, HiddenItemManager.PlayerUpdate)

local function IsActivePlayer(player)
	if not player then return false end
	local lastUpdate = player:GetData().hiddenItemManagerLastUpdate
	return lastUpdate and game:GetFrameCount() - lastUpdate <= 1
end

function HiddenItemManager:PostUpdate()
	if HiddenItemManager.INITIALIZING then
		LOG_ERROR("Initialization may not have finished correctly? Did someone return non-nil in MC_POST_GAME_STARTED?")
		HiddenItemManager.INITIALIZING = false
	end
	
	if HiddenItemManager.DoingSacrificialAltarProtection then
		LOG_ERROR("Sacrificial Altar protection didn't finish on MC_USE_ITEM - was the activation canceled?")
		HiddenItemManager:FinishSacrificialAltarProtection()
	end
	
	local wispsToRespawn = {}
	
	for key, data in pairs(INDEX) do
		local wisp = GetWisp(data)
		local player = GetPlayer(data)
		-- Ignore missing wisps if the player isn't found (could be due to something like Bazarus).
		if data.Initialized and not wisp and IsActivePlayer(player) then
			if data.ErrorCount >= 10 then
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
		local newKey = GetWispKey(wisp)
		InsertData(GetPlayerKey(player), data.Group, data.Item, newKey, data)
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
	if IsManagedWisp(wisp) then
		return true
	end
end
AddCallback(ModCallbacks.MC_PRE_FAMILIAR_COLLISION, HiddenItemManager.ItemWispCollision, FamiliarVariant.ITEM_WISP)

-- Prevents wisps from taking or dealing damage.
function HiddenItemManager:ItemWispDamage(entity, damage, damageFlags, damageSourceRef, damageCountdown)
	if entity and entity.Type == EntityType.ENTITY_FAMILIAR and entity.Variant == FamiliarVariant.ITEM_WISP and IsManagedWisp(entity) then
		return false
	end
	
	if damageSourceRef.Type == EntityType.ENTITY_FAMILIAR and damageSourceRef.Variant == FamiliarVariant.ITEM_WISP
			and damageSourceRef.Entity and IsManagedWisp(damageSourceRef.Entity) then
		return false
	end
end
AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, HiddenItemManager.ItemWispDamage)

-- Prevents wisps from firing tears with book of virtues.
function HiddenItemManager:ItemWispTears(tear)
	if tear.SpawnerEntity and tear.SpawnerEntity.Type == EntityType.ENTITY_FAMILIAR
			and tear.SpawnerEntity.Variant == FamiliarVariant.ITEM_WISP
			and IsManagedWisp(tear.SpawnerEntity) then
		tear:Remove()
		return true
	end
end
AddCallback(ModCallbacks.MC_POST_TEAR_INIT, HiddenItemManager.ItemWispTears)

-- Protect the wisp from Sacrificial Altar by breaking its connection to the player briefly.
-- Thanks DeadInfinity for coming up with this trick.
function HiddenItemManager:StartSacrificialAltarProtection()
	LOG("Detected Sacrificial Altar activation. Temporarily nulling wisp.Player...")
	for _, data in pairs(INDEX) do
		local wisp = GetWisp(data)
		
		if wisp then
			wisp:GetData().hiddenItemManagerCachedPlayer = wisp.Player
			-- Should already be removed from the orbit, but call RemoveFromOrbit again just to be sure.
			-- Setting the player to nil for a wisp thats currently in orbit crashes the game!
			wisp:RemoveFromOrbit()
			wisp.Player = nil
		end
	end
	HiddenItemManager.DoingSacrificialAltarProtection = true
	LOG("Sacrificial Altar handling underway...")
end
AddCallback(ModCallbacks.MC_PRE_USE_ITEM, HiddenItemManager.StartSacrificialAltarProtection, CollectibleType.COLLECTIBLE_SACRIFICIAL_ALTAR)

-- Restore the wisp's player connection after Sacrificial Altar is done (thanks again, Dead).
function HiddenItemManager:FinishSacrificialAltarProtection()
	LOG("Detected Sacrificial Altar resolution. Fixing wisp.Player...")
	HiddenItemManager.DoingSacrificialAltarProtection = nil
	for key, data in pairs(INDEX) do
		local wisp = GetWisp(data)
		if wisp then
			local player = wisp:GetData().hiddenItemManagerCachedPlayer or GetPlayer(data)
			
			if player then
				wisp.Player = player
			else
				LOG_ERROR("Somehow lost track of player during Sacrificial Altar protection. Giving up on item #" .. data.Item .. " from group: " .. data.Group)
				if wisp then
					wisp.Player = Isaac.GetPlayer()  -- De-nil `wisp.Player` to avoid crashing if this somehow happens.
				end
				RemoveWisp(key)
			end
			
			wisp:GetData().hiddenItemManagerCachedPlayer = nil
		end
	end
	LOG("Sacrificial Altar handling completed.")
end
AddCallback(ModCallbacks.MC_USE_ITEM, HiddenItemManager.FinishSacrificialAltarProtection, CollectibleType.COLLECTIBLE_SACRIFICIAL_ALTAR)

AddCallback(ModCallbacks.MC_USE_ITEM, function()
	LOG("Detected Genesis activation. Clearing all wisps.")
	INDEX = {}
	DATA = {}
	for _, ptr in pairs(WISP_PTRS) do
		if ptr and ptr.Ref then
			HiddenItemManager:ItemWispUpdate(ptr.Ref:ToFamiliar())
		end
	end
	WISP_PTRS = {}
	LOG("Genesis handling completed.")
end, CollectibleType.COLLECTIBLE_GENESIS)

return HiddenItemManager
