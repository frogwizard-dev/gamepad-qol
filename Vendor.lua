-- At a vendor: repair and sell your grey items as the window opens, so there's nothing to steer to
-- with the controller. Only game calls (the same ones the vendor's own buttons make): no Blizzard
-- frame is touched, so the gamepad UI stays untainted.
local _, ns = ...

local POOR = (Enum.ItemQuality and Enum.ItemQuality.Poor) or 0
-- The vendor's buyback list holds the last 12 sold: selling no more than that keeps every one
-- buyable again.
local BUYBACK = 12

-- "1g 2s 30c", with the game's coin icons (Forever has the C_CurrencyInfo one, not the old global).
local function Money(copper)
	local Format = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
	if Format then
		return Format(copper)
	end
	local gold, silver = math.floor(copper / 10000), math.floor(copper / 100) % 100
	return string.format("%dg %ds %dc", gold, silver, copper % 100)
end

local function Repair()
	if not (ns.db.autoRepair and CanMerchantRepair and CanMerchantRepair()) then
		return nil
	end
	local cost, canRepair = GetRepairAllCost()
	if not canRepair or not cost or cost <= 0 then
		return nil
	end
	if GetMoney() < cost then
		return "not enough money to repair (" .. Money(cost) .. ")"
	end
	RepairAllItems()
	return "repaired for " .. Money(cost)
end

-- Your grey items that sell for something, as { bag, slot, value, id } (value: the whole stack). An item the client
-- hasn't loaded yet has no quality in its bag info: its details are asked for (it's sold next time).
local function Greys()
	local found = {}
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and not info.isLocked and not info.hasNoValue then
				local _, _, quality, _, _, _, _, _, _, _, price = C_Item.GetItemInfo(info.hyperlink or info.itemID)
				quality = info.quality or quality
				if quality == nil and info.itemID and C_Item.RequestLoadItemDataByID then
					C_Item.RequestLoadItemDataByID(info.itemID)
				elseif quality == POOR and price and price > 0 then
					found[#found + 1] = { bag = bag, slot = slot, value = price * (info.stackCount or 1), id = info.itemID }
				end
			end
		end
	end
	return found
end

-- Done(text) once the sales have gone through, or Done(nil). The server drops sales sent too fast, so they go a few
-- at a time, and what's said is what really left your bags (looked at a moment after).
local STEP = 6
local function SellGreys(Done)
	if not ns.db.autoSellGreys then
		return Done(nil)
	end
	local greys = Greys()
	if #greys == 0 then
		return Done(nil)
	end
	-- Most valuable first, so if there are more than the buyback list holds, the best go.
	table.sort(greys, function(first, second) return first.value > second.value end)
	local list = {}
	for i = 1, math.min(#greys, BUYBACK) do list[i] = greys[i] end
	local index = 1
	-- What was sent (the first index - 1) and has left your bags; one still locked is on its way, looked at again
	-- (twice at most) before it's counted as not sold.
	local tries = 0
	local function Count()
		local count, total, pending = 0, 0, false
		for i = 1, index - 1 do
			local item = list[i]
			local info = C_Container.GetContainerItemInfo(item.bag, item.slot)
			if not (info and info.itemID == item.id) then
				count, total = count + 1, total + item.value
			elseif info.isLocked then
				pending = true
			end
		end
		tries = tries + 1
		if pending and tries < 3 then
			C_Timer.After(1, Count)
			return
		end
		if count == 0 then
			return Done(nil)
		end
		local text = string.format("sold %d grey item%s for %s", count, count == 1 and "" or "s", Money(total))
		if #greys - count > 0 then
			text = text .. string.format(" (%d more next time)", #greys - count)
		end
		Done(text)
	end
	local function Step()
		-- The vendor closed or a fight began part way: what went is still said.
		if InCombatLockdown() or not (MerchantFrame and MerchantFrame:IsShown()) then
			C_Timer.After(1, Count)
			return
		end
		for _ = 1, STEP do
			local item = list[index]
			if not item then
				C_Timer.After(1, Count)
				return
			end
			C_Container.UseContainerItem(item.bag, item.slot)
			index = index + 1
		end
		C_Timer.After(0.25, Step)
	end
	Step()
end

local events = CreateFrame("Frame")
events:RegisterEvent("MERCHANT_SHOW")
events:SetScript("OnEvent", function()
	-- A moment after it opens, once the vendor's own window has settled.
	C_Timer.After(0.3, function()
		if InCombatLockdown() or not (MerchantFrame and MerchantFrame:IsShown()) then
			return
		end
		local done = {}
		local ok, repaired = pcall(Repair)
		if ok and repaired then done[#done + 1] = repaired end
		local function Said(sold)
			if sold then done[#done + 1] = sold end
			if #done > 0 then
				local text = table.concat(done, ", ")
				ns.Say(text:sub(1, 1):upper() .. text:sub(2))
			end
		end
		if not pcall(SellGreys, Said) then Said(nil) end
	end)
end)
