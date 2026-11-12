-- Gamepad QoL's settings, in a window of our own, driven by the controller or the mouse.
--
-- Not Blizzard's Settings window: there, the game calls an addon's code and reads its values while
-- it works, and on Forever's gamepad UI closing it then gets SetPreferredGamepadInteractTarget
-- forbidden. (Improved Forever does the same, with its own window.) Blizzard's AddOns list only gets
-- a page saying where the settings are, with a button to open them (Core.lua).
--
-- While the window is open and no game window has the controller, the D-pad, A and B are ours, by
-- priority override bindings to buttons of ours (Buttons.lua's way): up / down pick a setting,
-- left / right change it, A changes it too (or runs it), B closes. Out of combat only: it closes
-- when a fight starts. Rows can be clicked too (right-click goes back a choice).
local ADDON, ns = ...

local ROW_H = 26
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

	{ header = "Controller buttons" },
	{ key = "cleanUpButton", label = "Clean Up Bags (bags open)", choices = function() return ns.Buttons.Choices() end,
		tip = "Cleans up your bags while they're open; the button does its usual job again once they close." },
	{ key = "inviteButton", label = "Quick invite", choices = function() return ns.Buttons.Choices() end,
		tip = "Invites whoever your target is fighting: target the mob you need for a quest and press it. With a player targeted, it invites them. Not while you're in combat." },
	{ key = "peekMapButton", label = "Peek at the map (hold)", choices = function() return ns.Buttons.Choices() end,
		tip = "Hold it to see the map, let go to close it. You keep moving while it's up." },
	{ action = "guide", label = "Button guide", value = "Show",
		tip = "Shows the window listing your buttons, so you can try them out." },
}

local frame, owner, selected
local rowFrames, selectable = {}, {}
local navBound = false

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

local function UIFocused()
	local manager = GamepadMode and GamepadMode.FrameControlsManager
	return manager and manager.isUIFocused and true or false
end

local preview = {}  -- the sample slots under the window

local function RefreshPreview()
	for i, slot in ipairs(preview) do
		ns.PreviewJunkMark(slot, i)
	end
end

local function Refresh()
	for _, r in ipairs(rowFrames) do
		if r.row and not r.row.header then
			r.value:SetText(r.row.action and r.row.value or ("<  " .. ValueText(r.row) .. "  >"))
			r.highlight:SetShown(r == selected)
		end
	end
	frame.tip:SetText(selected and selected.row.tip or "")
	RefreshPreview()
end

local function Select(r)
	selected = r
	Refresh()
end

-- Change a row by dir (+1 / -1); an action runs.
local function Change(r, dir)
	local row = r.row
	if row.action == "guide" then
		frame:Hide()
		C_Timer.After(0, ns.ShowGuide)
		return
	end
	local key = row.key
	if row.bool then
		ns.db[key] = not ns.db[key]
	elseif row.range then
		local v = (ns.db[key] or row.range[1]) + dir
		if v > row.range[2] then v = row.range[1] elseif v < row.range[1] then v = row.range[2] end
		ns.db[key] = v
	else
		local choices = Choices(row)
		local index = 1
		for i, choice in ipairs(choices) do
			if choice[1] == ns.db[key] then
				index = i
			end
		end
		index = (index - 1 + dir) % #choices + 1
		ns.db[key] = choices[index][1]
	end
	Refresh()
	ns.Refresh()
end

local function Move(dir)
	if not selected then
		return
	end
	local index = 1
	for i, r in ipairs(selectable) do
		if r == selected then
			index = i
		end
	end
	index = (index - 1 + dir) % #selectable + 1
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
local navButtons = {}

local function UpdateNavBindings()
	local want = frame and frame:IsShown() and not UIFocused() and not InCombatLockdown()
	if want == navBound or InCombatLockdown() then
		return
	end
	if want then
		for key, button in pairs(navButtons) do
			SetOverrideBindingClick(owner, true, key, button:GetName(), "LeftButton")
		end
	else
		ClearOverrideBindings(owner)
	end
	navBound = want
end

local function Build()
	frame = CreateFrame("Frame", "GamepadQoLOptions", UIParent, "BackdropTemplate")
	frame:SetFrameStrata("DIALOG")
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	frame:SetBackdropColor(0.04, 0.04, 0.05, 0.95)
	frame:SetBackdropBorderColor(0.8, 0.65, 0.25)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -14)
	title:SetText("Gamepad QoL")

	local y = -42
	for _, row in ipairs(ROWS) do
		local r = { row = row }
		if row.header then
			local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			text:SetPoint("TOPLEFT", 18, y - 8)
			text:SetText(row.header)
			text:SetTextColor(1, 0.82, 0)
			y = y - ROW_H - 4
		else
			local b = CreateFrame("Button", nil, frame)
			b:SetPoint("TOPLEFT", 12, y)
			b:SetPoint("TOPRIGHT", -12, y)
			b:SetHeight(ROW_H)
			b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			r.highlight = b:CreateTexture(nil, "BACKGROUND")
			r.highlight:SetAllPoints()
			r.highlight:SetColorTexture(1, 0.82, 0, 0.15)
			r.highlight:Hide()
			local hover = b:CreateTexture(nil, "HIGHLIGHT")
			hover:SetAllPoints()
			hover:SetColorTexture(1, 1, 1, 0.05)
			r.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			r.label:SetPoint("LEFT", 16, 0)
			r.label:SetText(row.label)
			r.value = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			r.value:SetPoint("RIGHT", -12, 0)
			b:SetScript("OnClick", function(_, mouse)
				Select(r)
				Change(r, mouse == "RightButton" and -1 or 1)
			end)
			b:SetScript("OnEnter", function() Select(r) end)
			selectable[#selectable + 1] = r
			y = y - ROW_H
			if row.preview then
				-- Three sample bag slots, marked in the chosen style, just under the row.
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
		rowFrames[#rowFrames + 1] = r
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

	local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	close:SetSize(80, 22)
	close:SetPoint("BOTTOMRIGHT", -12, 10)
	close:SetText(CLOSE or "Close")
	close:SetScript("OnClick", function() frame:Hide() end)

	frame:SetSize(WIDTH, -y + 44 + 60)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)

	owner = CreateFrame("Frame")
	for key, fn in pairs(NAV) do
		local b = CreateFrame("Button", "GamepadQoLOptions" .. key, UIParent)
		b:Hide()
		b:RegisterForClicks("AnyDown")
		b:SetScript("OnClick", fn)
		navButtons[key] = b
	end

	local elapsed = 0
	frame:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed > 0.1 then
			elapsed = 0
			UpdateNavBindings()
		end
	end)
	frame:SetScript("OnShow", function()
		Select(selected or selectable[1])
		UpdateNavBindings()
	end)
	frame:SetScript("OnHide", function()
		UpdateNavBindings()
	end)
	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:SetScript("OnEvent", function() frame:Hide() end)
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
