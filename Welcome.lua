-- The button guide: a window listing our controller buttons, shown on first login and whenever an
-- update changes them. Each row lights up when its button is pressed, so players can try them out
-- before closing it. Reopened from the settings window or with /gqol guide. Y opens the settings.
--
-- Taint: our own frame, never handed to Blizzard's window systems (no UIPanel, no UISpecialFrames,
-- no gamepad frame manager). B closes it through a priority override binding of ours, held only
-- while it's open, out of combat and with no gamepad window focused (so B still closes the bags).
local ADDON, ns = ...

-- Raise when the buttons or what they do change, so players see the guide again.
local GUIDE_VERSION = 2

local ROWS = {
	{ id = "cleanUp", title = "Clean Up Bags", hold = false, before = "Open your bags, then " },
	{ id = "invite", title = "Quick invite", hold = false, before = "Target a mob someone is fighting (or a player), then ",
		after = " Not while you're in combat." },
	{ id = "peekMap", title = "Peek at the map", hold = true, before = "" },
	{ id = "trackQuest", title = "Track / untrack a quest", hold = false, before = "Open the Map & Quest Log, put the cursor on a quest, then " },
	{ id = "feedPet", title = "Feed pet", hold = false, before = "With your pet out, ", hunter = true },
}
-- Hunter-only rows are left out for everyone else.
if select(2, UnitClass("player")) ~= "HUNTER" then
	for i = #ROWS, 1, -1 do
		if ROWS[i].hunter then
			table.remove(ROWS, i)
		end
	end
end

local NAMES = ns.Buttons.SHORT_NAMES

-- "Hold RT, then press R3" / "press L3" / "hold LT, then hold R3 (let go to close)".
local function HowTo(row)
	local spec = ns.Buttons.KeyFor(row.id)
	if not spec or spec == "none" then
		return nil
	end
	local held, pressed = ns.Buttons.Parse(spec)
	local action = (row.hold and "hold " or "press ") .. (NAMES[pressed] or pressed)
	local text
	if held then
		text = "hold " .. (NAMES[held] or held) .. ", then " .. action
	else
		text = action
	end
	if row.hold then
		text = text .. " (let go to close)"
	end
	text = row.before .. text .. "." .. (row.after or "")
	return text:sub(1, 1):upper() .. text:sub(2)
end

local frame, closeOwner, closeButton, settingsButton
local rowFrames = {}

local function UIFocused()
	local manager = GamepadMode and GamepadMode.FrameControlsManager
	return manager and manager.isUIFocused and true or false
end

-- B closes the guide while nothing else wants it.
local closeBound = false
local function UpdateCloseBinding()
	local want = frame and frame:IsShown() and not UIFocused() and not InCombatLockdown()
	if want == closeBound or InCombatLockdown() then
		return
	end
	if want then
		SetOverrideBindingClick(closeOwner, true, "PAD2", closeButton:GetName(), "LeftButton")
		SetOverrideBindingClick(closeOwner, true, "PAD4", settingsButton:GetName(), "LeftButton")
	else
		ClearOverrideBindings(closeOwner)
	end
	closeBound = want
end

local function Refresh()
	for _, row in ipairs(ROWS) do
		local r = rowFrames[row.id]
		local how = HowTo(row)
		r.how:SetText(how or "Not set: press Y to pick a button in the settings.")
		r.how:SetTextColor(how and 1 or 0.6, how and 1 or 0.6, how and 1 or 0.6)
		r.tick:SetShown(r.tried == true)
		r.status:SetText(r.tried and "Works!" or "")
	end
end

local function Build()
	frame = CreateFrame("Frame", "GamepadQoLGuide", UIParent, "BackdropTemplate")
	frame:SetSize(520, 120 + #ROWS * 58)
	frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
	frame:SetFrameStrata("DIALOG")
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	frame:SetBackdropColor(0.04, 0.04, 0.05, 0.94)
	frame:SetBackdropBorderColor(0.8, 0.65, 0.25)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -16)
	title:SetText("Gamepad QoL: your buttons")

	local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	sub:SetPoint("TOP", title, "BOTTOM", 0, -6)
	sub:SetText("Try each one now. It lights up when it works.")

	local y = -66
	for _, row in ipairs(ROWS) do
		local r = {}
		r.tick = frame:CreateTexture(nil, "OVERLAY")
		r.tick:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
		r.tick:SetSize(22, 22)
		r.tick:SetPoint("TOPLEFT", 18, y - 2)

		r.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		r.title:SetPoint("TOPLEFT", 48, y)
		r.title:SetText(row.title)

		r.status = frame:CreateFontString(nil, "OVERLAY", "GameFontGreen")
		r.status:SetPoint("TOPRIGHT", -20, y)

		r.how = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		r.how:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -5)
		r.how:SetPoint("RIGHT", -20, 0)
		r.how:SetJustifyH("LEFT")
		r.how:SetWordWrap(true)

		rowFrames[row.id] = r
		y = y - 58
	end

	local foot = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	foot:SetPoint("BOTTOM", 0, 34)
	foot:SetWidth(480)
	foot:SetText("Combinations work outside combat. Press Y to change any button in the settings (/gqol).")

	local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	hint:SetPoint("BOTTOM", 0, 14)
	hint:SetText("Y (Triangle): settings  ·  B (Circle) or Close: done")

	local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	close:SetSize(80, 22)
	close:SetPoint("BOTTOMRIGHT", -12, 10)
	close:SetText(CLOSE or "Close")
	close:SetScript("OnClick", function() frame:Hide() end)

	closeOwner = CreateFrame("Frame")
	closeButton = CreateFrame("Button", "GamepadQoLGuideClose", UIParent)
	closeButton:Hide()
	closeButton:RegisterForClicks("AnyDown")
	closeButton:SetScript("OnClick", function() frame:Hide() end)

	local function OpenSettings()
		frame:Hide()
		C_Timer.After(0, function() ns.ShowOptions() end)
	end
	settingsButton = CreateFrame("Button", "GamepadQoLGuideSettings", UIParent)
	settingsButton:Hide()
	settingsButton:RegisterForClicks("AnyDown")
	settingsButton:SetScript("OnClick", OpenSettings)

	local settings = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	settings:SetSize(90, 22)
	settings:SetPoint("BOTTOMLEFT", 12, 10)
	settings:SetText("Settings")
	settings:SetScript("OnClick", OpenSettings)

	local elapsed = 0
	frame:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed > 0.1 then
			elapsed = 0
			UpdateCloseBinding()
		end
	end)
	frame:SetScript("OnShow", function()
		for _, r in pairs(rowFrames) do
			r.tried = nil
		end
		Refresh()
		UpdateCloseBinding()
	end)
	frame:SetScript("OnHide", function()
		UpdateCloseBinding()
		ns.db.guideSeen = GUIDE_VERSION
	end)
	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:SetScript("OnEvent", function() frame:Hide() end)
end

function ns.ShowGuide()
	if InCombatLockdown() then
		return
	end
	if not frame then
		Build()
	end
	frame:Show()
end

-- Features call this when their button runs.
function ns.GuideTried(id)
	local r = frame and frame:IsShown() and rowFrames[id]
	if r then
		r.tried = true
		Refresh()
	end
end

ns.OnRefresh(function()
	if frame and frame:IsShown() then
		Refresh()
	end
end)

ns.OnLogin(function()
	if (ns.db.guideSeen or 0) >= GUIDE_VERSION then
		return
	end
	-- A few seconds in, once the loading screen and its popups have settled.
	C_Timer.After(6, function()
		if not InCombatLockdown() then
			ns.ShowGuide()
		end
	end)
end)
