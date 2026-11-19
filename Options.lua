-- Gamepad QoL's settings, in a window of our own driven by the controller or the mouse. Not Blizzard's
-- Settings window: it calls addon code while it works, and closing it then gets Forever's protected
-- SetPreferredGamepadInteractTarget forbidden (Improved Forever has its own window too). While it's open
-- the D-pad picks and changes, A changes or runs, B closes (out of combat only); rows take clicks too.
local _, ns = ...

local ROW_HEIGHT = 26
local WIDTH = 600

-- The settings, in order. Kinds: bool, choices ({ value, label } pairs, or a function giving them),
-- range ({ min, max }), action (run on A). A header row starts a section.
local ROWS = {
	{ header = "Bags" },
	{ key = "bagButtons", label = "Bag buttons", choices = {
		{ "row", "Row above the items" }, { "side", "Column down the left side" }, { "off", "Blizzard's (in the grid)" } },
		tip = "Where the backpack and bag buttons go in the gamepad bag window. Takes effect the next time you open your bags." },
	{ key = "autoCleanUp", label = "Clean up bags when you close them", bool = true,
		tip = "Runs Clean Up Bags every time you close your bags (not in combat)." },
	{ key = "cleanUpHint", label = "Show the Clean Up button in your bags", bool = true,
		tip = "Adds the Clean Up button to the button bar under your bags, as a reminder." },

	{ header = "Junk to sell or destroy" },
	{ key = "highlightCheapest", label = "Mark junk", bool = true,
		tip = "When your bags fill up, what should go first? The cheapest junk gets the junk coin and a number, 1 for the first to go, by what a vendor pays for the whole stack. Never marked: consumables, trade goods, reagents, recipes, quest items, ammunition, keys, tools, your hearthstone, and items a quest still needs." },
	{ key = "junkWhen", label = "Show the marks", choices = {
		{ "always", "Always" }, { "nearly", "When my bags are nearly full" } },
		tip = "Always, or only while your bags are nearly full (2 free slots or fewer)." },
	{ key = "junkQualities", label = "What counts as junk", choices = {
		{ 0, "Greys only" }, { 1, "Greys and whites" }, { 2, "Greys, whites and greens" } },
		tip = "Which item qualities may be marked. Greens are handy to include once you've outlevelled them. Blue and better are never marked." },
	{ key = "cheapestCount", label = "How many to mark", range = { 1, 5 },
		tip = "How many of the cheapest to mark, numbered 1 (the first to go) upwards." },
	{ key = "junkStyle", label = "Mark style", choices = ns.JUNK_STYLES, preview = true,
		tip = "How junk is marked. The slots below show the style you've picked." },

	{ header = "At a vendor" },
	{ key = "autoRepair", label = "Repair everything", bool = true,
		tip = "As a vendor that can repair opens, repairs all your gear (if you have the money). A message says what it cost." },
	{ key = "autoSellGreys", label = "Sell grey items", bool = true,
		tip = "As a vendor opens, sells your grey (poor quality) items, up to 12 at a time so every one can still be bought back. Only greys: whites and greens marked as junk are left for you to decide." },

	{ header = "Controller" },
	{ key = "partyHealth", label = "Health on party portraits", bool = true,
		tip = "In a party, hold the friendly targeting button and each portrait (your party on the D-pad, you, your pet, your target's target) shows a green health bar and its health %. Party members out of range are dimmed. Whoever is low is the button to press." },
	{ key = "cleanUpButton", label = "Clean Up Bags (bags open)", choices = function() return ns.Buttons.Choices() end,
		tip = "Cleans up your bags while they're open; the button does its usual job again once they close." },
	{ key = "inviteButton", label = "Quick invite", choices = function() return ns.Buttons.Choices() end,
		tip = "Invites whoever your target is fighting: target the mob you need for a quest and press it. With a player targeted, it invites them. Not while you're in combat." },
	{ key = "peekMapButton", label = "Peek at the map (hold)", choices = function() return ns.Buttons.Choices() end,
		tip = "Hold it to see the map, let go to close it. You keep moving while it's up." },
	{ key = "trackQuestButton", label = "Track / untrack (quest log)", choices = function() return ns.Buttons.Choices() end,
		tip = "In the Map & Quest Log, tracks or untracks the quest the cursor is on (or every quest under a zone header). With the map side focused the button stays the map marker." },
	{ key = "feedPetButton", label = "Feed pet (hunters)", choices = function() return ns.Buttons.Choices() end,
		tip = "Feeds your pet the best food in your bags without opening them: food it eats at most 10 levels below it (the lowest of those, keeping better food for later), else the highest it will eat." },
	{ action = "guide", label = "Button guide", value = "Show",
		tip = "Shows the window listing your buttons, so you can try them out." },
}

local frame, selected
local entries = {}      -- per row in ROWS: { row } and, for a setting, its highlight, label and value
local selectable = {}   -- the entries the cursor stops on

local function Choices(row)
	return type(row.choices) == "function" and row.choices() or row.choices
end

local function ValueText(row)
	if row.action then
		return row.value
	end
	local value = ns.db[row.key]
	if row.bool then
		return value and "On" or "Off"
	elseif row.range then
		return tostring(value)
	end
	for _, choice in ipairs(Choices(row)) do
		if choice[1] == value then
			return choice[2]
		end
	end
	return tostring(value)
end

local preview = {}  -- the sample slots under the window

local function RefreshPreview()
	for i, slot in ipairs(preview) do
		ns.PreviewJunkMark(slot, i)
	end
end

local function Refresh()
	for _, entry in ipairs(entries) do
		if not entry.row.header then
			entry.value:SetText(entry.row.action and entry.row.value or ("<  " .. ValueText(entry.row) .. "  >"))
			entry.highlight:SetShown(entry == selected)
		end
	end
	frame.tip:SetText(selected and selected.row.tip or "")
	RefreshPreview()
end

local function Select(entry)
	selected = entry
	Refresh()
end

-- Move a setting on (+1) or back (-1); an action runs.
local function Change(entry, direction)
	local row = entry.row
	if row.action == "guide" then
		frame:Hide()
		C_Timer.After(0, ns.ShowGuide)
		return
	end
	local key = row.key
	if row.bool then
		ns.db[key] = not ns.db[key]
	elseif row.range then
		local value = (ns.db[key] or row.range[1]) + direction
		if value > row.range[2] then value = row.range[1] elseif value < row.range[1] then value = row.range[2] end
		ns.db[key] = value
	else
		local choices = Choices(row)
		local index = 1
		for i, choice in ipairs(choices) do
			if choice[1] == ns.db[key] then
				index = i
			end
		end
		index = (index - 1 + direction) % #choices + 1
		ns.db[key] = choices[index][1]
	end
	Refresh()
	ns.Refresh()
end

local function Move(direction)
	if not selected then
		return
	end
	local index = 1
	for i, entry in ipairs(selectable) do
		if entry == selected then
			index = i
		end
	end
	index = (index - 1 + direction) % #selectable + 1
	Select(selectable[index])
end

-- The D-pad, A and B while the window is open and nothing else has the controller.
local NAV = {
	PADDUP = function() Move(-1) end,
	PADDDOWN = function() Move(1) end,
	PADDLEFT = function() if selected then Change(selected, -1) end end,
	PADDRIGHT = function() if selected then Change(selected, 1) end end,
	PAD1 = function() if selected then Change(selected, 1) end end,
	PAD2 = function() frame:Hide() end,
}

local function Build()
	frame = ns.Window("GamepadQoLOptions", 0.95)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -14)
	title:SetText("Gamepad QoL")

	local y = -42
	for _, row in ipairs(ROWS) do
		local entry = { row = row }
		if row.header then
			local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			text:SetPoint("TOPLEFT", 18, y - 8)
			text:SetText(row.header)
			text:SetTextColor(1, 0.82, 0)
			y = y - ROW_HEIGHT - 4
		else
			local button = CreateFrame("Button", nil, frame)
			button:SetPoint("TOPLEFT", 12, y)
			button:SetPoint("TOPRIGHT", -12, y)
			button:SetHeight(ROW_HEIGHT)
			button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			entry.highlight = button:CreateTexture(nil, "BACKGROUND")
			entry.highlight:SetAllPoints()
			entry.highlight:SetColorTexture(1, 0.82, 0, 0.15)
			entry.highlight:Hide()
			local hover = button:CreateTexture(nil, "HIGHLIGHT")
			hover:SetAllPoints()
			hover:SetColorTexture(1, 1, 1, 0.05)
			entry.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			entry.label:SetPoint("LEFT", 16, 0)
			entry.label:SetText(row.label)
			entry.value = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			entry.value:SetPoint("RIGHT", -12, 0)
			-- A click moves the setting on, a right-click back.
			button:SetScript("OnClick", function(_, mouseButton)
				Select(entry)
				Change(entry, mouseButton == "RightButton" and -1 or 1)
			end)
			button:SetScript("OnEnter", function() Select(entry) end)
			selectable[#selectable + 1] = entry
			y = y - ROW_HEIGHT
			if row.preview then
				-- Three sample bag slots, marked in the chosen style, under the row.
				for i = 1, 3 do
					local slot = CreateFrame("Frame", nil, frame)
					slot:SetSize(37, 37)
					slot:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24 - (3 - i) * 44, y - 4)
					local icon = slot:CreateTexture(nil, "BACKGROUND")
					icon:SetAllPoints()
					icon:SetTexture(i == 2 and "Interface\\Icons\\INV_Misc_Bone_01" or "Interface\\Icons\\INV_Misc_Pelt_Wolf_Ruin_01")
					local count = slot:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
					count:SetPoint("BOTTOMRIGHT", -3, 3)
					count:SetText(i == 3 and "4" or "")
					preview[i] = slot
				end
				local label = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
				label:SetPoint("RIGHT", preview[1], "LEFT", -12, 0)
				label:SetText("Preview")
				y = y - 46
			end
		end
		entries[#entries + 1] = entry
	end

	frame.tip = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.tip:SetPoint("TOPLEFT", 24, y - 10)
	frame.tip:SetPoint("TOPRIGHT", -24, y - 10)
	frame.tip:SetJustifyH("LEFT")
	frame.tip:SetWordWrap(true)
	frame.tip:SetHeight(44)

	local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("BOTTOM", 0, 14)
	hint:SetText("D-pad up / down: pick  ·  left / right or A: change  ·  B: close")

	frame:SetSize(WIDTH, -y + 44 + 60)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	frame:SetClampedToScreen(true)

	local navButtons = {}
	for key, Press in pairs(NAV) do
		local button = CreateFrame("Button", "GamepadQoLOptions" .. key, UIParent)
		button:Hide()
		button:RegisterForClicks("AnyDown")
		button:SetScript("OnClick", Press)
		navButtons[key] = button
	end
	local UpdateBindings = ns.Buttons.BindWhileOpen(frame, navButtons)
	frame:SetScript("OnShow", function()
		Select(selected or selectable[1])
		UpdateBindings()
	end)
	frame:SetScript("OnHide", UpdateBindings)
end

function ns.ShowOptions()
	if InCombatLockdown() then
		return
	end
	if not frame then
		Build()
	end
	frame:Show()
end
