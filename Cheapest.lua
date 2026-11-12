-- Marks the item(s) in your bags that sell to a vendor for the least (price x stack size), so you
-- know what to drop when your bags are full, numbered 1 (cheapest) upwards when more than one is
-- marked. Items that can't be sold are never marked.
--
-- The marks are textures added to Blizzard's item buttons; they're tracked in our own table, never
-- as fields on the buttons, so nothing of Blizzard's is tainted.
local ADDON, ns = ...

local overlays = {}      -- [itemButton] = { glow = texture, coin = texture }
local cheapest = {}      -- ["bag:slot"] = rank (1 = cheapest) for the slots to mark
local waitingOnItems = false
local refreshQueued = false

local function GetSellPrice(itemID)
	local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local price = select(11, getInfo(itemID))
	if price == nil then
		waitingOnItems = true
		if C_Item and C_Item.RequestLoadItemDataByID then
			C_Item.RequestLoadItemDataByID(itemID)
		end
	end
	return price
end

local function LastBagID()
	return NUM_TOTAL_BAG_FRAMES or NUM_BAG_SLOTS or 4
end

local function FindCheapest()
	wipe(cheapest)
	waitingOnItems = false

	local candidates = {}
	for bag = 0, LastBagID() do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID and not info.hasNoValue then
				local price = GetSellPrice(info.itemID)
				if price and price > 0 then
					candidates[#candidates + 1] = {
						key = bag .. ":" .. slot, bag = bag, slot = slot,
						value = price * (info.stackCount or 1),
					}
				end
			end
		end
	end

	-- Cheapest first; stacks worth the same go in bag order so the numbers don't jump about.
	table.sort(candidates, function(a, b)
		if a.value ~= b.value then
			return a.value < b.value
		end
		if a.bag ~= b.bag then
			return a.bag < b.bag
		end
		return a.slot < b.slot
	end)

	local count = math.max(1, ns.db.cheapestCount or 1)
	for rank = 1, math.min(count, #candidates) do
		cheapest[candidates[rank].key] = rank
	end
end

local function GetOverlay(button)
	local o = overlays[button]
	if not o then
		local size = button:GetWidth()
		if not size or size < 1 then
			size = 37
		end

		local glow = button:CreateTexture(nil, "OVERLAY", nil, 6)
		glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
		glow:SetBlendMode("ADD")
		glow:SetVertexColor(1, 0.45, 0.1)
		glow:SetSize(size * 1.8, size * 1.8)
		glow:SetPoint("CENTER")

		local coin = button:CreateTexture(nil, "OVERLAY", nil, 7)
		coin:SetTexture("Interface\\MoneyFrame\\UI-CopperIcon")
		coin:SetSize(14, 14)
		coin:SetPoint("TOPLEFT", 2, -2)

		local rank = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		rank:SetPoint("LEFT", coin, "RIGHT", 1, 0)
		rank:SetTextColor(1, 0.65, 0.3)

		o = { glow = glow, coin = coin, rank = rank }
		overlays[button] = o
	end
	return o
end

-- rank: 1 for the cheapest, 2 for the next, ...; nil to clear the mark.
local function SetMarked(button, rank)
	local o = overlays[button]
	if rank then
		o = GetOverlay(button)
	elseif not o then
		return
	end
	local marked = rank ~= nil
	o.glow:SetShown(marked)
	o.coin:SetShown(marked)
	-- Numbers only mean something when more than one item is marked.
	local showRank = marked and (ns.db.cheapestCount or 1) > 1
	o.rank:SetText(showRank and rank or "")
	o.rank:SetShown(showRank)
end

local function ContainerFrames()
	local frames = {}
	if ContainerFrameCombinedBags then
		frames[#frames + 1] = ContainerFrameCombinedBags
	end
	for i = 1, NUM_CONTAINER_FRAMES or 13 do
		local frame = _G["ContainerFrame" .. i]
		if frame then
			frames[#frames + 1] = frame
		end
	end
	return frames
end

local function Update()
	refreshQueued = false
	local enabled = ns.db and ns.db.highlightCheapest

	if enabled then
		FindCheapest()
	else
		wipe(cheapest)
	end

	for _, frame in ipairs(ContainerFrames()) do
		if frame:IsShown() and frame.EnumerateValidItems then
			for _, item in frame:EnumerateValidItems() do
				local bag, slot = item:GetBagID(), item:GetID()
				SetMarked(item, enabled and cheapest[bag .. ":" .. slot] or nil)
			end
		end
	end

	-- Buttons from Blizzard's pool that aren't in use right now keep no stale marks.
	for button in pairs(overlays) do
		if not button:IsShown() then
			SetMarked(button, nil)
		end
	end
end

local function QueueUpdate()
	if not refreshQueued then
		refreshQueued = true
		C_Timer.After(0, Update)
	end
end

ns.OnRefresh(QueueUpdate)

ns.OnLogin(function()
	local events = CreateFrame("Frame")
	events:RegisterEvent("BAG_UPDATE_DELAYED")
	events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	events:SetScript("OnEvent", function(_, event)
		if event == "GET_ITEM_INFO_RECEIVED" and not waitingOnItems then
			return
		end
		QueueUpdate()
	end)

	for _, frame in ipairs(ContainerFrames()) do
		frame:HookScript("OnShow", QueueUpdate)
	end
	if ContainerFrame_GenerateFrame then
		hooksecurefunc("ContainerFrame_GenerateFrame", QueueUpdate)
	end
end)
