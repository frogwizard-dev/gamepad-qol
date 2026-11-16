-- Track / untrack quests with one button in the quest log (L3 unless changed) instead of Y, the menu,
-- Track. A quest or objective flips that quest; a zone header tracks its quests, or untracks them if
-- all are; the details page works too. Taint: Blizzard's cursor and focus are only read; tracking is
-- the C_QuestLog API, and the log redraws itself from QUEST_WATCH_LIST_CHANGED.
local _, ns = ...

local function IsTracked(questID)
	return C_QuestLog.GetQuestWatchType(questID) ~= nil
end

-- The New Player Experience doesn't let quests be untracked (Blizzard's QuestUtil.CanRemoveQuestWatch).
local function CanUntrack()
	return not (C_PlayerInfo and C_PlayerInfo.IsPlayerNPERestricted and C_PlayerInfo.IsPlayerNPERestricted())
end

local function MaxWatches()
	local constants = Constants and Constants.QuestWatchConsts
	return constants and constants.MAX_QUEST_WATCHES or 25
end

local function Title(questID)
	return C_QuestLog.GetTitleForQuestID(questID) or "Quest"
end

local function Track(questID)
	if C_QuestLog.GetNumQuestWatches() >= MaxWatches() then
		ns.Say(("You can only track %d quests."):format(MaxWatches()))
		return false
	end
	C_QuestLog.AddQuestWatch(questID)
	return IsTracked(questID)
end

local function ToggleQuest(questID)
	if IsTracked(questID) then
		if not CanUntrack() then
			return
		end
		C_QuestLog.RemoveQuestWatch(questID)
		ns.Say("Untracked: " .. Title(questID), 0.75, 0.75, 0.75)
	elseif Track(questID) then
		ns.Say("Tracking: " .. Title(questID), 0.3, 1, 0.3)
	end
end

-- The quests under a header (until the next header).
local function QuestsUnder(headerLogIndex)
	local quests = {}
	for i = headerLogIndex + 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		if not info or info.isHeader then
			break
		end
		if info.questID and info.questID > 0 and not info.isHidden then
			quests[#quests + 1] = info.questID
		end
	end
	return quests
end

local function ToggleHeader(headerLogIndex)
	local quests = QuestsUnder(headerLogIndex)
	if #quests == 0 then
		return
	end
	local allTracked = true
	for _, questID in ipairs(quests) do
		if not IsTracked(questID) then
			allTracked = false
		end
	end
	local info = C_QuestLog.GetInfo(headerLogIndex)
	local name = info and info.title or "these quests"
	if allTracked then
		if not CanUntrack() then
			return
		end
		for _, questID in ipairs(quests) do
			C_QuestLog.RemoveQuestWatch(questID)
		end
		ns.Say("Untracked all in " .. name, 0.75, 0.75, 0.75)
	else
		for _, questID in ipairs(quests) do
			if not IsTracked(questID) and not Track(questID) then
				break
			end
		end
		ns.Say("Tracking all in " .. name, 0.3, 1, 0.3)
	end
end

-- Which part of the Map & Quest Log has the controller: "list", "details" or nil (the map, where L3
-- stays the game's map marker, or the window isn't the focused one).
local function FocusedPart()
	local map = WorldMapFrame
	local manager = GamepadMode and GamepadMode.FrameControlsManager
	if not (map and map:IsShown() and manager and manager.isUIFocused and manager.focusedFrame == map) then
		return nil
	end
	if map.IsQuestFocused and map:IsQuestFocused() then
		return "list"
	end
	if map.IsQuestDetailsFocused and map:IsQuestDetailsFocused() then
		return "details"
	end
	return nil
end

local function ToggleTracking()
	local part = FocusedPart()
	if part == "list" then
		local current = SmartNavigation and SmartNavigation.GetCurrentButton and SmartNavigation:GetCurrentButton()
		if not current then
			return
		end
		if current.questID then
			ToggleQuest(current.questID)
		elseif current.questLogIndex then
			ToggleHeader(current.questLogIndex)
		end
	elseif part == "details" then
		local details = QuestMapFrame and QuestMapFrame.DetailsFrame
		if details and details.questID then
			ToggleQuest(details.questID)
		end
	end
end

local button = CreateFrame("Button", "GamepadQoLTrackQuestButton", UIParent)
button:RegisterForClicks("AnyDown")
button:Hide()
button:SetScript("OnClick", function()
	if ns.Buttons.SomethingHeld() then
		return
	end
	ToggleTracking()
	ns.GuideTried("trackQuest")
end)

local lastPart

-- Ours only while the quest list or a quest's details has the controller; when the window closes the
-- button goes back to auto-run.
ns.Buttons.Add("trackQuest", button, function()
	return FocusedPart() ~= nil
end)

ns.OnLogin(function()
	local map = WorldMapFrame
	if not map then
		return
	end
	-- A frame of ours inside the map window notices the focus moving between list, details and map. It
	-- only reads; binding changes wait a frame so they never run inside Blizzard's opening or closing.
	local watcher = CreateFrame("Frame", nil, map)
	watcher:SetSize(1, 1)
	watcher:SetPoint("TOPLEFT")
	watcher:SetScript("OnUpdate", function()
		local part = FocusedPart()
		if part ~= lastPart then
			lastPart = part
			C_Timer.After(0, function() ns.Buttons.Apply() end)
		end
	end)
	watcher:SetScript("OnHide", function()
		lastPart = nil
		C_Timer.After(0, function() ns.Buttons.Apply() end)
	end)
end)
