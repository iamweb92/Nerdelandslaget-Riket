-- Promote: one click for a captain (rank "Kaptein") or higher to promote everyone in our guild
-- who is online, has the rank "Fersking" and has written a name in their public guild note, to
-- the rank "Spiller". A note of only professions ("Ench", "BS/LW", "Alch 300") holds no name and
-- doesn't count; anything else in it does. It works on the guild's own ranks, with nothing from
-- the other guilds.
-- The game lets only its own code promote (C_GuildInfo.Promote is protected), so the button is
-- a secure macro button: just before the click it gets a macro of /gpromote lines, one for each
-- rank to climb, and the game runs them. A macro holds 255 characters, so a long list takes
-- more than one click. Nothing can be changed on a secure button in combat, so it hides then.
-- Riket's admin sees the button in every guild; where his rank (or the guild's ranks) doesn't
-- allow it, a click only says so and runs nothing.

local ADDON_NAME, ns = ...
local R = ns.R
local M = ns.Members
local Plain, IsSecret = R.Plain, R.IsSecret

local PR = {}
ns.Promote = PR

PR.CAPTAIN, PR.FROM, PR.TO = "Kaptein", "Fersking", "Spiller"
PR.MACRO_MAX = 255
PR.ADMINS = { ["Sexy Neophyte"] = true }

function PR.IsAdmin() return PR.ADMINS[R.Me() or ""] == true end

---------------------------------------------------------------------------
-- Is there a name in a guild note? Every word of letters (two or more) counts as a name, but
-- the words for professions, in English, Norwegian and the usual short forms, and the words
-- that go with them (numbers, "and", "max", "prof"...). Words run together ("alchherb", "BSLW")
-- and plurals ("JCs") count as theirs.
---------------------------------------------------------------------------

PR.NOT_NAMES = {}
for w in ([[
alchemy alchemist alch alc alk alky alchy alche alchem alkemi alkymi alkymist alchemie
transmute transmuter transmutation elixir elixirs potion potions pot pots flask flasks
blacksmithing blacksmith bs bsmith smith smithing smithy armorsmith armoursmith weaponsmith
swordsmith axesmith hammersmith smed smeding smedarbeid
enchanting enchanter enchant ench enc enchy chanter chant dust disenchant disenchanting de
engineering engineer engi engy eng engie engin enginer engineeer gnomish goblin ingeniør ingenior ingenjør
herbalism herbalist herbing herb herbal herbo herby herbalisme urter urt urtesanking urtesanker urteplukker
inscription inscriber scribe scribing insc inscr scrib
jewelcrafting jewelcrafter jewelcraft jewel jewler jeweler jeweller jc gem gems juveler gullsmed
leatherworking leatherworker leatherwork leather lw lwer lwing tribal elemental dragonscale
lær lærarbeid lærarbeider garver garving
mining miner mine min smelting smelt gruve gruvedrift gruvearbeider
skinning skinner skin skinn flå flåing flåer flaa flaaing
tailoring tailor tail tai tailo cloth clothier mooncloth spellcloth shadoweave spellfire skredder sy søm sying
cooking cook chef kokk matlaging
first aid firstaid fa bandage førstehjelp forstehjelp
fishing fisher fisherman fish fiske fisker fiskar
prof proff profession yrke yrker craft crafter crafting gather gathering gatherer
master grandmaster grand artisan expert journeyman apprentice illustrious spec specc specced specialization
max maxed maks lvl lv level skill skilled done ferdig and og the of av med with w discord disc dc
]]):gmatch("%S+") do PR.NOT_NAMES[w] = true end

-- what run-together words can be made of: the long ones and the well-known short ones
local PIECES = { bs = true, lw = true, jc = true, fa = true }
for w in pairs(PR.NOT_NAMES) do if #w >= 3 then PIECES[w] = true end end

local function Fold(s)   -- lower case, Æ Ø Å too (lower() knows only A to Z)
	return (s:lower():gsub("\195\134", "\195\166"):gsub("\195\152", "\195\184"):gsub("\195\133", "\195\165"))
end

local function RunTogether(word)
	local n = #word
	if n > 40 then return false end
	local can = { [0] = true }
	for i = 2, n do
		for j = 0, i - 2 do
			if can[j] and PIECES[word:sub(j + 1, i)] then can[i] = true break end
		end
	end
	return can[n] == true
end

-- a plural of a profession word ("JCs", "enchs", "herbs"), but not of a short one a name could
-- end in ("Mats", "Des")
local function Plural(word)
	if word:sub(-1) ~= "s" then return nil end
	local base = word:sub(1, -2)
	if #base >= 4 or PIECES[base] and #base == 2 then return base end
	return nil
end

local function NotName(word)
	if PR.NOT_NAMES[word] or RunTogether(word) then return true end
	local base = Plural(word)
	return base ~= nil and (PR.NOT_NAMES[base] or RunTogether(base))
end

function PR.NoteHasName(note)
	if type(note) ~= "string" or IsSecret(note) then return false end
	for word in Fold(note):gmatch("[%a\128-\255]+") do
		if #word >= 2 and not NotName(word) then return true end
	end
	return false
end

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
-- allowed: reason says why (for the tooltip and the chat), and the button stays hidden, but for
-- Riket's admin.
function PR.Plan()
	local plan = { list = {} }
	local guild = R.MyGuild()
	if not guild then plan.reason = "You are in no nerd guild." return plan end
	local ranks = PR.Ranks()
	local captain, from, to = IndexOf(ranks, PR.CAPTAIN), IndexOf(ranks, PR.FROM), IndexOf(ranks, PR.TO)
	if not (captain and from and to) or to >= from then
		plan.reason = ("%s has no ranks %s, %s and %s, so there is nobody to promote."):format(guild, PR.CAPTAIN, PR.TO, PR.FROM)
		return plan
	end
	local _, _, mine = Try(GetGuildInfo, "player")
	if type(mine) ~= "number" or mine > captain then
		plan.reason = ("You don't have the rank for this in %s: only %s and higher can promote."):format(guild, PR.CAPTAIN)
		return plan
	end
	if CanGuildPromote and not Try(CanGuildPromote) then plan.reason = ("Your rank in %s may not promote."):format(guild) return plan end
	plan.allowed, plan.from, plan.to, plan.steps = true, from, to, from - to
	local me = R.Me()
	for i = 1, tonumber((Try(GetNumGuildMembers))) or 0 do
		local ok, name, _, rankIndex, _, _, _, note, _, online, _, _, _, _, _, _, _, guid = pcall(GetGuildRosterInfo, i)
		name, rankIndex, note, online, guid = ok and R.Name(Plain(name)), Plain(rankIndex), Plain(note), Plain(online), Plain(guid)
		if name and name ~= me and online and rankIndex == from and PR.NoteHasName(note) then
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
	GameTooltip:AddLine(("Everyone online with the rank %s who has written a name in their guild note. Professions alone (\"Ench\", \"BS/LW\") don't count."):format(PR.FROM), 1, 0.82, 0, true)
	if not plan.allowed then
		GameTooltip:AddLine(plan.reason or "", 1, 0.3, 0.3, true)
		GameTooltip:AddLine("Shown to you as Riket's admin. A click does nothing here.", 0.6, 0.6, 0.6, true)
	elseif #plan.list > 0 then
		GameTooltip:AddLine(table.concat(plan.list, ", "), 1, 1, 1, true)
	else
		GameTooltip:AddLine(("Nobody online with the rank %s and a name in their guild note right now."):format(PR.FROM), 0.6, 0.6, 0.6, true)
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
			if not plan.allowed then
				R.Print((plan.reason or "You can't promote here."):gsub("^You", "you") .. " Nothing was done.")
			elseif #done == 0 then
				R.Print(("nobody online with the rank %s and a name in their guild note to promote."):format(PR.FROM))
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
	if not (plan and (plan.allowed or PR.IsAdmin())) then
		if button then button:Hide() end
		return
	end
	if not Create() then return end
	button.plan = plan
	if plan.allowed then
		button:SetText(("Promote to %s (%d)"):format(PR.TO, #plan.list))
		button:SetEnabled(#plan.list > 0)
	else   -- (the admin, without the rank: the click explains)
		button:SetText(("Promote to %s"):format(PR.TO))
		button:SetEnabled(true)
	end
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
