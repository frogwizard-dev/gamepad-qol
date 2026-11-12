-- Junk to sell or destroy: when your bags fill up, what should go first? The cheapest junk in your
-- bags gets the game's junk coin and a number, 1 for the first to go. Value is what a vendor pays for
-- the whole stack, so a stack of cheap things can be worth more than one grey. Greys and whites
-- count (or greys alone, or greens too: ns.db.junkQualities). The bag window's bottom bar says
-- "5 to sell or destroy · 23c", and each marked item's tooltip says its place and worth. Shown
-- always, or only while your bags are nearly full (ns.db.junkWhen). The look is the player's
-- choice (ns.db.junkStyle).
--
-- Never suggested, as you'd want to keep them (as FrogUI's bag triage, plus a little):
--  * anything a vendor won't take;
--  * consumables (food, drink, potions, bandages), reagents, trade goods (cloth, ore, herbs),
--    recipes, quest items, ammunition and keys;
--  * profession and class tools: mining picks, skinning knives, blacksmith hammers, enchanting rods,
--    fishing poles, thieves' tools, totems (Forever's item IDs, as checked by Improved Forever, by
--    markgravity, MIT), and the hearthstone;
--  * items a quest in your log still needs (by its objectives: "Ridgeshade Greens: 2/6").
--
-- The marks are frames and textures of ours over Blizzard's item buttons, tracked in our own table,
-- never as fields on the buttons; Blizzard's slots themselves are never changed (doing so taints
-- the gamepad UI).
local ADDON, ns = ...

local overlays = {}      -- [itemButton] = our marks over it
local ranked = {}        -- ["bag:slot"] = { n = rank, value = copper } for the slots to mark
local markedCount, markedTotal = 0, 0
local waitingOnItems = false
local refreshQueued = false

local JUNK_COIN = "bags-junkcoin"   -- the game's own junk coin, as on grey items
local BORDER = 2
local NEARLY_FULL = 2               -- free slots or fewer that count as "nearly full"

-- Never suggested, by item class: consumables, reagents, ammunition, trade goods, recipes, quest
-- items, keys.
local NEVER_CLASS = { [0] = true, [5] = true, [6] = true, [7] = true, [9] = true, [12] = true, [13] = true }
local CLASS_WEAPON, FISHING_POLE = 2, 20

-- Never suggested, by item ID: profession and class tools (Forever's IDs) and the hearthstone.
local NEVER_ITEM = {
	[6948] = true,    -- Hearthstone
	[2901] = true,    -- Mining Pick
	[4471] = true,    -- Flint and Tinder
	[5956] = true,    -- Blacksmith Hammer
	[6206] = true,    -- (a mining tool)
	[6218] = true,    -- Runed Copper Rod
	[6219] = true,    -- Arclight Spanner
	[6339] = true,    -- Runed Silver Rod
	[7005] = true,    -- Skinning Knife
	[9149] = true,    -- Philosopher's Stone
	[10498] = true,   -- Gyromatic Micro-Adjustor
	[11130] = true,   -- Runed Golden Rod
	[11145] = true,   -- Runed Truesilver Rod
	[13503] = true,   -- Alchemist's Stone
	[16207] = true,   -- Runed Arcanite Rod
	[259229] = true,  -- Forever's own tools
	[260811] = true,
	[269716] = true,
	[285280] = true,
	[285281] = true,
	[5060] = true,    -- Thieves' Tools
	[5175] = true,    -- Earth Totem
	[5176] = true,    -- Fire Totem
	[5177] = true,    -- Water Totem
	[5178] = true,    -- Air Totem
}

-- The looks a player can pick (ns.db.junkStyle).
--   faded: the item dimmed and greyed, the coin and rank on a dark backing
--   tag:   a dark-red "SELL 1" tag across the top, the item left clear
--   glow:  a slowly pulsing gold border, the coin and rank
--   red:   a dim reddish wash and a red-orange border, the coin and rank
--   coin:  just the coin and rank
ns.JUNK_STYLES = {
	{ "faded", "Faded" },
	{ "tag", "Sell tag" },
	{ "glow", "Gold glow" },
	{ "red", "Red wash" },
	{ "coin", "Coin only" },
}

local function LastBagID()
	return NUM_TOTAL_BAG_FRAMES or NUM_BAG_SLOTS or 4
end

local function Key(bag, slot)
	return bag .. ":" .. slot
end

local function FreeSlots()
	local free = 0
	for bag = 0, LastBagID() do
		local n = C_Container.GetContainerNumFreeSlots(bag)
		if type(n) == "number" then
			free = free + n
		end
	end
	return free
end

local function Showing()
	if not ns.db.highlightCheapest then
		return false
	end
	if ns.db.junkWhen == "nearly" then
		return FreeSlots() <= NEARLY_FULL
	end
	return true
end

-- The names of the items the quests in your log still need ("Ridgeshade Greens: 2/6", not yet
-- finished), read straight from the quest log.
local function QuestItemNames()
	local names = {}
	if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetQuestObjectives) then
		return names
	end
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader and info.questID then
			for _, objective in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
				if objective.type == "item" and not objective.finished and objective.text then
					local name = objective.text:match("^(.-):%s*%d+%s*/%s*%d+")
						or objective.text:match("^%d+%s*/%s*%d+%s+(.+)$")
					if name then
						names[name] = true
					end
				end
			end
		end
	end
	return names
end

-- Whether a slot's item may be suggested, and what the whole stack's worth (in copper).
local function Worth(bag, slot, questNames)
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if not info or not info.itemID or info.hasNoValue or NEVER_ITEM[info.itemID] then
		return nil
	end
	local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local name, _, quality, _, _, _, _, _, _, _, price, classID, subclassID = getInfo(info.itemID)
	if price == nil then
		-- Not loaded yet: asked for, and looked at again when it comes.
		waitingOnItems = true
		if C_Item and C_Item.RequestLoadItemDataByID then
			C_Item.RequestLoadItemDataByID(info.itemID)
		end
		return nil
	end
	quality = info.quality or quality
	if price <= 0 or type(quality) ~= "number" or quality > (ns.db.junkQualities or 1) then
		return nil
	end
	if NEVER_CLASS[classID] or (classID == CLASS_WEAPON and subclassID == FISHING_POLE) then
		return nil
	end
	name = name or info.itemName
	if name and questNames[name] then
		return nil
	end
	return price * (info.stackCount or 1)
end

local function Rank()
	wipe(ranked)
	markedCount, markedTotal = 0, 0
	waitingOnItems = false
	if not Showing() then
		return
	end

	local questNames = QuestItemNames()
	local list = {}
	for bag = 0, LastBagID() do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local value = Worth(bag, slot, questNames)
			if value then
				list[#list + 1] = { bag = bag, slot = slot, value = value }
			end
		end
	end
	-- Cheapest first; stacks worth the same go in bag order so the numbers don't jump about.
	table.sort(list, function(a, b)
		if a.value ~= b.value then
			return a.value < b.value
		end
		if a.bag ~= b.bag then
			return a.bag < b.bag
		end
		return a.slot < b.slot
	end)
	for i = 1, math.min(#list, math.max(1, ns.db.cheapestCount or 5)) do
		local e = list[i]
		ranked[Key(e.bag, e.slot)] = { n = i, value = e.value }
		markedCount = i
		markedTotal = markedTotal + e.value
	end
end

---------------------------------------------------------------------------------------------------
-- The marks
---------------------------------------------------------------------------------------------------

local function SetCoin(texture)
	if C_Texture.GetAtlasInfo(JUNK_COIN) then
		texture:SetAtlas(JUNK_COIN)
	else
		texture:SetTexture("Interface\\MoneyFrame\\UI-CopperIcon")
	end
end

-- Four textures round the inside of `parent`, in one colour.
local function Border(parent, r, g, b)
	local edges = {}
	local function Edge(p1, p2, w, h)
		local t = parent:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(r, g, b, 1)
		t:SetPoint(p1)
		t:SetPoint(p2)
		if w then t:SetWidth(w) end
		if h then t:SetHeight(h) end
		edges[#edges + 1] = t
	end
	Edge("TOPLEFT", "TOPRIGHT", nil, BORDER)
	Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, BORDER)
	Edge("TOPLEFT", "BOTTOMLEFT", BORDER, nil)
	Edge("TOPRIGHT", "BOTTOMRIGHT", BORDER, nil)
	return edges
end

local function ShowAll(list, shown)
	for _, t in ipairs(list) do
		t:SetShown(shown)
	end
end

local function GetOverlay(button)
	local o = overlays[button]
	if o then
		return o
	end
	-- A frame of ours over the slot, a level up so it draws over the slot's own parts, taking no
	-- mouse: it changes nothing about the button.
	local f = CreateFrame("Frame", nil, button)
	f:SetAllPoints(button)
	f:SetFrameLevel(button:GetFrameLevel() + 5)
	f:EnableMouse(false)
	o = { frame = f }

	-- A wash over the item: grey-dark (faded) or reddish (red).
	o.wash = f:CreateTexture(nil, "ARTWORK")
	o.wash:SetPoint("TOPLEFT", BORDER, -BORDER)
	o.wash:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)

	o.redBorder = Border(f, 0.95, 0.3, 0.1)

	-- The gold glow: a border and soft halo on a frame of their own, fading in and out.
	o.glow = CreateFrame("Frame", nil, f)
	o.glow:SetAllPoints(f)
	Border(o.glow, 1, 0.82, 0.2)
	local halo = o.glow:CreateTexture(nil, "OVERLAY")
	halo:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	halo:SetBlendMode("ADD")
	halo:SetVertexColor(1, 0.8, 0.2)
	halo:SetPoint("TOPLEFT", -12, 12)
	halo:SetPoint("BOTTOMRIGHT", 12, -12)
	o.pulse = o.glow:CreateAnimationGroup()
	o.pulse:SetLooping("BOUNCE")
	local fade = o.pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.3)
	fade:SetDuration(0.9)
	fade:SetSmoothing("IN_OUT")

	-- The coin and rank in the top-left corner, on a dark backing.
	o.backing = f:CreateTexture(nil, "OVERLAY", nil, 1)
	o.backing:SetColorTexture(0, 0, 0, 0.75)
	o.backing:SetPoint("TOPLEFT", 1, -1)
	o.backing:SetHeight(17)
	o.coin = f:CreateTexture(nil, "OVERLAY", nil, 2)
	SetCoin(o.coin)
	o.coin:SetSize(16, 16)
	o.coin:SetPoint("TOPLEFT", 2, -1)
	o.rank = f:CreateFontString(nil, "OVERLAY")
	o.rank:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
	o.rank:SetPoint("LEFT", o.coin, "RIGHT", 1, 0)
	o.rank:SetTextColor(1, 0.82, 0.2)
	o.rank:SetDrawLayer("OVERLAY", 3)

	-- The sell tag across the top.
	o.tag = f:CreateTexture(nil, "OVERLAY", nil, 1)
	o.tag:SetColorTexture(0.55, 0.05, 0.02, 0.92)
	o.tag:SetPoint("TOPLEFT", 1, -1)
	o.tag:SetPoint("TOPRIGHT", -1, -1)
	o.tag:SetHeight(13)
	o.tagText = f:CreateFontString(nil, "OVERLAY")
	o.tagText:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
	o.tagText:SetPoint("CENTER", o.tag, "CENTER", 0, 0)
	o.tagText:SetTextColor(1, 1, 1)
	o.tagText:SetDrawLayer("OVERLAY", 3)

	overlays[button] = o
	return o
end

-- Draw a mark in the chosen style.
local function Style(o, rank)
	local style = ns.db.junkStyle or "faded"
	local corner = style ~= "tag"

	o.wash:SetShown(style == "faded" or style == "red")
	if style == "faded" then
		o.wash:SetColorTexture(0.1, 0.1, 0.1, 0.62)
	elseif style == "red" then
		o.wash:SetColorTexture(0.35, 0.02, 0, 0.45)
	end
	ShowAll(o.redBorder, style == "red")

	o.glow:SetShown(style == "glow")
	if style == "glow" then
		if not o.pulse:IsPlaying() then
			o.pulse:Play()
		end
	else
		o.pulse:Stop()
	end

	o.coin:SetShown(corner)
	o.rank:SetShown(corner)
	o.rank:SetText(rank)
	o.backing:SetShown(corner and style ~= "coin")
	o.backing:SetWidth(16 + 2 + o.rank:GetStringWidth() + 3)

	o.tag:SetShown(style == "tag")
	o.tagText:SetShown(style == "tag")
	o.tagText:SetText(("|A:%s:10:10|a SELL %d"):format(JUNK_COIN, rank))
end

-- rank: 1 for the first to go, 2 for the next, ...; nil to clear the mark.
local function SetMarked(button, rank)
	local o = overlays[button]
	if rank then
		o = GetOverlay(button)
		Style(o, rank)
	elseif not o then
		return
	end
	o.frame:SetShown(rank ~= nil)
	if not rank then
		o.pulse:Stop()
	end
end

-- Draw a mark on a frame of the settings window's preview (Options.lua), in the current style.
function ns.PreviewJunkMark(frame, rank)
	local o = GetOverlay(frame)
	Style(o, rank)
	o.frame:Show()
end

-- Money as the game writes it, with coin icons.
local function Coins(copper)
	local fn = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or _G.GetCoinTextureString or _G.GetMoneyString
	if fn then
		local ok, text = pcall(fn, copper)
		if ok and type(text) == "string" then
			return text
		end
	end
	return copper .. "c"
end

-- "[coin] 5 to sell or destroy · 23c" in the bag window's bottom bar, opposite the money: says what
-- the marks are. Our own text on our own frame, placed by the bar.
local summary
local function UpdateSummary()
	local bags = ContainerFrameCombinedBags
	if not (bags and bags.MoneyFrame) then
		return
	end
	if not summary then
		local f = CreateFrame("Frame", nil, bags)
		f:SetAllPoints(bags.MoneyFrame)
		f:SetFrameLevel(bags.MoneyFrame:GetFrameLevel() + 5)
		summary = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		summary:SetPoint("LEFT", f, "LEFT", 8, 0)
	end
	if markedCount > 0 then
		summary:SetText(("|A:%s:14:14|a %d to sell or destroy · %s"):format(JUNK_COIN, markedCount, Coins(markedTotal)))
		summary:Show()
	else
		summary:Hide()
	end
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

	-- Nothing to mark while no bag window is open (opening one runs this again).
	local anyShown = false
	for _, frame in ipairs(ContainerFrames()) do
		if frame:IsShown() then
			anyShown = true
			break
		end
	end
	if not anyShown then
		return
	end

	Rank()
	UpdateSummary()

	for _, frame in ipairs(ContainerFrames()) do
		if frame:IsShown() and frame.EnumerateValidItems then
			for _, item in frame:EnumerateValidItems() do
				local r = ranked[Key(item:GetBagID(), item:GetID())]
				SetMarked(item, r and r.n or nil)
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

---------------------------------------------------------------------------------------------------
-- The tooltip: "Junk 1 of 5: sells for 2c"
---------------------------------------------------------------------------------------------------

local function AddTooltipLine(tooltip)
	if tooltip ~= GameTooltip then
		return
	end
	local owner = tooltip:GetOwner()
	if not (owner and owner.GetBagID and overlays[owner] and overlays[owner].frame:IsShown()) then
		return
	end
	local r = ranked[Key(owner:GetBagID(), owner:GetID())]
	if r then
		tooltip:AddLine(("Junk %d of %d: sells for %s"):format(r.n, markedCount, Coins(r.value)), 1, 0.82, 0)
	end
end

ns.OnLogin(function()
	local events = CreateFrame("Frame")
	events:RegisterEvent("BAG_UPDATE_DELAYED")
	events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	events:RegisterEvent("QUEST_LOG_UPDATE")
	events:SetScript("OnEvent", function(_, event)
		if event == "GET_ITEM_INFO_RECEIVED" and not waitingOnItems then
			return
		end
		QueueUpdate()
	end)

	if ContainerFrame_GenerateFrame then
		hooksecurefunc("ContainerFrame_GenerateFrame", QueueUpdate)
	end

	-- The game's own way for addons to add to item tooltips, where it has one.
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, AddTooltipLine)
	end
end)
