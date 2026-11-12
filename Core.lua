-- Gamepad QoL: saved settings, the settings page and the refresh hub.
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
	-- Controller buttons (Buttons.lua): a stick click, alone or "HELD+STICK"; "none" for not set.
	cleanUpButton = "PADLSTICK",                -- L3, only while the bags are open
	inviteButton = "PADRTRIGGER+PADRSTICK",     -- RT held + R3
	peekMapButton = "PADLTRIGGER+PADRSTICK",    -- LT held + R3, kept held
}

local BUTTON_SETTINGS = { "cleanUpButton", "inviteButton", "peekMapButton" }

-- Improved Forever has its own uses for these buttons (L3 cleans up there too, R3 is its wheels),
-- so with it installed ours start unset and the player picks.
local function ImprovedForeverInstalled()
	if not (C_AddOns and C_AddOns.GetAddOnEnableState) then
		return false
	end
	local ok, state = pcall(C_AddOns.GetAddOnEnableState, "ImprovedForever", UnitName("player"))
	return ok and type(state) == "number" and state > 0
end

local refreshers = {}

-- Modules register a function to run when settings change or bags need redrawing.
function ns.OnRefresh(fn)
	refreshers[#refreshers + 1] = fn
end

function ns.Refresh()
	for _, fn in ipairs(refreshers) do
		fn()
	end
end

function ns.IsGamepadUI()
	return InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled()
end

local function InitDB()
	if ImprovedForeverInstalled() then
		for _, key in ipairs(BUTTON_SETTINGS) do
			ns.DEFAULTS[key] = "none"
		end
	end
	GamepadQoLDB = GamepadQoLDB or {}
	local db = GamepadQoLDB
	for k, v in pairs(ns.DEFAULTS) do
		if db[k] == nil or type(db[k]) ~= type(v) then
			db[k] = v
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

-- A page in Blizzard's AddOns list saying where the settings are, with a button to open them. The
-- settings themselves are in our own window (Options.lua): Blizzard's Settings window calls an
-- addon's code and reads its values while it works, and closing it then upsets Forever's gamepad UI.
-- The page is a plain frame of ours; its button only notes the request, and our window opens once
-- Blizzard's has closed (opening ours while that one has the controller would fight over it).
local pendingOpen = false

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
	text:SetText("Gamepad QoL's settings have their own window, made for the controller. Press the button "
		.. "below and it opens as soon as you close this window. You can also open it with /gqol, "
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
		if not (SettingsPanel and SettingsPanel:IsShown()) then
			self:Hide()
			pendingOpen = false
			note:SetText("")
			C_Timer.After(0.2, function() ns.ShowOptions() end)
		end
	end)
	button:SetScript("OnClick", function()
		pendingOpen = true
		note:SetText("Opens when you close this window.")
		watcher:Show()
	end)

	Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(page, page.name))
end

SLASH_GAMEPADQOL1 = "/gqol"
SlashCmdList.GAMEPADQOL = function(msg)
	if (msg or ""):lower():match("guide") then
		ns.ShowGuide()
	elseif (msg or ""):lower():match("cheap") and ns.CheapestReport then
		ns.CheapestReport()
	else
		ns.ShowOptions()
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		InitDB()
		RegisterPage()
	elseif event == "PLAYER_LOGIN" then
		for _, setup in ipairs(ns.setups or {}) do
			setup()
		end
	end
end)

-- Modules add one-time setup to run at login, once Blizzard's bag frames exist.
function ns.OnLogin(fn)
	ns.setups = ns.setups or {}
	ns.setups[#ns.setups + 1] = fn
end
