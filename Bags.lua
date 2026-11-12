-- Gamepad bag window tweaks:
--  * Blizzard puts the backpack and bag buttons inside the item grid (the backpack ends up in the
--    far top-left). We lay the items out again without them and put the buttons in their own row
--    above the items, or in a column down the left side.
--  * "Clean Up Bags" at the top of an item's Y (More Actions) menu, so tidying up doesn't need a trip
--    to the backpack button.
--
-- Taint: everything here runs after Blizzard's own code (hooksecurefunc, Menu.ModifyMenu) and only
-- moves or resizes frames. It never writes into Blizzard's tables or the gamepad binding stack, so
-- using items from the bags in combat stays allowed.
local ADDON, ns = ...

local SPACING = 5   -- Blizzard's ITEM_SPACING_X / ITEM_SPACING_Y (locals in ContainerFrame.lua)
local ROW_GAP = 6   -- gap between the bag row and the items

local sideBackground

local function Mode()
	if not ns.IsGamepadUI() then
		return "off"
	end
	return ns.db and ns.db.bagButtons or "off"
end

-- Same test Blizzard's UpdateItemLayout uses to leave out items of a collapsed bag.
local function IsItemLaidOut(item)
	local bagButton = GamepadBagBar and GamepadBagBar:GetBagButton(item.bagID)
	return bagButton == nil or bagButton.isCollapsed ~= true
end

-- Same order as Blizzard's SortItems / SortItemsByExtendedState, items only.
local function SortBagID(item)
	local bagID = item:GetBagID()
	if KEYRING_CONTAINER and bagID == KEYRING_CONTAINER then
		return (NUM_TOTAL_BAG_FRAMES or 5) + 1
	end
	return bagID
end

local function SortItems(a, b)
	local bagA, bagB = SortBagID(a), SortBagID(b)
	if bagA ~= bagB then
		return bagA > bagB
	end
	return a:GetID() > b:GetID()
end

local function SortItemsByExtendedState(a, b)
	local extA, extB = a.IsExtended and a:IsExtended(), b.IsExtended and b:IsExtended()
	if extA ~= extB then
		return not extA
	end
	return SortItems(a, b)
end

local function CollectItems(frame)
	local items = {}
	for _, item in frame:EnumerateValidItems() do
		if IsItemLaidOut(item) then
			items[#items + 1] = item
		end
	end
	if IsAccountSecured and not IsAccountSecured() then
		table.sort(items, SortItemsByExtendedState)
	else
		table.sort(items, SortItems)
	end
	return items
end

-- Backpack first, then bags 1-4 and the reagent bag, skipping any the game hides.
local function CollectBagButtons()
	local buttons = {}
	for _, button in ipairs(GamepadBagBar.BagButtonArray or {}) do
		if button:IsShown() then
			buttons[#buttons + 1] = button
		end
	end
	return buttons
end

local function RowsHeight(frame, rows)
	if rows <= 0 then
		return 0
	end
	local info = C_XMLUtil.GetTemplateInfo(frame.itemButtonPool:GetTemplate())
	return rows * info.height + (rows - 1) * SPACING
end

local function BagRowHeight(buttons)
	local h = 0
	for _, button in ipairs(buttons) do
		h = math.max(h, button:GetHeight())
	end
	return h
end

-- Blizzard sizes the window for items plus a slot per bag button. Size it for the items alone,
-- plus the bag row when it sits above them.
local function ApplySize(frame)
	local mode = Mode()
	if mode == "off" then
		return
	end

	local items = CollectItems(frame)
	local columns = frame:GetColumns()
	local height = frame:CalculateHeight()
		- RowsHeight(frame, frame:GetRows())
		+ RowsHeight(frame, math.ceil(#items / columns))

	if mode == "row" then
		height = height + BagRowHeight(CollectBagButtons()) + ROW_GAP
	end

	frame:SetHeight(height)
	if NineSliceUtil and NineSliceUtil.UpdateCornerCropping then
		NineSliceUtil.UpdateCornerCropping(frame, height)
	end
end

local function GetSideBackground()
	if not sideBackground then
		sideBackground = GamepadBagBar:CreateTexture(nil, "BACKGROUND")
		sideBackground:SetColorTexture(0.05, 0.05, 0.05, 0.85)
	end
	return sideBackground
end

local function LayOut(frame)
	local mode = Mode()
	if sideBackground then
		sideBackground:SetShown(mode == "side")
	end
	if mode == "off" then
		return
	end

	-- Items: Blizzard's grid, minus the bag buttons.
	local items = CollectItems(frame)
	if #items > 0 then
		AnchorUtil.GridLayout(items, frame:GetInitialItemAnchor(), frame:GetAnchorLayout())
	end

	local buttons = CollectBagButtons()
	if #buttons == 0 then
		return
	end
	local keyRing = GamepadBagBar.KeyRingButton
	local last = buttons[#buttons]

	if mode == "row" then
		-- Right to left above the top row of items, the backpack on the right like the action bar's bags.
		local columns = frame:GetColumns()
		local first = buttons[1]
		first:ClearAllPoints()
		if #items > 0 then
			local rows = math.ceil(#items / columns)
			local topRight = items[(rows - 1) * columns + 1]
			first:SetPoint("BOTTOMRIGHT", topRight, "TOPRIGHT", 0, ROW_GAP)
		else
			first:SetPoint("BOTTOMRIGHT", frame.MoneyFrame, "TOPRIGHT", 0, 4)
		end
		for i = 2, #buttons do
			buttons[i]:ClearAllPoints()
			buttons[i]:SetPoint("BOTTOMRIGHT", buttons[i - 1], "BOTTOMLEFT", -SPACING, 0)
		end
		if keyRing then
			keyRing:ClearAllPoints()
			keyRing:SetPoint("BOTTOMRIGHT", last, "BOTTOMLEFT", -SPACING, 0)
		end
	else -- "side"
		-- Top to bottom just outside the window's left edge, on a dark strip.
		local first = buttons[1]
		first:ClearAllPoints()
		first:SetPoint("TOPRIGHT", frame, "TOPLEFT", -8, -40)
		for i = 2, #buttons do
			buttons[i]:ClearAllPoints()
			buttons[i]:SetPoint("TOP", buttons[i - 1], "BOTTOM", 0, -SPACING)
		end
		local bottom = last
		if keyRing and keyRing:IsShown() then
			keyRing:ClearAllPoints()
			keyRing:SetPoint("TOP", last, "BOTTOM", 0, -SPACING)
			bottom = keyRing
		end

		local bg = GetSideBackground()
		bg:ClearAllPoints()
		bg:SetPoint("TOPLEFT", first, "TOPLEFT", -5, 5)
		bg:SetPoint("RIGHT", first, "RIGHT", 5, 0)
		bg:SetPoint("BOTTOM", bottom, "BOTTOM", 0, -5)
		bg:Show()
	end
end

-- "Clean Up Bags" at the top of the Y menu on items in the gamepad bag window.
local function AddCleanUpToItemMenu(owner, rootDescription)
	if not (ns.db and ns.db.cleanUpInMenu) then
		return
	end
	local bags = ContainerFrameCombinedBags
	if not (owner and bags and bags:IsShown() and owner.GetBagID and owner:GetParent() == bags) then
		return
	end

	local button = MenuUtil.CreateButton(BAG_CLEANUP_BAGS or "Clean Up Bags", function()
		C_Container.SortBags()
	end)
	local ok = pcall(rootDescription.Insert, rootDescription, button, 1)
	if ok then
		rootDescription:Insert(MenuUtil.CreateDivider(), 2)
	else
		rootDescription:CreateDivider()
		rootDescription:CreateButton(BAG_CLEANUP_BAGS or "Clean Up Bags", function()
			C_Container.SortBags()
		end)
	end
end

ns.OnLogin(function()
	local bags = ContainerFrameCombinedBags
	if bags and GamepadBagBar then
		hooksecurefunc(bags, "UpdateFrameSize", ApplySize)
		hooksecurefunc(bags, "UpdateItemLayout", LayOut)
	end

	if Menu and Menu.ModifyMenu then
		Menu.ModifyMenu("MORE_CONTEXT_ACTIONS", AddCleanUpToItemMenu)
	end
end)
