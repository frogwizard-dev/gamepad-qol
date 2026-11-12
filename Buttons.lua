-- Controller buttons for our features, without tainting Forever's gamepad UI.
--
-- Each feature is a hidden button of ours. Its controller press is a priority override binding
-- (SetOverrideBindingClick) that clicks it. Nothing of Blizzard's gamepad code is touched: its
-- binding stack, frame manager and windows stay untainted. Bindings can only change out of combat.
-- (The technique is Improved Forever's, by markgravity, MIT: github.com/markgravity/ImprovedForever.)
--
-- A feature's button is either a stick click alone ("PADLSTICK") or one with a trigger or shoulder
-- held ("PADLTRIGGER+PADRSTICK"). Forever handles its triggers and shoulders itself (crossbar and
-- targeting), not as Shift / Ctrl / Alt, so a combination can't be one binding key. Instead the
-- stick click is bound to us only while that trigger or shoulder is physically held, and handed
-- straight back when it's let go: R3 alone stays the game's ping (and its wheel when held). As
-- bindings can't change in combat, combinations work outside it.
local ADDON, ns = ...

local Buttons = {}
ns.Buttons = Buttons

local owner = CreateFrame("Frame")
local features = {}   -- in the order added: { id, label, button, active() }
local pending = false
local lastSignature
local bound = {}      -- [key] = feature bound there now

local NAMES = {
	PADLSTICK = "L3", PADRSTICK = "R3",
	PADLTRIGGER = "LT / L2", PADRTRIGGER = "RT / R2",
	PADLSHOULDER = "LB / L1", PADRSHOULDER = "RB / R1",
}
local HOLDS = { "PADLTRIGGER", "PADRTRIGGER", "PADLSHOULDER", "PADRSHOULDER" }
-- Short names for hints ("Hold RT, then press R3").
Buttons.SHORT_NAMES = {
	PADLSTICK = "L3", PADRSTICK = "R3",
	PADLTRIGGER = "LT", PADRTRIGGER = "RT",
	PADLSHOULDER = "LB", PADRSHOULDER = "RB",
}
local STICKS = { "PADLSTICK", "PADRSTICK" }

-- "PADLTRIGGER+PADRSTICK" -> "PADLTRIGGER", "PADRSTICK"; "PADLSTICK" -> nil, "PADLSTICK".
local function Parse(spec)
	local held, pressed = (spec or ""):match("^(PAD%u+)%+(PAD%u+)$")
	if held then
		return held, pressed
	end
	return nil, spec
end

Buttons.Parse = Parse

function Buttons.IsValid(spec)
	if spec == "none" then
		return true
	end
	local held, pressed = Parse(spec)
	return NAMES[pressed] ~= nil and (held == nil or NAMES[held] ~= nil)
end

function Buttons.Label(spec)
	if not spec or spec == "none" then
		return "Not set"
	end
	local held, pressed = Parse(spec)
	if held then
		return NAMES[held] .. " held + " .. NAMES[pressed]
	end
	return NAMES[pressed] or pressed
end

-- The choices for a settings dropdown.
function Buttons.Options()
	local container = Settings.CreateControlTextContainer()
	container:Add("none", "Not set")
	for _, held in ipairs(HOLDS) do
		for _, stick in ipairs(STICKS) do
			local spec = held .. "+" .. stick
			container:Add(spec, Buttons.Label(spec))
		end
	end
	container:Add("PADLSTICK", "L3 alone (replaces auto-run)")
	container:Add("PADRSTICK", "R3 alone (replaces ping)")
	return container:GetData()
end

-- A shoulder or trigger held, or a modifier: the press belongs to another binding. (An override
-- binding on L3 alone also answers Shift-L3 when nothing has that.)
function Buttons.SomethingHeld()
	if IsModifierKeyDown() then
		return true
	end
	for _, key in ipairs(HOLDS) do
		if IsKeyDown(key) then
			return true
		end
	end
	return false
end

function Buttons.KeyFor(id)
	return ns.db[id .. "Button"]
end

-- A gamepad window has the controller (bags, character...): its own buttons are in use, and a
-- trigger there switches windows, so combinations wait. Only read, never driven.
local function UIFocused()
	local manager = GamepadMode and GamepadMode.FrameControlsManager
	return manager and manager.isUIFocused and true or false
end

-- What should be bound now: [key] = feature.
local function Wanted(combatStarting)
	local want = {}
	local uiFocused = UIFocused()
	-- Combinations first: while their trigger or shoulder is held they win the stick click. One
	-- already bound keeps it while its stick is still down, so the release reaches us too (the peek
	-- map closes on it).
	for _, f in ipairs(features) do
		local held, pressed = Parse(Buttons.KeyFor(f.id))
		if held and (not f.active or f.active()) and not want[pressed] then
			local keep = bound[pressed] == f and IsKeyDown(pressed)
			if keep or (not combatStarting and not uiFocused and IsKeyDown(held)) then
				want[pressed] = f
			end
		end
	end
	for _, f in ipairs(features) do
		local held, pressed = Parse(Buttons.KeyFor(f.id))
		if not held and pressed and pressed ~= "none" and (not f.active or f.active()) and not want[pressed] then
			want[pressed] = f
		end
	end
	return want
end

-- Rebind if what's wanted changed. Out of combat only. combatStarting: a fight is about to start,
-- so no new combination is taken (a trigger held then would keep the stick ours all fight).
function Buttons.Apply(combatStarting)
	if InCombatLockdown() then
		pending = true
		return
	end
	pending = false
	local want = Wanted(combatStarting)
	local parts = {}
	for key, f in pairs(want) do
		parts[#parts + 1] = key .. "=" .. f.id
	end
	table.sort(parts)
	local signature = table.concat(parts, ",")
	if signature == lastSignature then
		return
	end
	lastSignature = signature
	ClearOverrideBindings(owner)
	wipe(bound)
	for key, f in pairs(want) do
		SetOverrideBindingClick(owner, true, key, f.button:GetName(), "LeftButton")
		bound[key] = f
	end
end

-- id: the feature (its setting is ns.db[id .. "Button"]); label: for the settings; button: a named
-- Button of ours; active: optional, true while the binding should be there.
function Buttons.Add(id, label, button, active)
	features[#features + 1] = { id = id, label = label, button = button, active = active }
end

-- Watch the triggers and shoulders while any combination is set (cheap: a few key reads a frame,
-- and bindings only change when the answer does).
local function AnyCombination()
	for _, f in ipairs(features) do
		if Parse(Buttons.KeyFor(f.id)) then
			return true
		end
	end
	return false
end

local function OnUpdate()
	if not InCombatLockdown() then
		Buttons.Apply()
	end
end

local function UpdateWatching()
	owner:SetScript("OnUpdate", AnyCombination() and OnUpdate or nil)
end

owner:RegisterEvent("PLAYER_REGEN_ENABLED")
owner:RegisterEvent("PLAYER_REGEN_DISABLED")
owner:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		-- The last moment bindings can change before the fight: let go of combinations (unless a
		-- stick is held right now, so its release still reaches us).
		lastSignature = nil
		Buttons.Apply(true)
	elseif pending then
		Buttons.Apply()
	end
end)

ns.OnRefresh(function()
	lastSignature = nil
	Buttons.Apply()
	UpdateWatching()
end)
ns.OnLogin(function()
	-- After every feature has added itself (they're set up at login too).
	C_Timer.After(0, function()
		Buttons.Apply()
		UpdateWatching()
	end)
end)
