-- Gamepad QoL: saved settings, the settings page and the refresh hub.
local ADDON, ns = ...

ns.DEFAULTS = {
	bagButtons = "row",        -- "row" (above the items), "side" (down the left side) or "off" (Blizzard's grid)
	autoCleanUp = false,       -- Clean Up Bags whenever the bags close
	cleanUpHint = true,        -- "L3  Clean Up Bags" in the bag window's bottom bar
	highlightCheapest = true,  -- mark the item(s) that sell for the least
	cheapestCount = 1,         -- how many of the cheapest stacks to mark, numbered 1 (cheapest) upwards
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

local function RegisterSettings()
	if not (Settings and Settings.RegisterVerticalLayoutCategory) then
		return
	end

	local category = Settings.RegisterVerticalLayoutCategory("Gamepad QoL")
	ns.settingsCategory = category

	local function Register(key, name)
		local default = ns.DEFAULTS[key]
		local setting = Settings.RegisterAddOnSetting(category, "GamepadQoL_" .. key, key,
			ns.db, type(default), name, default)
		setting:SetValueChangedCallback(function() ns.Refresh() end)
		return setting
	end

	local bagButtons = Register("bagButtons", "Bag buttons")
	local function BagButtonOptions()
		local container = Settings.CreateControlTextContainer()
		container:Add("row", "Row above the items")
		container:Add("side", "Column down the left side")
		container:Add("off", "Blizzard default (in the grid)")
		return container:GetData()
	end
	Settings.CreateDropdown(category, bagButtons, BagButtonOptions,
		"Where the backpack and bag buttons go in the gamepad bag window. Takes effect the next time you open your bags.")

	Settings.CreateCheckbox(category, Register("autoCleanUp", "Clean up bags when you close them"),
		"Runs Clean Up Bags every time you close your bags (not in combat). There's also a Clean Up Bags key binding under Key Bindings > AddOns > Gamepad QoL.")

	Settings.CreateCheckbox(category, Register("cleanUpHint", "Show the Clean Up button in your bags"),
		"Adds the Clean Up button to the button bar under your bags (with Select, Use and Close), as a reminder that it cleans up your bags while they're open.")

	Settings.CreateCheckbox(category, Register("highlightCheapest", "Mark the cheapest items"),
		"Puts a copper coin and an orange glow on the item(s) in your bags that sell to a vendor for the least (whole stack). Items that can't be sold are left out.")

	local countOptions = Settings.CreateSliderOptions(1, 5, 1)
	if MinimalSliderWithSteppersMixin then
		countOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
	end
	Settings.CreateSlider(category, Register("cheapestCount", "How many to mark"), countOptions,
		"How many of the cheapest stacks to mark. With more than one, each is numbered: 1 is the cheapest, the first to sell or drop.")

	-- Controller buttons
	if CreateSettingsListSectionHeaderInitializer and SettingsPanel and SettingsPanel.GetLayout then
		local layout = SettingsPanel:GetLayout(category)
		if layout then
			layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Controller buttons"))
		end
	end
	local buttonTip = " Pick a stick click with a trigger or shoulder held, or a stick click alone. Combinations work outside combat; R3 and L3 alone keep doing their usual jobs."
	Settings.CreateDropdown(category, Register("cleanUpButton", "Clean Up Bags (bags open)"), ns.Buttons.Options,
		"Cleans up your bags while they're open. The button does its usual job again once they close." .. buttonTip)
	Settings.CreateDropdown(category, Register("inviteButton", "Quick invite"), ns.Buttons.Options,
		"Invites whoever your target is fighting: target the mob you need for a quest and press it to invite the player killing it. With a player targeted, it invites them. It doesn't work while you're in combat." .. buttonTip)
	Settings.CreateDropdown(category, Register("peekMapButton", "Peek at the map (hold)"), ns.Buttons.Options,
		"Hold it to see the map, let go to close it. You keep moving while it's up (outside combat)." .. buttonTip)

	if CreateSettingsButtonInitializer and SettingsPanel and SettingsPanel.GetLayout then
		local layout = SettingsPanel:GetLayout(category)
		if layout then
			layout:AddInitializer(CreateSettingsButtonInitializer("Button guide", "Show",
				function() ns.ShowGuide() end,
				"Shows the window listing your buttons, so you can try them out.", true))
		end
	end

	Settings.RegisterAddOnCategory(category)
end

local function OpenSettings()
	if ns.settingsCategory and Settings.OpenToCategory then
		Settings.OpenToCategory(ns.settingsCategory:GetID())
	end
end

SLASH_GAMEPADQOL1 = "/gqol"
SlashCmdList.GAMEPADQOL = function(msg)
	if (msg or ""):lower():match("guide") then
		ns.ShowGuide()
	else
		OpenSettings()
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		InitDB()
		RegisterSettings()
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
