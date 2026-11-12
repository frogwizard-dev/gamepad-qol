-- Gamepad QoL: saved settings, the settings page and the refresh hub.
local ADDON, ns = ...

ns.DEFAULTS = {
	bagButtons = "row",        -- "row" (above the items), "side" (down the left side) or "off" (Blizzard's grid)
	cleanUpInMenu = true,      -- "Clean Up Bags" at the top of an item's Y (More Actions) menu
	highlightCheapest = true,  -- mark the item(s) that sell for the least
	cheapestCount = 1,         -- how many of the cheapest stacks to mark, numbered 1 (cheapest) upwards
}

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
	GamepadQoLDB = GamepadQoLDB or {}
	local db = GamepadQoLDB
	for k, v in pairs(ns.DEFAULTS) do
		if db[k] == nil or type(db[k]) ~= type(v) then
			db[k] = v
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

	Settings.CreateCheckbox(category, Register("cleanUpInMenu", "Clean Up Bags on the item menu"),
		"Press Y on any item in your bags to get Clean Up Bags at the top of the menu.")

	Settings.CreateCheckbox(category, Register("highlightCheapest", "Mark the cheapest items"),
		"Puts a copper coin and an orange glow on the item(s) in your bags that sell to a vendor for the least (whole stack). Items that can't be sold are left out.")

	local countOptions = Settings.CreateSliderOptions(1, 5, 1)
	if MinimalSliderWithSteppersMixin then
		countOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
	end
	Settings.CreateSlider(category, Register("cheapestCount", "How many to mark"), countOptions,
		"How many of the cheapest stacks to mark. With more than one, each is numbered: 1 is the cheapest, the first to sell or drop.")

	Settings.RegisterAddOnCategory(category)
end

local function OpenSettings()
	if ns.settingsCategory and Settings.OpenToCategory then
		Settings.OpenToCategory(ns.settingsCategory:GetID())
	end
end

SLASH_GAMEPADQOL1 = "/gqol"
SlashCmdList.GAMEPADQOL = OpenSettings

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
