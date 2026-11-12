-- Quick invite: one button invites whoever your target is fighting. Target the mob you need for a
-- quest and press it, and the player killing it gets a party invite. Target a player and it invites
-- them.
local ADDON, ns = ...

local function Say(text, r, g, b)
	UIErrorsFrame:AddMessage(text, r or 1, g or 0.82, b or 0)
end

local function InGroupWith(unit)
	return UnitInParty(unit) or UnitInRaid(unit)
end

-- The player to invite and why not, from the target.
local function Pick()
	if not UnitExists("target") then
		return nil, "Target a player, or the mob they're fighting."
	end
	local unit
	if UnitIsPlayer("target") then
		unit = "target"
	elseif UnitIsPlayer("targettarget") then
		unit = "targettarget"
	else
		return nil, "Nobody is fighting your target."
	end
	if UnitIsUnit(unit, "player") then
		return nil, "Your target is fighting you."
	end
	if InGroupWith(unit) then
		return nil, (UnitName(unit)) .. " is already in your group."
	end
	if UnitCanAttack("player", unit) or not UnitIsFriend("player", unit) then
		return nil, "You can't invite " .. (UnitName(unit)) .. "."
	end
	return unit
end

local function InviteTargetFighter()
	ns.GuideTried("invite")
	local unit, why = Pick()
	if not unit then
		Say(why)
		return
	end
	-- On Forever UnitName's second return is the character's surname, not a realm, so only the
	-- first is the name to invite.
	local name = UnitName(unit)
	if C_PartyInfo and C_PartyInfo.InviteUnit then
		C_PartyInfo.InviteUnit(name)
	else
		InviteUnit(name)
	end
	Say("Invited " .. name .. ".", 0.3, 1, 0.3)
end

-- Called by the key binding.
function GamepadQoL_QuickInvite()
	InviteTargetFighter()
end

BINDING_NAME_GAMEPADQOL_INVITE = "Invite who your target is fighting"

local button = CreateFrame("Button", "GamepadQoLInviteButton", UIParent)
button:RegisterForClicks("AnyDown")
button:Hide()
button:SetScript("OnClick", InviteTargetFighter)

ns.Buttons.Add("invite", "Invite who your target is fighting", button)
