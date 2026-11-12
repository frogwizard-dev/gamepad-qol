-- Gamepad bag window tweaks:
--  * Blizzard puts the backpack and bag buttons inside the item grid (the backpack ends up in the
--    far top-left). We lay the items out again without them and put the buttons in their own row
--    above the items, or in a column down the left side.
--
-- Taint: everything here runs after Blizzard's own code (hooksecurefunc) and only moves or resizes
-- frames. It never writes into Blizzard's tables, menus or the gamepad binding stack.
-- Don't add entries to gamepad menus (Menu.ModifyMenu): an addon-made entry taints the menu's
-- close, which runs through the gamepad binding stack, and the action bars' protected
-- SetPreferredGamepadInteractTarget is then forbidden (seen in 0.1.0 testing).
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

-- Backpack first, then bags 1-4, the reagent bag and the keyring, skipping any the game hides.
local function CollectBagButtons()
	local buttons = {}
	local keyRing = GamepadBagBar.KeyRingButton
	for _, button in ipairs(GamepadBagBar.BagButtonArray or {}) do
		if button ~= keyRing and button:IsShown() then
			buttons[#buttons + 1] = button
		end
	end
	-- The keyring is in the same list but Blizzard only uses it while "show keyring" is on
	-- (GamepadBagBarMixin:GetBagButton). It goes last, on the far end from the backpack.
	if keyRing and keyRing:IsShown() and GetCVarBool("showKeyring") then
		buttons[#buttons + 1] = keyRing
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

local function GetSideBackground(frame)
	if not sideBackground then
		-- On a frame of ours (not drawn on Blizzard's bag bar), level with the bag bar so its
		-- buttons draw over it.
		local holder = CreateFrame("Frame", nil, frame)
		holder:SetAllPoints(frame)
		holder:SetFrameLevel(GamepadBagBar:GetFrameLevel())
		sideBackground = holder:CreateTexture(nil, "BACKGROUND")
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

	if mode == "row" then
		-- Left to right above the top row of items, starting at the grid's left edge: the backpack
		-- first, as in Blizzard's own bag order.
		--
		-- Each button sits straight above an item of its column, anchored to it. The gamepad's grid
		-- navigation puts buttons in one column only when their centres' x are exactly equal; a
		-- button placed by adding up widths lands a fraction off and becomes a column of its own,
		-- which made left / right zig-zag between the bag row and the items.
		local columns = frame:GetColumns()
		local info = C_XMLUtil.GetTemplateInfo(frame.itemButtonPool:GetTemplate())
		local stepX, stepY = info.width + SPACING, info.height + SPACING
		local rows = math.max(1, math.ceil(#items / columns))

		-- Items fill from the bottom right, leftward then up: item k is in row floor((k-1)/columns)
		-- from the bottom and column columns - (k-1) % columns from the left. Keep each column's
		-- lowest item.
		local lowest = {}  -- [column from the left] = { item, row }
		for k, item in ipairs(items) do
			local row = math.floor((k - 1) / columns)
			local column = columns - (k - 1) % columns
			if not lowest[column] then
				lowest[column] = { item = item, row = row }
			end
		end

		for i, button in ipairs(buttons) do
			button:ClearAllPoints()
			local below = lowest[i]
			if below then
				button:SetPoint("BOTTOM", below.item, "TOP", 0, (rows - 1 - below.row) * stepY + ROW_GAP)
			elseif #items > 0 then
				-- No item in this column (fewer items than columns): measure from the first item,
				-- the bottom-right one.
				button:SetPoint("BOTTOM", items[1], "TOP", -(columns - i) * stepX, (rows - 1) * stepY + ROW_GAP)
			else
				button:SetPoint("BOTTOMLEFT", frame.MoneyFrame, "TOPRIGHT",
					-(columns * info.width + (columns - 1) * SPACING) + (i - 1) * stepX, 4)
			end
		end
	else -- "side"
		-- Top to bottom just outside the window's left edge, on a dark strip. Every button is placed
		-- from the same point of the window with the same x, so their centres line up exactly: the
		-- gamepad's grid navigation needs that to see them as one column (as in the row above).
		local info = C_XMLUtil.GetTemplateInfo(frame.itemButtonPool:GetTemplate())
		local stepY = info.height + SPACING
		local x = -8 - info.width / 2
		for i, button in ipairs(buttons) do
			button:ClearAllPoints()
			button:SetPoint("TOP", frame, "TOPLEFT", x, -40 - (i - 1) * stepY)
		end

		local bg = GetSideBackground(frame)
		bg:ClearAllPoints()
		bg:SetPoint("TOPRIGHT", frame, "TOPLEFT", -3, -35)
		bg:SetSize(info.width + 10, #buttons * stepY - SPACING + 10)
		bg:Show()
	end
end

ns.OnLogin(function()
	local bags = ContainerFrameCombinedBags
	if bags and GamepadBagBar then
		hooksecurefunc(bags, "UpdateFrameSize", ApplySize)
		hooksecurefunc(bags, "UpdateItemLayout", LayOut)
	end
end)
