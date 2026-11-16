-- Clean Up Bags without the trip to the bag portrait's menu: a controller button while the bags are
-- open (L3 unless changed; Buttons.lua), and optionally whenever the bags close. Taint: both run as
-- their own executions (a press, a timer), never inside Blizzard's code. It isn't on the Y menu, as
-- gamepad menus can't take an addon entry safely (see Bags.lua).
local _, ns = ...

local bagsOpen = false

local function CleanUpBags()
	if InCombatLockdown() then
		return
	end
	PlaySound(SOUNDKIT.UI_BAG_SORTING_01)
	C_Container.SortBags()
end

local function CleanUpIfStillClosed()
	local bags = ContainerFrameCombinedBags
	if ns.db.autoCleanUp and bags and not bags:IsShown() then
		CleanUpBags()
	end
end

-- The controller button: acts on the release, and only when nothing was held with it (a shoulder or
-- trigger held makes it another press, which may be someone else's).
local button = CreateFrame("Button", "GamepadQoLCleanUpButton", UIParent)
button:RegisterForClicks("AnyDown", "AnyUp")
button:Hide()
local heldOnPress = false
button:SetScript("OnClick", function(_, _, down)
	if down then
		heldOnPress = ns.Buttons.SomethingHeld()
		return
	end
	if not heldOnPress and not ns.Buttons.SomethingHeld() then
		CleanUpBags()
		ns.GuideTried("cleanUp")
	end
	heldOnPress = false
end)

ns.Buttons.Add("cleanUp", button, function()
	return bagsOpen
end)

ns.OnLogin(function()
	local bags = ContainerFrameCombinedBags
	if not bags then
		return
	end

	-- A frame of ours inside the bag window shows and hides with it, so we hear of both without hooking
	-- Blizzard's frames. (Alt+Z hides it too, while the bag window still counts as shown.)
	local watcher = CreateFrame("Frame", nil, bags)
	watcher:SetAllPoints(bags)

	-- Until the prompt bar exists (or on a client without one), the hint goes in the bag window's bottom bar.
	local barHint = watcher:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	if bags.MoneyFrame then
		watcher:SetFrameLevel(bags.MoneyFrame:GetFrameLevel() + 5)
		barHint:SetPoint("LEFT", bags.MoneyFrame, "LEFT", 8, 0)
	else
		barHint:SetPoint("BOTTOMLEFT", bags, "BOTTOMLEFT", 16, 14)
	end

	local piece  -- the prompt bar section, made the first time the bar is there

	-- The button icons by name from the game's icon set, drawn on our own textures (its icon template
	-- registers itself with a shared manager, so it isn't used).
	local function IconAtlas(key)
		local util = InputIconTextureSetUtility
		if not (util and util.GetActiveInputIconButtonTextures and InputDeviceIconVariant) then
			return nil
		end
		local ok, textures = pcall(util.GetActiveInputIconButtonTextures, key, InputDeviceIconVariant.Standard)
		return ok and type(textures) == "table" and textures[InputIconTextureState and InputIconTextureState.Normal or 1] or nil
	end

	local function SetIcon(texture, key, left)
		local atlas = IconAtlas(key)
		texture:ClearAllPoints()
		if not atlas then
			texture:Hide()
			return false
		end
		texture:SetAtlas(atlas)
		-- Newer prompt art has extra padding round the button, as Blizzard's own icons allow for.
		local info = C_Texture.GetAtlasInfo(atlas)
		local pad = (info and info.width and info.width >= 70) and 5 or 0
		texture:SetSize(24 + pad * 2, 24 + pad * 2)
		texture:SetPoint("LEFT", piece, "LEFT", left - pad, 0)
		texture:Show()
		return true
	end

	-- "L3  Clean Up Bags" as one more section of Blizzard's prompt bar: a frame of ours in the bar's art,
	-- attached to it. Nothing goes into the footer itself (that would put us in its binding handling).
	local function BuildPiece(container)
		piece = CreateFrame("Frame", nil, container)
		-- The left end, as the bags usually sit at the screen's right edge; the 6 overlaps the borders,
		-- as Blizzard joins its own sections.
		piece:SetPoint("TOPRIGHT", container, "TOPLEFT", 6, 0)
		piece:SetPoint("BOTTOMRIGHT", container, "BOTTOMLEFT", 6, 0)
		piece.bg = piece:CreateTexture(nil, "BACKGROUND")
		piece.bg:SetAllPoints()
		piece.bg:SetAtlas("gamepad-footer-slot-bg")
		piece.border = piece:CreateTexture(nil, "BORDER")
		piece.border:SetAllPoints()
		piece.border:SetAtlas("gamepad-footer-slot-frameneutral")
		piece.icon1 = piece:CreateTexture(nil, "ARTWORK")
		piece.icon2 = piece:CreateTexture(nil, "ARTWORK")
		piece.plus = piece:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		piece.plus:SetText("+")
		piece.text = piece:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		piece.text:SetText(BAG_CLEANUP_BAGS or "Clean Up Bags")
	end

	-- Fill the section for the current button; false if the icons can't be had.
	local function LayOutPiece(spec)
		local held, pressed = ns.Buttons.Parse(spec)
		local x = 10
		piece.icon2:Hide()
		piece.plus:Hide()
		if held then
			if not SetIcon(piece.icon1, held, x) then return false end
			x = x + 24 + 4
			piece.plus:ClearAllPoints()
			piece.plus:SetPoint("LEFT", piece, "LEFT", x, 0)
			piece.plus:Show()
			x = x + piece.plus:GetStringWidth() + 4
			if not SetIcon(piece.icon2, pressed, x) then return false end
		else
			if not SetIcon(piece.icon1, pressed, x) then return false end
		end
		x = x + 24 + 4
		piece.text:ClearAllPoints()
		piece.text:SetPoint("LEFT", piece, "LEFT", x, 0)
		piece:SetWidth(x + piece.text:GetStringWidth() + 10)
		return true
	end

	local function UpdateHint()
		local spec = ns.Buttons.KeyFor("cleanUp")
		local wanted = ns.db.cleanUpHint and ns.IsGamepadUI() and spec and spec ~= "none"

		local footer = bags.gamepadFooter
		local legend = footer and footer.inputLegend
		local container = legend and legend.promptContainerFrame
		if container and not piece then
			BuildPiece(container)
		end
		local inBar = false
		if piece then
			inBar = wanted and LayOutPiece(spec) or false
			piece:SetShown(inBar)
		end

		if wanted and not inBar then
			local held, pressed = ns.Buttons.Parse(spec)
			local names = ns.Buttons.SHORT_NAMES
			local keys = held and (names[held] .. " + " .. names[pressed]) or names[pressed]
			barHint:SetText("|cffffffff" .. keys .. "|r  " .. (BAG_CLEANUP_BAGS or "Clean Up Bags"))
		end
		barHint:SetShown((wanted and not inBar) and true or false)
	end
	ns.OnRefresh(UpdateHint)
	UpdateHint()
	-- These run inside Blizzard's own opening and closing of the bags, where a script can taint what runs
	-- after it (rebinding mid-close got SetPreferredGamepadInteractTarget forbidden): the work waits a frame.
	local function Opened()
		bagsOpen = bags:IsShown()
		UpdateHint()
		ns.Buttons.Apply()
	end
	local function Closed()
		bagsOpen = bags:IsShown()
		if not bagsOpen then
			ns.Buttons.Apply()
			CleanUpIfStillClosed()
		end
	end
	watcher:SetScript("OnShow", function()
		C_Timer.After(0, Opened)
		C_Timer.After(0.1, UpdateHint)
	end)
	watcher:SetScript("OnHide", function()
		C_Timer.After(0, Closed)
	end)
	bagsOpen = bags:IsVisible()
end)
