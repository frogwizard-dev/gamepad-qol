-- Health on the party portraits: hold the friendly targeting button in a party and each portrait on
-- the bar (the D-pad's party members, you, your pet, your target's target) gets a green health bar
-- across its bottom and the health % above that; party members out of range are dimmed. Whoever is low is the button to
-- press, without knowing everyone's face.
--
-- Nothing of Blizzard's is changed or hooked (hooks on Blizzard frames upset the gamepad UI). Our
-- overlays sit on UIParent, anchored once, out of combat, to the bar's buttons, so they follow them
-- through every layout. In combat they're only shown and hidden by alpha and never moved or scaled,
-- in case being anchored to secure buttons makes them protected. While you're in a party a frame of ours looks each frame whether the bar is up, and while it
-- is, reads which unit each button targets (its attributes) and refreshes the overlays every 0.1s.
local _, ns = ...

local UPDATE_EVERY = 0.1
local FAR_ALPHA = 0.4  -- out of range

local issecret = issecretvalue or function() return false end

local overlays        -- one per bar button, made the first time they're needed
local waitingForCombat = false

local function TargetingBar()
	local page = GamepadMainActionBarFrame and GamepadMainActionBarFrame.PageUnit
	return page and page.FriendlyTargetingActionBar
end

-- 0 to 100, secret in combat. Forever works it out itself; older clients from the two numbers.
local function HealthPercent(unit)
	local curve = CurveConstants and CurveConstants.ScaleTo100
	if UnitHealthPercent and curve then
		local ok, percent = pcall(UnitHealthPercent, unit, true, curve)
		if ok and (issecret(percent) or percent ~= nil) then
			return percent
		end
	end
	local value, max = UnitHealth(unit), UnitHealthMax(unit)
	if issecret(value) or issecret(max) or max <= 0 then
		return 0
	end
	return value / max * 100
end

local function MakeOverlay(button)
	local overlay = CreateFrame("Frame", nil, UIParent)
	overlay:SetFrameStrata("MEDIUM")
	overlay:SetAllPoints(button)
	overlay:SetAlpha(0)

	-- Faded for range on its own, so the overlay's alpha stays the shown/hidden switch.
	local content = CreateFrame("Frame", nil, overlay)
	content:SetAllPoints()

	-- Inside the portrait's bottom edge: below it there's only 2px to the next button in the D-pad's
	-- small layout. Inset so it stays within the face buttons' circles.
	local bar = CreateFrame("StatusBar", nil, content)
	bar:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 6, 4)
	bar:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -6, 4)
	bar:SetHeight(4)
	bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	bar:SetStatusBarColor(0.2, 0.85, 0.2)
	bar:SetMinMaxValues(0, 100)
	local back = bar:CreateTexture(nil, "BACKGROUND")
	back:SetPoint("TOPLEFT", -1, 1)
	back:SetPoint("BOTTOMRIGHT", 1, -1)
	back:SetColorTexture(0, 0, 0, 0.8)

	local text = content:CreateFontString(nil, "OVERLAY")
	text:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
	text:SetPoint("BOTTOM", bar, "TOP", 0, 1)

	overlay.button, overlay.content, overlay.bar, overlay.text = button, content, bar, text
	return overlay
end

local function Build()
	overlays = {}
	local targetingBar = TargetingBar()
	for _, group in ipairs({ targetingBar.Left, targetingBar.Right }) do
		for i = 1, 4 do
			local button = group and group["ActionButton" .. i]
			if button then
				overlays[#overlays + 1] = MakeOverlay(button)
			end
		end
	end
end

-- The bar's scale (Edit Mode) can differ from UIParent's: match it so the bar and text keep their size
-- next to the buttons. Out of combat only (the overlays are protected in it).
local function MatchScale()
	local parentScale = UIParent:GetEffectiveScale()
	for _, overlay in ipairs(overlays) do
		overlay:SetScale(overlay.button:GetEffectiveScale() / parentScale)
	end
end

local function HideAll()
	if not overlays then
		return
	end
	for _, overlay in ipairs(overlays) do
		overlay:SetAlpha(0)
	end
end

-- Party members by the game's range check. Only them: for anyone it doesn't check (you, your pet, an
-- assist target outside the group) it answers "not near", and in combat that answer is secret, so it
-- can't be told apart from a real one.
local function ShowRange(content, unit)
	if not (UnitInRange and unit:find("^party")) then
		content:SetAlpha(1)
		return
	end
	local near, checked = UnitInRange(unit)
	if issecret(near) then
		if not pcall(content.SetAlphaFromBoolean, content, near, 1, FAR_ALPHA) then
			content:SetAlpha(1)
		end
	elseif issecret(checked) or checked then
		content:SetAlpha(near and 1 or FAR_ALPHA)
	else
		content:SetAlpha(1)
	end
end

local function Fill(overlay, unit)
	local bar, text = overlay.bar, overlay.text
	if not UnitIsConnected(unit) then
		bar:SetValue(0)
		text:SetText("Offline")
		text:SetTextColor(0.6, 0.6, 0.6)
	elseif UnitIsDeadOrGhost(unit) then
		bar:SetValue(0)
		text:SetText("Dead")
		text:SetTextColor(1, 0.35, 0.35)
	else
		-- In combat the percent is secret: the bar and SetFormattedText take it as it is.
		local percent = HealthPercent(unit)
		pcall(bar.SetValue, bar, percent)
		text:SetTextColor(1, 1, 1)
		if not pcall(text.SetFormattedText, text, "%.0f%%", percent) then
			text:SetText("")
		end
	end
	ShowRange(overlay.content, unit)
end

-- Which unit each button targets right now (Blizzard sets the attributes, and turns the button off
-- when nobody's there), so swapped D-pad and face buttons sort themselves out.
local function UpdateAll()
	for _, overlay in ipairs(overlays) do
		local button = overlay.button
		local unit = button:IsEnabled() and button:GetAttribute("type") == "target" and button:GetAttribute("unit")
		if unit and UnitExists(unit) then
			Fill(overlay, unit)
			overlay:SetAlpha(1)
		else
			overlay:SetAlpha(0)
		end
	end
end

local watcher = CreateFrame("Frame")
watcher:Hide()
local barUp, sinceUpdate = false, 0
watcher:SetScript("OnUpdate", function(_, elapsed)
	local up = TargetingBar():IsVisible()
	if up ~= barUp then
		barUp = up
		if not up then
			HideAll()
			return
		end
		if not InCombatLockdown() then
			MatchScale()
		end
		sinceUpdate = UPDATE_EVERY
	end
	if up then
		sinceUpdate = sinceUpdate + elapsed
		if sinceUpdate >= UPDATE_EVERY then
			sinceUpdate = 0
			UpdateAll()
		end
	end
end)

-- In a party (a raid picks with the D-pad instead of portraits) with party targeting on.
local function Wanted()
	return ns.db and ns.db.partyHealth and ns.IsGamepadUI() and TargetingBar() ~= nil
		and IsInGroup() and not IsInRaid() and C_CVar.GetCVarBool("GamepadUsePartyTargeting")
end

local function Refresh()
	if not Wanted() then
		watcher:Hide()
		barUp = false
		HideAll()
		return
	end
	if not overlays then
		-- Anchoring to the bar's buttons can't be done in combat.
		if InCombatLockdown() then
			waitingForCombat = true
			return
		end
		Build()
		MatchScale()
	end
	watcher:Show()
end

ns.OnRefresh(Refresh)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("CVAR_UPDATE")
-- Switching to or from the gamepad UI; older clients don't have the event.
pcall(events.RegisterEvent, events, "INPUT_DEVICE_INTERFACE_TRANSITION")
events:SetScript("OnEvent", function(_, event, name)
	if event == "INPUT_DEVICE_INTERFACE_TRANSITION" then
		-- The gamepad UI answers correctly only a frame later.
		C_Timer.After(0, Refresh)
		return
	elseif event == "PLAYER_REGEN_ENABLED" then
		if not waitingForCombat then
			return
		end
		waitingForCombat = false
	elseif event == "CVAR_UPDATE" and name ~= "GamepadUsePartyTargeting" then
		return
	end
	Refresh()
end)
