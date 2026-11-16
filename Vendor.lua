-- At a vendor: repair and sell your grey items as the window opens, so there's nothing to steer to
-- with the controller. Only game calls (the same ones the vendor's own buttons make): no Blizzard
-- frame is touched, so the gamepad UI stays untainted.
local _, ns = ...

local POOR = (Enum.ItemQuality and Enum.ItemQuality.Poor) or 0
-- The vendor's buyback list holds the last 12 sold: selling no more than that keeps every one
-- buyable again.
local BUYBACK = 12

-- "1g 2s 30c", with the game's coin icons.
local function Money(copper)
	if GetCoinTextureString then
		return GetCoinTextureString(copper)
	end
	return string.format("%dc", copper)
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

-- Your grey items that sell for something, as { bag, slot, value } (value: the whole stack).
local function Greys()
	local found = {}
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.quality == POOR and not info.isLocked and not info.hasNoValue then
				local price = select(11, C_Item.GetItemInfo(info.hyperlink or info.itemID))
				if price and price > 0 then
					found[#found + 1] = { bag = bag, slot = slot, value = price * (info.stackCount or 1) }
				end
			end
		end
	end
	return found
end

local function SellGreys()
	if not ns.db.autoSellGreys then
		return nil
	end
	local greys = Greys()
	if #greys == 0 then
		return nil
	end
	-- Most valuable first, so if there are more than the buyback list holds, the best go.
	table.sort(greys, function(first, second) return first.value > second.value end)
	local count, total = 0, 0
	for i = 1, math.min(#greys, BUYBACK) do
		local item = greys[i]
		C_Container.UseContainerItem(item.bag, item.slot)
		count, total = count + 1, total + item.value
	end
	local text = string.format("sold %d grey item%s for %s", count, count == 1 and "" or "s", Money(total))
	if #greys > BUYBACK then
		text = text .. string.format(" (%d more next time)", #greys - BUYBACK)
	end
	return text
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
		local okSell, sold = pcall(SellGreys)
		if okSell and sold then done[#done + 1] = sold end
		if #done > 0 then
			local text = table.concat(done, ", ")
			ns.Say(text:sub(1, 1):upper() .. text:sub(2))
		end
	end)
end)
