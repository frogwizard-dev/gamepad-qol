-- Peek map: hold the button and the map shows; let go and it closes. A map you opened yourself is
-- left alone.
--
-- Opening a game window from addon code taints it on Forever, so the button is a secure one and
-- everything happens in its secure snippet:
--  * out of combat the map is shown directly, not opened as a window, so Forever's gamepad UI
--    doesn't take the controller and you keep moving;
--  * in combat (when the snippet can't touch the map) it runs "/click QuestLogMicroButton", the
--    game's own button for the Map & Quest Log, once to open and once to close;
--  * the map's first showing goes through that button too: until it has been opened as a window it
--    has no size, and shown directly it would be drawn nowhere.
-- (Improved Forever's peek map, by markgravity, MIT, showed the way.)
local ADDON, ns = ...

local MACRO = "/click QuestLogMicroButton"


local button = CreateFrame("Button", "GamepadQoLPeekMapButton", UIParent,
	"SecureActionButtonTemplate, SecureHandlerBaseTemplate")
button:SetSize(1, 1)
button:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -20, 20)
button:RegisterForClicks("AnyDown", "AnyUp")
button:SetAttribute("macrotext", MACRO)

-- Runs before the button's own click. Returning false stops the click; otherwise the macro runs, on
-- this press or release whatever the "cast on key down" setting says (useOnKeyDown).
SecureHandlerWrapScript(button, "OnClick", button, [[
	self:SetAttribute("type", nil)
	local map = self:GetFrameRef("map")
	local scroll = self:GetFrameRef("scroll")
	local combat = PlayerInCombat()
	local usable = map and not combat

	if down then
		if self:GetAttribute("gq-peeking") then return false end
		if usable and map:IsShown() then return false end
		self:SetAttribute("gq-peeking", true)
		if usable and scroll and (scroll:GetWidth() or 0) > 0 then
			map:Show()
			self:SetAttribute("gq-direct", true)
			return false
		end
		self:SetAttribute("gq-direct", nil)
	else
		if not self:GetAttribute("gq-peeking") then return false end
		self:SetAttribute("gq-peeking", nil)
		local direct = self:GetAttribute("gq-direct")
		self:SetAttribute("gq-direct", nil)
		if usable then
			if not map:IsShown() then return false end
			if direct then
				map:Hide()
				return false
			end
		end
	end

	self:SetAttribute("useOnKeyDown", down and true or false)
	self:SetAttribute("type", "macro")
]])

ns.Buttons.Add("peekMap", "Peek at the map (hold)", button)

-- After the secure part has run (our own button's script; nothing of Blizzard's).
button:SetScript("PostClick", function(_, _, down)
	if down then
		ns.GuideTried("peekMap")
	end
end)

ns.OnLogin(function()
	if WorldMapFrame then
		button:SetFrameRef("map", WorldMapFrame)
		if WorldMapFrame.ScrollContainer then
			button:SetFrameRef("scroll", WorldMapFrame.ScrollContainer)
		end
	end
end)
