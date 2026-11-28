-- Promote: one click for a captain (rank "Kaptein") or higher to promote everyone in our guild
-- who is online, has the rank "Fersking" and has written in their public guild note, to the rank
-- "Spiller". It works on the guild's own ranks, with nothing from the other guilds.
-- The game lets only its own code promote (C_GuildInfo.Promote is protected), so the button is
-- a secure macro button: just before the click it gets a macro of /gpromote lines, one for each
-- rank to climb, and the game runs them. A macro holds 255 characters, so a long list takes
-- more than one click. Nothing can be changed on a secure button in combat, so it hides then.

local ADDON_NAME, ns = ...
local R = ns.R
local M = ns.Members
local Plain, IsSecret = R.Plain, R.IsSecret

local PR = {}
ns.Promote = PR

PR.CAPTAIN, PR.FROM, PR.TO = "Kaptein", "Fersking", "Spiller"
PR.MACRO_MAX = 255

local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if not ok then return nil end
	return Plain(a), Plain(b), Plain(c)
end

local function Same(a, b)
	return type(a) == "string" and type(b) == "string" and strtrim(a):lower() == strtrim(b):lower()
end

-- Our guild's rank names by index, 0 being the guild master.
function PR.Ranks()
	local ranks = {}
	local n = tonumber((Try(GuildControlGetNumRanks))) or 0
	for i = 1, n do
		local name = Try(GuildControlGetRankName, i)
		if type(name) == "string" then ranks[i - 1] = name end
	end
	if not next(ranks) then   -- (from the roster: only ranks someone holds)
		local own = M.ReadOwn()
		for i, name in pairs(own and own.ranks or {}) do ranks[i] = name end
	end
	return ranks
end

local function IndexOf(ranks, name)
	for i, n in pairs(ranks) do
		if Same(n, name) then return i end
	end
	return nil
end

-- What the button would do now: { allowed, reason, from, to, steps, list = { names } }. Not
-- allowed: reason says why (for the tooltip), and the button stays hidden.
function PR.Plan()
	local plan = { list = {} }
	if not R.MyGuild() then plan.reason = "Not in a nerd guild." return plan end
	local ranks = PR.Ranks()
	local captain, from, to = IndexOf(ranks, PR.CAPTAIN), IndexOf(ranks, PR.FROM), IndexOf(ranks, PR.TO)
	if not (captain and from and to) or to >= from then
		plan.reason = ("The guild has no ranks %s, %s and %s in that order."):format(PR.CAPTAIN, PR.TO, PR.FROM)
		return plan
	end
	local _, _, mine = Try(GetGuildInfo, "player")
	if type(mine) ~= "number" or mine > captain then plan.reason = "Only for " .. PR.CAPTAIN .. " and higher." return plan end
	if CanGuildPromote and not Try(CanGuildPromote) then plan.reason = "Your rank may not promote." return plan end
	plan.allowed, plan.from, plan.to, plan.steps = true, from, to, from - to
	local me = R.Me()
	for i = 1, tonumber((Try(GetNumGuildMembers))) or 0 do
		local ok, name, _, rankIndex, _, _, _, note, _, online, _, _, _, _, _, _, _, guid = pcall(GetGuildRosterInfo, i)
		name, rankIndex, note, online, guid = ok and R.Name(Plain(name)), Plain(rankIndex), Plain(note), Plain(online), Plain(guid)
		if name and name ~= me and online and rankIndex == from and type(note) == "string" and strtrim(note) ~= "" then
			local fine = true
			if guid and C_GuildInfo and C_GuildInfo.IsGuildRankAssignmentAllowed then
				fine = Try(C_GuildInfo.IsGuildRankAssignmentAllowed, guid, to + 1) ~= false
			end
			if fine then plan.list[#plan.list + 1] = name end
		end
	end
	table.sort(plan.list)
	return plan
end

-- The macro for the button: /gpromote for each player, once per rank to climb, as many players
-- as fit in a macro. Returns the macro and the players in it.
function PR.Macro(plan)
	local cmd = (type(SLASH_GUILD_PROMOTE1) == "string" and SLASH_GUILD_PROMOTE1 ~= "") and SLASH_GUILD_PROMOTE1 or "/gpromote"
	local lines, done, used = {}, {}, 0
	for _, name in ipairs(plan.list or {}) do
		local mine = {}
		for _ = 1, plan.steps or 1 do mine[#mine + 1] = cmd .. " " .. name end
		local chunk = table.concat(mine, "\n")
		local size = #chunk + (#lines > 0 and 1 or 0)
		if used + size > PR.MACRO_MAX then break end
		lines[#lines + 1] = chunk
		done[#done + 1] = name
		used = used + size
	end
	return table.concat(lines, "\n"), done
end

---------------------------------------------------------------------------
-- The button. It belongs to no frame of Riket's (a secure frame would make its parents and
-- anchors locked in combat too), so it sits on its own over the Members page, placed by hand.
---------------------------------------------------------------------------

local button, page, panel

local function Combat() return InCombatLockdown and InCombatLockdown() and true or false end

local function Tip(self)
	local plan = self.plan
	if not plan then return end
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
	GameTooltip:SetText(("Promote to %s"):format(PR.TO), 1, 1, 1)
	GameTooltip:AddLine(("Everyone online with the rank %s who has written in their guild note."):format(PR.FROM), 1, 0.82, 0, true)
	if #plan.list > 0 then
		GameTooltip:AddLine(table.concat(plan.list, ", "), 1, 1, 1, true)
	else
		GameTooltip:AddLine(("Nobody online with the rank %s and a guild note right now."):format(PR.FROM), 0.6, 0.6, 0.6, true)
	end
	GameTooltip:AddLine(("For %s and higher."):format(PR.CAPTAIN), 0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end

local function Create()
	if button or not CreateFrame then return button end
	local tpl = "SecureActionButtonTemplate"
	local ui = ns.UI
	if ui and ui.HasTemplate("UIPanelButtonTemplate") then tpl = tpl .. ",UIPanelButtonTemplate" end
	local ok, b = pcall(CreateFrame, "Button", "NLRiketPromoteButton", UIParent, tpl)
	if not ok or not b then R.Log("promote button:", b) return nil end
	button = b
	b:SetSize(190, 22)
	b:SetFrameStrata("DIALOG")
	b:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
	b:SetAttribute("type", "macro")
	b:SetAttribute("macrotext", "")
	b:Hide()
	-- just before the game runs the click: the macro for who is there now
	b:SetScript("PreClick", function(self, _, down)
		if Combat() then return end
		local plan = PR.Plan()
		self.plan = plan
		local text, done = "", {}
		if plan.allowed then text, done = PR.Macro(plan) end
		self:SetAttribute("macrotext", text)
		if down == false or down == nil then   -- (say it once, not on both press and release)
			if #done == 0 then
				R.Print(("nobody online with the rank %s and a guild note to promote."):format(PR.FROM))
			else
				local rest = #plan.list - #done
				R.Print(("promoting %s to %s.%s"):format(table.concat(done, ", "), PR.TO,
					rest > 0 and ("  Click again for the other " .. rest .. ".") or ""))
			end
		end
	end)
	b:SetScript("OnEnter", Tip)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

-- Places the button in the Members page's top right corner, in UIParent's coordinates.
local function Place()
	if not (button and panel) then return end
	local right, top = Plain(panel:GetRight()), Plain(panel:GetTop())
	if type(right) ~= "number" or type(top) ~= "number" then return end
	local ps, us = Plain(panel:GetEffectiveScale()), Plain(UIParent:GetEffectiveScale())
	if type(ps) ~= "number" or ps <= 0 then ps = 1 end
	if type(us) ~= "number" or us <= 0 then us = 1 end
	local s = ps / us
	button:ClearAllPoints()
	button:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right * s - 12, top * s - 31)
end

-- Shows the button over the Members page for those it is for, and hides it everywhere else.
-- Nothing changes on it in combat (it hides as combat starts).
function PR.Update()
	if Combat() then return end
	local want = page and page:IsVisible() and panel and panel:IsVisible()
	local plan = want and PR.Plan()
	if not (plan and plan.allowed) then
		if button then button:Hide() end
		return
	end
	if not Create() then return end
	button.plan = plan
	button:SetText(("Promote to %s (%d)"):format(PR.TO, #plan.list))
	button:SetEnabled(#plan.list > 0)
	Place()
	button:Show()
end

-- The Members page tells us where it is; it calls Update as it shows, hides and refreshes.
function PR.Attach(membersPage, riketPanel)
	page, panel = membersPage, riketPanel
	local wait = 0
	page:HookScript("OnShow", PR.Update)
	page:HookScript("OnHide", PR.Update)
	page:HookScript("OnUpdate", function(_, elapsed)   -- (follow the window if it moves)
		wait = wait + (elapsed or 0)
		if wait < 0.5 then return end
		wait = 0
		if button and button:IsShown() and not Combat() then Place() end
	end)
end

R.On("PLAYER_REGEN_DISABLED", function() if button then button:Hide() end end)
R.On("PLAYER_REGEN_ENABLED", function() PR.Update() end)
