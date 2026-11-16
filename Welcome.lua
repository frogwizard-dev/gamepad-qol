-- The button guide: our controller buttons, shown on first login and when an update changes them;
-- each row lights up when its button is pressed, so players can try them. Reopened from the settings
-- or /gqol guide. Taint: our own frame, never handed to UIPanel, UISpecialFrames or the gamepad frame
-- manager; its B and Y are ours only while no gamepad window has the controller (B still closes the bags).
local _, ns = ...

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

local frame
local entries = {}   -- [row id] = its tick, title, status and how-to text, and whether it was tried

local function Refresh()
	for _, row in ipairs(ROWS) do
		local entry = entries[row.id]
		local how = HowTo(row)
		entry.how:SetText(how or "Not set: press Y to pick a button in the settings.")
		local shade = how and 1 or 0.6
		entry.how:SetTextColor(shade, shade, shade)
		entry.tick:SetShown(entry.tried == true)
		entry.status:SetText(entry.tried and "Works!" or "")
	end
end

local function Build()
	frame = ns.Window("GamepadQoLGuide", 0.94)
	frame:SetSize(520, 120 + #ROWS * 58)
	frame:SetPoint("TOP", UIParent, "TOP", 0, -140)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -16)
	title:SetText("Gamepad QoL: your buttons")

	local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	sub:SetPoint("TOP", title, "BOTTOM", 0, -6)
	sub:SetText("Try each one now. It lights up when it works.")

	local y = -66
	for _, row in ipairs(ROWS) do
		local entry = {}
		entry.tick = frame:CreateTexture(nil, "OVERLAY")
		entry.tick:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
		entry.tick:SetSize(22, 22)
		entry.tick:SetPoint("TOPLEFT", 18, y - 2)

		entry.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		entry.title:SetPoint("TOPLEFT", 48, y)
		entry.title:SetText(row.title)

		entry.status = frame:CreateFontString(nil, "OVERLAY", "GameFontGreen")
		entry.status:SetPoint("TOPRIGHT", -20, y)

		entry.how = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		entry.how:SetPoint("TOPLEFT", entry.title, "BOTTOMLEFT", 0, -5)
		entry.how:SetPoint("RIGHT", -20, 0)
		entry.how:SetJustifyH("LEFT")
		entry.how:SetWordWrap(true)

		entries[row.id] = entry
		y = y - 58
	end

	local foot = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	foot:SetPoint("BOTTOM", 0, 34)
	foot:SetWidth(480)
	foot:SetText("Combinations work outside combat. Press Y to change any button in the settings (/gqol).")

	local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	hint:SetPoint("BOTTOM", 0, 14)
	hint:SetText("Y (Triangle): settings  ·  B (Circle) or Close: done")

	local closeButton = CreateFrame("Button", "GamepadQoLGuideClose", UIParent)
	closeButton:Hide()
	closeButton:RegisterForClicks("AnyDown")
	closeButton:SetScript("OnClick", function() frame:Hide() end)

	local function OpenSettings()
		frame:Hide()
		C_Timer.After(0, function() ns.ShowOptions() end)
	end
	local settingsButton = CreateFrame("Button", "GamepadQoLGuideSettings", UIParent)
	settingsButton:Hide()
	settingsButton:RegisterForClicks("AnyDown")
	settingsButton:SetScript("OnClick", OpenSettings)

	local settings = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	settings:SetSize(90, 22)
	settings:SetPoint("BOTTOMLEFT", 12, 10)
	settings:SetText("Settings")
	settings:SetScript("OnClick", OpenSettings)

	local UpdateBindings = ns.Buttons.BindWhileOpen(frame, { PAD2 = closeButton, PAD4 = settingsButton })
	frame:SetScript("OnShow", function()
		for _, entry in pairs(entries) do
			entry.tried = nil
		end
		Refresh()
		UpdateBindings()
	end)
	frame:SetScript("OnHide", function()
		UpdateBindings()
		ns.db.guideSeen = GUIDE_VERSION
	end)
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
	local entry = frame and frame:IsShown() and entries[id]
	if entry then
		entry.tried = true
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
