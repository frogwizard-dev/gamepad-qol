-- Gamepad QoL: saved settings, the page in Blizzard's AddOns list, the refresh hub, and what the
-- features share (messages, our windows).
local ADDON, ns = ...

ns.DEFAULTS = {
	bagButtons = "row",        -- "row" (above the items), "side" (down the left side) or "off" (Blizzard's grid)
	autoCleanUp = false,       -- Clean Up Bags whenever the bags close
	cleanUpHint = true,        -- "L3  Clean Up Bags" in the bag window's bottom bar
	highlightCheapest = true,  -- mark junk to sell or destroy (Cheapest.lua)
	cheapestCount = 5,         -- how many to mark, 1 (the first to go) upwards
	junkQualities = 1,         -- the best quality that counts: 0 greys, 1 whites too, 2 greens too
	junkWhen = "always",       -- "always", or "nearly" (only while the bags are nearly full)
	junkStyle = "faded",       -- the look (ns.JUNK_STYLES in Cheapest.lua)
	autoRepair = true,         -- repair everything when a vendor that can opens (Vendor.lua)
	autoSellGreys = true,      -- sell grey items to vendors as they open
	partyHealth = true,        -- health bar and % on the friendly targeting portraits (PartyHealth.lua)
	-- Controller buttons (Buttons.lua): a stick click, alone or "HELD+STICK"; "none" for not set.
	cleanUpButton = "PADLSTICK",                -- L3, only while the bags are open
	inviteButton = "PADRTRIGGER+PADRSTICK",     -- RT held + R3
	peekMapButton = "PADLTRIGGER+PADRSTICK",    -- LT held + R3, kept held
	trackQuestButton = "PADLSTICK",             -- L3, only while the quest log has the controller
	feedPetButton = "PADRSHOULDER+PADRSTICK",   -- RB held + R3, hunters with a pet only
}

local BUTTON_SETTINGS = { "cleanUpButton", "inviteButton", "peekMapButton", "trackQuestButton", "feedPetButton" }

-- Improved Forever has its own uses for these buttons (L3 cleans up there too, R3 is its wheels),
-- so with it installed ours start unset and the player picks.
local function ImprovedForeverInstalled()
	if not (C_AddOns and C_AddOns.GetAddOnEnableState) then
		return false
	end
	local ok, state = pcall(C_AddOns.GetAddOnEnableState, "ImprovedForever", UnitName("player"))
	return ok and type(state) == "number" and state > 0
end

local refreshers, setups = {}, {}

-- Modules register a function to run when settings change or bags need redrawing.
function ns.OnRefresh(Refresh)
	refreshers[#refreshers + 1] = Refresh
end

function ns.Refresh()
	for _, Refresh in ipairs(refreshers) do
		Refresh()
	end
end

-- Modules add one-time setup to run at login, once Blizzard's bag frames exist.
function ns.OnLogin(Setup)
	setups[#setups + 1] = Setup
end

function ns.IsGamepadUI()
	return InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled()
end

-- A message in the middle of the screen, gold unless a colour is given.
function ns.Say(text, r, g, b)
	UIErrorsFrame:AddMessage(text, r or 1, g or 0.82, b or 0)
end

-- A dark, draggable window of ours with a Close button. It closes as a fight starts, the last moment
-- its controller bindings can be let go.
function ns.Window(name, alpha)
	local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
	frame:SetFrameStrata("DIALOG")
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	frame:SetBackdropColor(0.04, 0.04, 0.05, alpha)
	frame:SetBackdropBorderColor(0.8, 0.65, 0.25)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()

	local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	close:SetSize(80, 22)
	close:SetPoint("BOTTOMRIGHT", -12, 10)
	close:SetText(CLOSE or "Close")
	close:SetScript("OnClick", function() frame:Hide() end)

	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:SetScript("OnEvent", function() frame:Hide() end)
	return frame
end

local function InitDB()
	if ImprovedForeverInstalled() then
		for _, key in ipairs(BUTTON_SETTINGS) do
			ns.DEFAULTS[key] = "none"
		end
	end
	GamepadQoLDB = GamepadQoLDB or {}
	local db = GamepadQoLDB
	for key, default in pairs(ns.DEFAULTS) do
		if db[key] == nil or type(db[key]) ~= type(default) then
			db[key] = default
		end
	end
	-- Buttons saved in a form this version doesn't use (0.1.0 test builds had "CTRL-PADRSTICK").
	for _, key in ipairs(BUTTON_SETTINGS) do
		if not ns.Buttons.IsValid(db[key]) then
			db[key] = ns.DEFAULTS[key]
		end
	end
	ns.db = db
end

-- A page in Blizzard's AddOns list pointing at our own window (Options.lua says why). Showing the page is
-- the request (the controller can't reach a button on it: Forever only steers into Blizzard's own settings
-- lists); ours opens once Blizzard's has closed, as the two would fight over the controller. Moving on to
-- another page drops the request. The button does the same for the mouse.
local function RegisterPage()
	if not (Settings and Settings.RegisterCanvasLayoutCategory) then
		return
	end
	local page = CreateFrame("Frame")
	page.name = "Gamepad QoL"

	local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Gamepad QoL")

	local text = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
	text:SetWidth(560)
	text:SetJustifyH("LEFT")
	text:SetText("Gamepad QoL's settings have their own window, made for the controller. Close this window "
		.. "(B) with this page showing and it opens straight away. You can also open it with /gqol, "
		.. "or with Y in the button guide (/gqol guide).")

	local button = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	button:SetSize(200, 26)
	button:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -16)
	button:SetText("Open settings")

	local note = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	note:SetPoint("LEFT", button, "RIGHT", 12, 0)
	note:SetText("")

	local watcher = CreateFrame("Frame")
	watcher:Hide()
	watcher:SetScript("OnUpdate", function(self)
		if SettingsPanel and SettingsPanel:IsShown() then
			if not page:IsVisible() then
				self:Hide()
				note:SetText("")
			end
			return
		end
		self:Hide()
		note:SetText("")
		C_Timer.After(0.2, function() ns.ShowOptions() end)
	end)
	local function Request()
		note:SetText("Opens when you close this window.")
		watcher:Show()
	end
	button:SetScript("OnClick", Request)
	-- Shown from inside Blizzard's window: the work waits a frame, so none of it runs as part of Blizzard's code.
	page:SetScript("OnShow", function() C_Timer.After(0, Request) end)

	Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(page, page.name))
end

SLASH_GAMEPADQOL1 = "/gqol"
SlashCmdList.GAMEPADQOL = function(text)
	if (text or ""):lower():match("guide") then
		ns.ShowGuide()
	else
		ns.ShowOptions()
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, addonName)
	if event == "ADDON_LOADED" and addonName == ADDON then
		InitDB()
		RegisterPage()
	elseif event == "PLAYER_LOGIN" then
		for _, Setup in ipairs(setups) do
			Setup()
		end
	end
end)
