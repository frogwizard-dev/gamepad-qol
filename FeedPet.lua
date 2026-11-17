-- Feed pet in one press: casts Feed Pet straight onto the best food in your bags, so the bag window never
-- opens (cast from the action bar, Feed Pet opens the gamepad bags, which on Forever can close again at
-- once). A secure button of ours runs "/cast Feed Pet" then "/use <bag> <slot>"; the macro can't change
-- in combat, so the food is picked outside it, whenever bags, the pet or levels change.
local _, ns = ...

local FEED_PET = 6991

local function KnowsFeedPet()
	return (IsPlayerSpell and IsPlayerSpell(FEED_PET)) or (IsSpellKnown and IsSpellKnown(FEED_PET)) or false
end

local function SpellName()
	if C_Spell and C_Spell.GetSpellName then
		return C_Spell.GetSpellName(FEED_PET)
	end
	return GetSpellInfo and (GetSpellInfo(FEED_PET))
end

local function NumBags()
	local constants = Constants and Constants.InventoryConstants
	return constants and constants.NumBagSlots or NUM_BAG_SLOTS or 4
end

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- A food in your bags whose details hadn't loaded at the last pick: only then does item info arriving pick again (an
-- auction house scan sends thousands of those).
local waitingInfo = false

-- bag, slot, item name of the food to use; nil if there's none. Food at most 10 levels below the pet
-- does the most for its happiness: the lowest of those (better food lasts), else the highest it eats.
local function PickFood()
	waitingInfo = false
	if not (C_PetInfo and C_PetInfo.CanPetEatItem) or not UnitExists("pet") then
		return nil
	end
	local petLevel = UnitLevel("pet") or 1
	local bestGood, bestAny
	for bag = 0, NumBags() do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			-- Not loaded yet, so whether the pet eats it may not be known either: asked for, and picked again when it comes.
			if info and info.itemID and C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(info.itemID) then
				waitingInfo = true
				C_Item.RequestLoadItemDataByID(info.itemID)
			elseif info and info.itemID and C_PetInfo.CanPetEatItem(info.itemID) then
				local name, _, _, itemLevel = GetItemInfo(info.itemID)
				if not name then waitingInfo = true end
				if name then
					local food = { bag = bag, slot = slot, name = name, level = itemLevel or 0, count = info.stackCount or 1 }
					if food.level >= petLevel - 10 then
						-- Lowest level first; then the smaller stack, to free a slot sooner.
						if not bestGood or food.level < bestGood.level
							or (food.level == bestGood.level and food.count < bestGood.count) then
							bestGood = food
						end
					elseif not bestAny or food.level > bestAny.level then
						bestAny = food
					end
				end
			end
		end
	end
	local food = bestGood or bestAny
	if food then
		return food.bag, food.slot, food.name
	end
end

local button = CreateFrame("Button", "GamepadQoLFeedPetButton", UIParent, "SecureActionButtonTemplate")
button:SetSize(1, 1)
button:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -20, 20)
button:RegisterForClicks("AnyDown", "AnyUp")
button:SetAttribute("type", "macro")
button:SetAttribute("macrotext", "")

local foodName  -- what the macro feeds now, for the message

local function UpdateMacro()
	if InCombatLockdown() then
		return false
	end
	local spell = SpellName()
	local bag, slot, name = PickFood()
	if spell and bag then
		button:SetAttribute("macrotext", ("/cast %s\n/use %d %d"):format(spell, bag, slot))
		foodName = name
	else
		button:SetAttribute("macrotext", "")
		foodName = nil
	end
	return true
end

-- After the macro (our own button's script): say what happened, and pick the next food.
button:SetScript("PostClick", function(_, _, down)
	local useOnKeyDown = GetCVarBool("ActionButtonUseKeyDown")
	if (down and true or false) ~= (useOnKeyDown and true or false) then
		return
	end
	ns.GuideTried("feedPet")
	if not UnitExists("pet") then
		ns.Say(ERR_NO_PET or "You don't have a pet.")
	elseif UnitIsDead("pet") then
		ns.Say("Your pet is dead.")
	elseif not foodName then
		ns.Say("No food in your bags that your pet will eat.")
	end
	C_Timer.After(0.5, UpdateMacro)
end)

ns.Buttons.Add("feedPet", button, function()
	return KnowsFeedPet() and UnitExists("pet")
end)

-- In combat the macro waits; PLAYER_REGEN_ENABLED catches it up.
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
	if event == "GET_ITEM_INFO_RECEIVED" and not waitingInfo then
		return
	end
	if event == "UNIT_PET" or event == "SPELLS_CHANGED" then
		ns.Buttons.Apply()  -- the button is only taken while there's a pet to feed
	end
	UpdateMacro()
end)

ns.OnLogin(function()
	if select(2, UnitClass("player")) ~= "HUNTER" then
		return
	end
	events:RegisterEvent("BAG_UPDATE_DELAYED")
	-- Your own pet and its level only, not every unit's.
	events:RegisterUnitEvent("UNIT_PET", "player")
	events:RegisterUnitEvent("UNIT_LEVEL", "player", "pet")
	events:RegisterEvent("SPELLS_CHANGED")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	UpdateMacro()
end)
