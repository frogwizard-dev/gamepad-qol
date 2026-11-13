-- Feed pet in one press: casts Feed Pet straight onto the best food in your bags, so the bag window
-- never has to open. (Cast from the action bar, Feed Pet opens the gamepad bags to pick the food, and
-- on Forever they can close again at once.)
--
-- The best food: something your pet eats (C_PetInfo.CanPetEatItem) at most 10 levels below it, where
-- feeding does the most for its happiness; of those the lowest-level one, so better food is kept for
-- later. With none that close, the highest-level food it will eat.
--
-- A secure button of ours runs "/cast Feed Pet" then "/use <bag> <slot>". The food is picked out of
-- combat, whenever bags, the pet or levels change, as the macro can't change in combat.
local ADDON, ns = ...

local FEED_PET = 6991

local function Say(text, r, g, b)
	UIErrorsFrame:AddMessage(text, r or 1, g or 0.82, b or 0)
end

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
	local consts = Constants and Constants.InventoryConstants
	return consts and consts.NumBagSlots or NUM_BAG_SLOTS or 4
end

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- bag, slot, item name of the food to use; nil if there's none.
local function PickFood()
	if not (C_PetInfo and C_PetInfo.CanPetEatItem) or not UnitExists("pet") then
		return nil
	end
	local petLevel = UnitLevel("pet") or 1
	local bestGood, bestAny
	for bag = 0, NumBags() do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID and C_PetInfo.CanPetEatItem(info.itemID) then
				local name, _, _, itemLevel = GetItemInfo(info.itemID)
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
		Say(ERR_NO_PET or "You don't have a pet.")
	elseif UnitIsDead("pet") then
		Say("Your pet is dead.")
	elseif not foodName then
		Say("No food in your bags that your pet will eat.")
	end
	C_Timer.After(0.5, UpdateMacro)
end)

ns.Buttons.Add("feedPet", "Feed your pet", button, function()
	return KnowsFeedPet() and UnitExists("pet")
end)

-- In combat the macro waits; PLAYER_REGEN_ENABLED catches it up.
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit)
	if (event == "UNIT_PET" or event == "UNIT_LEVEL") and unit ~= "player" and unit ~= "pet" then
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
	events:RegisterEvent("UNIT_PET")
	events:RegisterEvent("UNIT_LEVEL")
	events:RegisterEvent("SPELLS_CHANGED")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	UpdateMacro()
end)
