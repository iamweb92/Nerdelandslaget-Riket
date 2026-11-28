-- Offline test for Nerdelandslaget: Riket. Simulates several WoW clients (each its own globals)
-- in different "nerd" guilds on one shared channel, with a fake clock and a fake guild window
-- (J), and checks the guild chat bridge, the online lists, the professions board, the Discord
-- name and Riket in the guild window: its tabs, its pages and the merged guild chat.
-- Usage: luajit riket_test.lua <addon folder>
local DIR = assert(arg[1], "addon folder")
local FILES = { "Core.lua", "Chat.lua", "Members.lua", "Promote.lua", "Professions.lua", "UI.lua" }

local now = 1795000000
local timers = {}
local function Schedule(t, fn, every) timers[#timers + 1] = { at = t, fn = fn, every = every } end
local function Advance(seconds)
	local stop = now + seconds
	while true do
		table.sort(timers, function(a, b) return a.at < b.at end)
		local t = timers[1]
		if not t or t.at > stop then break end
		table.remove(timers, 1)
		now = t.at
		t.fn()
		if t.every then Schedule(now + t.every, t.fn, t.every) end
	end
	now = stop
end


-- A frame stand-in: every method exists; Get* answer a harmless value.
local function Stub(name)
	local f = { scripts = {}, events = {}, name = name }
	return setmetatable(f, { __index = function(t, k)
		if k == "SetScript" then return function(self, kind, fn) self.scripts[kind] = fn end end
		if k == "GetScript" then return function(self, kind) return self.scripts[kind] end end
		if k == "HookScript" then return function(self, kind, fn)
			local old = self.scripts[kind]
			self.scripts[kind] = old and function(...) old(...) fn(...) end or fn
		end end
		if k == "RegisterEvent" then return function(self, e) self.events[e] = true end end
		if k == "IsShown" or k == "IsVisible" then return function(self) return self.shown ~= false end end
		if k == "Show" then return function(self) self.shown = true if self.scripts.OnShow then self.scripts.OnShow(self) end end end
		if k == "Hide" then return function(self) self.shown = false if self.scripts.OnHide then self.scripts.OnHide(self) end end end
		if k == "SetShown" then return function(self, v) self.shown = v and true or false end end
		if k == "GetText" then return function(self) return self.text or "" end end
		if k == "SetText" then return function(self, v) self.text = v end end
		if k == "AddMessage" then return function(self, line) local l = rawget(self, "lines") or {} rawset(self, "lines", l) table.insert(l, line) end end
		if k == "Clear" then return function(self) rawset(self, "lines", {}) end end
		if k == "SetAlpha" then return function(self, a) self.alpha = a end end
		if k == "SetFrameStrata" then return function(self, v) self.strata = v end end
		if k == "SetPoint" then return function(self, ...) local p = rawget(self, "points") or {} rawset(self, "points", p) p[#p + 1] = { ... } end end
		if k == "ClearAllPoints" then return function(self) rawset(self, "points", {}) end end
		if k == "SetEnabled" then return function(self, v) self.enabled = v and true or false end end
		if k == "GetPoint" then return function() return "CENTER", nil, "CENTER", 0, 0 end end
		if k == "GetMinMaxValues" then return function() return 0, 0 end end
		if k == "GetHeight" then return function() return 400 end end
		if k == "GetWidth" then return function() return 700 end end
		if k == "GetCenter" then return function() return 100, 100 end end
		if k == "GetChecked" then return function(self) return self.checked == true end end
		if k == "SetAttribute" then return function(self, a, v) local t = rawget(self, "attrs") or {} rawset(self, "attrs", t) t[a] = v end end
		if k == "GetAttribute" then return function(self, a) return (rawget(self, "attrs") or {})[a] end end
		if k == "SetChecked" then return function(self, v) self.checked = v and true or false end end
		if k == "HasFocus" then return function() return false end end
		if k == "GetTop" or k == "GetBottom" then return function() return nil end end
		if type(k) == "string" and k:match("^Get") then return function() return 0 end end
		if type(k) == "string" and k:match("^Create") then return function() return Stub() end end
		if type(k) == "string" and k:match("^%u") then return function() end end
		return nil
	end })
end

local clients, byName = {}, {}
-- recipe names, as the game's spell data has them
local RECIPE_NAMES = {}
for k = 0, 49 do RECIPE_NAMES[2660 + k * 7] = ((k % 2 == 0) and "Copper " or "Bronze ") .. ("Thing %02d"):format(k) end
local GUILD_CLUB, GUILD_STREAM, OFFICER_STREAM, OTHER_CLUB = "club-guild", "stream-guild", "stream-officer", "club-friends"

local function Client(name, guild, opts)
	opts = opts or {}
	local env = setmetatable({}, { __index = _G })
	local c = { name = name, guild = guild, env = env, frames = {}, sent = {}, chat = {}, clubMessages = {}, opts = opts }
	env._G = env
	env.time = function() return now end
	env.GetTime = function() return now end
	env.date = function(fmt, t) return os.date(fmt, t or now) end
	c.prints = {}
	env.print = function(...) c.printed = (c.printed or 0) + 1 c.prints[#c.prints + 1] = table.concat({ ... }, " ") end
	env.C_Timer = {
		After = function(s, fn) Schedule(now + s, fn) end,
		NewTicker = function(s, fn) Schedule(now + s, fn, s) end,
	}
	local KNOWN = { UIPanelButtonTemplate = true, UICheckButtonTemplate = true, InputBoxTemplate = true,
		WowStyle1DropdownTemplate = true, WowScrollBoxList = true, MinimalScrollBar = true, WowTrimScrollBar = true,
		InsetFrameTemplate = true, CommunitiesFrameTabTemplate = true, BackdropTemplate = true, SecureActionButtonTemplate = true }
	env.C_XMLUtil = { GetTemplateInfo = function(t)
		if opts.noTemplates then return nil end
		if KNOWN[t] then return { type = "Frame" } end
	end }
	c.menus = {}
	local function Root()
		local r = { items = {} }
		function r:CreateRadio(text, is, set, data) self.items[#self.items + 1] = { text = text, is = is, set = set, data = data } return Stub() end
		function r:CreateButton(text, fn) self.items[#self.items + 1] = { text = text, fn = fn } return Stub() end
		function r:CreateTitle(text) self.items[#self.items + 1] = { title = text } return Stub() end
		return r
	end
	c.Root = Root
	env.CreateFrame = function(kind, fname, parent, template)
		for t in (template or ""):gmatch("[^,%s]+") do
			if not env.C_XMLUtil.GetTemplateInfo(t) then error("Couldn't find inherited node " .. t) end
		end
		local f = Stub(fname)
		f.kind, f.template, f.parent = kind, template, parent
		if template == "WowScrollBoxList" then
			f.rows = {}
			f.SetDataProvider = function(self, dp)
				self.dp = dp
				for i, item in ipairs(dp.items) do
					local row = self.rows[i] or Stub()
					self.rows[i] = row
					self.view.init(row, item)
				end
			end
		elseif kind == "DropdownButton" then
			f.SetupMenu = function(self, gen) self.gen = gen self:GenerateMenu() end
			f.GenerateMenu = function(self) local root = Root() self.gen(self, root) self.root = root end
		end
		c.frames[#c.frames + 1] = f
		if fname then env[fname] = f end
		return f
	end
	env.CreateScrollBoxListLinearView = function()
		local v = {}
		function v:SetElementExtent(h) self.h = h end
		function v:SetElementInitializer(kind, fn) self.kind, self.init = kind, fn end
		return v
	end
	env.ScrollUtil = {
		InitScrollBoxListWithScrollBar = function(box, bar, view) box.view = view end,
		AddManagedScrollBarVisibilityBehavior = function() end,
		InitScrollingMessageFrameWithScrollBar = function(smf, bar) c.chatBar = bar end,
	}
	env.CreateDataProvider = function(items) return { items = items } end
	env.CreateAnchor = function(...) return { ... } end
	env.ScrollBoxConstants = { RetainScrollPosition = 1 }
	env.SOUNDKIT = { IG_CHARACTER_INFO_TAB = 841 }
	env.PlaySound = function(k) c.sounds = (c.sounds or 0) + 1 end
	local version = io.open(DIR .. "/Nerdelandslaget_Riket.toc"):read("*a"):match("## Version: ([%d%.]+)")
	env.C_AddOns = {
		GetAddOnMetadata = function(_, key) if key == "Version" then return version end end,
		IsAddOnLoaded = function(n) return n == "Blizzard_Communities" and env.CommunitiesFrame ~= nil end,
	}
	env.UIParent, env.Minimap = Stub(), Stub()
	env.GameTooltip = Stub()
	env.GameTooltip.SetText = function(self, t) self.tlines = { t } end
	env.GameTooltip.AddLine = function(self, t) table.insert(self.tlines, t) end
	env.GameTooltip.SetSpellByID = function(self, id) self.tlines = { "spell " .. id } end
	env.C_Spell = {
		GetSpellName = function(id) return RECIPE_NAMES[id] end,
		GetSpellTexture = function(id) return 134400 + (id % 7) end,
		GetSpellLink = function(id) return "|cff71d5ff|Hspell:" .. id .. ":0|h[" .. (RECIPE_NAMES[id] or ("Spell " .. id)) .. "]|h|r" end,
	}
	env.ChatFrame_SendTell = function(who) c.tellTo = who end
	env.SlashCmdList = {}
	env.tinsert = table.insert
	env.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
	env.Mixin = function(o) return o end
	env.BackdropTemplateMixin = {}
	env.STANDARD_TEXT_FONT = "font"
	env.NUM_CHAT_WINDOWS = 2
	env.ChatFrame1 = Stub()
	env.ChatFrame1.messageTypeList = { "SAY", "GUILD" }
	env.DEFAULT_CHAT_FRAME = env.ChatFrame1
	env.ChatTypeInfo = { GUILD = { r = 0.25, g = 1, b = 0.25 } }
	env.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
	env.issecretvalue = function(v) return v == "SECRET" end
	env.UnitName = function() if opts.fullUnitName then return name end return (name:match("^(%S+)")) end
	env.UnitClass = function() return "Warrior", opts.class or "WARRIOR" end
	env.UnitLevel = function() return opts.level or 60 end
	env.IsInGuild = function() return c.guild ~= nil end
	env.GetGuildInfo = function() return c.guild, "Member", c.rankIndex or opts.rankIndex or 3 end
	if opts.ranks then
		env.GuildControlGetNumRanks = function() local n = 0 for i in pairs(opts.ranks) do n = math.max(n, i + 1) end return n end
		env.GuildControlGetRankName = function(i) return opts.ranks[i - 1] end
	end
	env.CanGuildPromote = function() return opts.canPromote == true end
	env.InCombatLockdown = function() return c.combat == true end
	local roster = opts.roster or { { name, 60, "WARRIOR", true } }
	env.GetNumGuildMembers = function() return #roster, #roster end
	env.GetGuildRosterInfo = function(i)
		local r = roster[i]
		local note = (c.notes and c.notes[r[1]]) or r[7] or ""
		return r[1] .. "-CAMWOWEU5Realm2PvP", r[6] or "Member", r[5] or 3, r[2], "Class", "Stormwind", note, "", r[4], 0, r[3],
			0, 0, false, false, 0, (not opts.noGuid) and ("Player-1-" .. r[1]) or nil
	end
	env.GetGuildRosterLastOnline = function(i)
		local r = roster[i]
		if not r or r[4] then return nil end
		return 0, 0, r[8] or 0, 0
	end
	c.notes = {}
	env.C_GuildInfo = {
		GuildRoster = function() end,
		SetNote = function(guid, text, isPublic) c.noteSet = { guid = guid, text = text, public = isPublic } c.notes[name] = text end,
	}
	env.UnitGUID = function() return "Player-1-" .. name end
	env.CanEditPublicNote = function() return opts.canEdit == true end
	c.popups = {}
	env.StaticPopupDialogs = {}
	env.StaticPopup_Show = function(which, a, b) c.popups[#c.popups + 1] = { which = which, a = a, b = b } return Stub() end
	env.hooksecurefunc = function(t, key, fn)
		if type(t) == "string" then t, key, fn = env, t, key end
		local orig = t[key]
		t[key] = function(...) local r = { orig(...) } fn(...) return unpack(r) end
	end
	env.Enum = {
		SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3, ChannelThrottle = 8 },
		ClubType = { BattleNet = 0, Character = 1, Guild = 2 },
		ClubStreamType = { General = 0, Guild = 1, Officer = 2 },
	}
	-- the game's side of guild chat: messages per client, as C_Club holds them
	env.C_Club = {
		GetClubInfo = function(id) return { clubType = id == GUILD_CLUB and 2 or 1 } end,
		GetStreamInfo = function(clubId, streamId) return { streamType = streamId == GUILD_STREAM and 1 or 2 } end,
		GetMessageRanges = function(clubId, streamId)
			if streamId ~= GUILD_STREAM or #c.clubMessages == 0 then return {} end
			return { { oldestMessageId = { epoch = 0, position = 1 }, newestMessageId = { epoch = 0, position = #c.clubMessages } } }
		end,
		GetMessagesInRange = function(clubId, streamId, oldest, newest)
			local out = {}
			for i = oldest.position, newest.position do out[#out + 1] = c.clubMessages[i] end
			return out
		end,
		GetMessageInfo = function(clubId, streamId, id) return c.clubMessages[id.position] end,
	}
	-- the guild window (J): Blizzard_Communities, loaded at the first ToggleGuildFrame. Its four
	-- side tabs sit with GuildInfoTab above GuildBenefitsTab, unlike their order in its code.
	local TAB_SPOTS = { ChatTab = { 400, 368 }, RosterTab = { 351, 319 }, GuildInfoTab = { 302, 270 }, GuildBenefitsTab = { 253, 221 } }
	local function Communities()
		local host = Stub("CommunitiesFrame")
		host.shown = false
		host.GetWidth = function() return opts.hostWidth or 814 end
		host.GetHeight = function() return 426 end
		host.mode = "CHAT"
		host.club, host.stream = GUILD_CLUB, GUILD_STREAM
		host.GetDisplayMode = function(self) return self.mode end
		host.SetDisplayMode = function(self, m) self.mode = m end
		host.GetSelectedClubId = function(self) return self.club end
		host.GetSelectedStreamId = function(self) return self.stream end
		host.SelectClub = function(self, id) self.club = id end
		host.SelectStream = function(self, clubId, streamId) self.club, self.stream = clubId, streamId end
		for i, key in ipairs({ "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab" }) do
			local t = Stub(key)
			t.checked, t.shown = (i == 1), true
			local spot = TAB_SPOTS[key]
			t.GetTop = function() return spot[1] end
			t.GetBottom = function() return spot[2] end
			host[key] = t
		end
		host.Chat = Stub("Chat")
		host.Chat.MessageFrame = Stub("Blizzard chat")
		host.Chat.ScrollBar = Stub("Blizzard chat bar")
		env.CommunitiesFrame = host
		env.COMMUNITIES_FRAME_DISPLAY_MODES = { MINIMIZED = "MINIMIZED", CHAT = "CHAT", ROSTER = "ROSTER" }
		return host
	end
	env.ToggleGuildFrame = function()
		if not env.CommunitiesFrame then Communities() c.Fire("ADDON_LOADED", "Blizzard_Communities") end
		local h = env.CommunitiesFrame
		if h.shown then h:Hide() else h:Show() end
	end
	env.GetChannelName = function(n) if n == "NLRiketNet" and c.joined then return 5, n end return 0 end
	env.JoinTemporaryChannel = function(n) if not opts.noChannel then c.joined = true end end
	env.C_ChatInfo = {
		RegisterAddonMessagePrefix = function() end,
		InChatMessagingLockdown = function() return c.lockdown == true end,
		SendAddonMessage = function(prefix, text, dist, target)
			assert(#text <= 255, "addon message too long: " .. #text)
			c.sent[#c.sent + 1] = text
			c.sentAt = c.sentAt or {}
			c.sentAt[#c.sent] = now
			for _, o in ipairs(clients) do
				if o.loaded and ((dist == "CHANNEL" and o.joined) or (dist == "GUILD" and o.guild == c.guild)) then
					o.Fire("CHAT_MSG_ADDON", prefix, text, dist, name .. "-CAMWOWEU5Realm2PvP")
				end
			end
			return 0
		end,
		-- /g: the game keeps it as a guild chat message for everyone in the guild and tells them
		SendChatMessage = function(text, kind)
			for _, o in ipairs(clients) do
				if o.guild == c.guild then
					local id = { epoch = now * 1e6, position = #o.clubMessages + 1 }
					local shown = o.opts.protectedChat and ("|Kw" .. (4999 + id.position) .. "|k") or text
					o.clubMessages[#o.clubMessages + 1] = { messageId = id, author = { name = name .. "-CAMWOWEU5Realm2PvP", classID = opts.class == "MAGE" and 8 or 1 }, content = shown }
					o.Fire("CHAT_MSG_GUILD", shown, name .. "-CAMWOWEU5Realm2PvP")
					o.Fire("CLUB_MESSAGE_ADDED", GUILD_CLUB, GUILD_STREAM, id)
				end
			end
		end,
	}
	env.C_SkillInfo = { GetSkillLineInfoByID = function(id)
		local p = (opts.profs or {})[id]
		return { name = ({ [164] = "Blacksmithing", [186] = "Mining", [171] = "Alchemy" })[id] or ("Skill" .. id),
			rank = p and p[1] or 0, maxRank = p and p[2] or 0 }
	end }
	env.C_TradeSkillUI = {
		GetBaseProfessionInfo = function()
			local p = (opts.profs or {})[c.openProf]
			return { professionID = c.openProf, professionName = ({ [164] = "Blacksmithing", [171] = "Alchemy", [186] = "Mining" })[c.openProf],
				skillLevel = p and p[1] or 250, maxSkillLevel = p and p[2] or 300 }
		end,
		-- recipes: opts.recipes[skillLine] = { { id, learned } }
		GetAllRecipeIDs = function()
			local out = {}
			for i, r in ipairs((opts.recipes or {})[c.openProf] or {}) do out[i] = r[1] end
			return out
		end,
		GetRecipeInfo = function(id)
			for _, r in ipairs((opts.recipes or {})[c.openProf] or {}) do
				if r[1] == id then return { recipeID = id, learned = r[2], name = RECIPE_NAMES[id] } end
			end
		end,
		GetTradeSkillListLink = function() return "|cffffd000|Htrade:Player-1234-ABCD:2018:164|h[Blacksmithing]|h|r" end,
	}
	env.MenuUtil = { CreateContextMenu = function(owner, gen) local root = Root() gen(owner, root) c.menus[#c.menus + 1] = root end }
	env.SetItemRef = function(ref, link) c.opened = ref if c.recipesOpen then c.Fire("TRADE_SKILL_SHOW") end end
	env.IsModifiedClick = function(kind) return kind == "CHATLINK" and c.shift == true end
	env.ChatEdit_InsertLink = function(link) c.inserted = link c.insertedAll = c.insertedAll or {} table.insert(c.insertedAll, link) return true end
	function c.Fire(event, ...)
		for _, f in ipairs(c.frames) do
			if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
		end
	end
	local ns = {}
	for _, file in ipairs(FILES) do
		local chunk = assert(loadfile(DIR .. "/" .. file))
		setfenv(chunk, env)
		chunk("Nerdelandslaget_Riket", ns)
	end
	c.ns = ns
	c.R = ns.R
	clients[#clients + 1] = c
	byName[name] = c
	c.loaded = true
	if opts.discord ~= false then env.NLRiketDB = { discord = opts.discord or (name:match("^(%S+)"):lower() .. "_dc") } end
	c.Fire("ADDON_LOADED", "Nerdelandslaget_Riket")
	c.Fire("PLAYER_LOGIN")
	c.Fire("PLAYER_ENTERING_WORLD")
	return c
end

local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then fails = fails + 1 print("FAIL " .. what) end
end
local function Lines(c) return rawget(c.env.ChatFrame1, "lines") or {} end
local function has(list, pat)
	for _, l in ipairs(list or {}) do if type(l) == "string" and l:find(pat, 1, true) then return true end end
	return false
end
local function find(list, pat)
	for i, l in ipairs(list or {}) do if type(l) == "string" and l:find(pat, 1, true) then return i end end
end

-- Two guilds: Aria and Bjorn in <Nerdelandslaget>, Cato in <Nerdelandslaget II>; Dina is in no
-- nerd guild.
local A = Client("Aria Ashfall", "Nerdelandslaget", { roster = { { "Aria Ashfall", 60, "WARRIOR", true }, { "Bjorn Ironside", 58, "MAGE", true },
	{ "Offline Olaf", 40, "MAGE", false, 3, "Member", nil, 2 }, { "Gone Gunnar", 20, "WARRIOR", false, 3, "Member", nil, 90 } },
	profs = { [164] = { 250, 300 }, [186] = { 280, 300 } }, recipes = { [164] = (function()
		local r = {}
		for k = 0, 49 do r[#r + 1] = { 2660 + k * 7, k < 40 } end
		return r
	end)() } })
local B = Client("Bjorn Ironside", "Nerdelandslaget", { class = "MAGE", roster = { { "Aria Ashfall", 60, "WARRIOR", true }, { "Bjorn Ironside", 58, "MAGE", true } } })
local bigRoster = {}
local RANKS = { [0] = "Guild Master", "Officer", "Veteran", "Member" }
for i = 1, 60 do bigRoster[i] = { ("Member Number%02d"):format(i), 10 + i % 50, "MAGE", true, i % 4, RANKS[i % 4] } end
for i = 1, 30 do bigRoster[60 + i] = { ("Asleep Number%02d"):format(i), 20 + i, "MAGE", false, i % 4, RANKS[i % 4], nil, i % 25 } end
local bigRecipes = {}
for k = 1, 600 do bigRecipes[k] = { 10000 + k * k, true } end
local Cc = Client("Cato Cobalt", "Nerdelandslaget II", { class = "MAGE", roster = bigRoster, profs = { [171] = { 300, 300 } }, recipes = { [171] = bigRecipes } })
local D = Client("Dina Dust", "Some Other Guild", {})

Advance(30)   -- everyone joins, says hello, asks for professions

ok(A.R.ready and Cc.R.ready, "clients get ready")
ok(A.R.MyGuild() == "Nerdelandslaget" and Cc.R.MyGuild() == "Nerdelandslaget II", "guild rule takes both nerd guilds")
ok(D.R.MyGuild() == nil, "a guild without nerd in its name is not in the network")
ok(A.R.Relay("Nerdelandslaget") == "Aria Ashfall", "the name that sorts first relays")
ok(A.R.IAmRelay() and not B.R.IAmRelay(), "only one relay per guild")
ok(B.R.Relay("Nerdelandslaget") == "Aria Ashfall", "everyone agrees on the relay")
ok(Cc.R.IAmRelay(), "a guild's only Riket user relays it")

-- Guild chat: Bjorn writes in /g of <Nerdelandslaget>; Cato in the other guild sees it once.
A.env.C_ChatInfo.SendChatMessage("Hello from NL |cffa335ee|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r |TInterface\\Icons\\Huge:500|t", "GUILD")
Advance(5)
local cLines = Lines(Cc)
ok(#cLines == 1, "the other guild gets the line once (got " .. #cLines .. ")")
ok(has(cLines, "[Nerdelandslaget] |Hplayer:Aria Ashfall|h[" .. Cc.R.ClassName("Aria Ashfall", "WARRIOR") .. "]|h: Hello from NL"), "shown as [Guild] [Name]: text, the name in class colour: " .. tostring(cLines[1]))
ok(has(cLines, "|cffa335ee|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r"), "item links stay clickable")
ok(has(cLines, "||TInterface"), "texture codes are shown as text, not drawn")
ok(#(Lines(B)) == 0, "our own guild's line is not shown twice to our guild")
ok(#Cc.R.db.chatLog == 1 and Cc.R.db.chatLog[1].o == true, "kept in the window's log as another guild's line")

-- The other direction: Cato writes in <Nerdelandslaget II>.
Cc.env.C_ChatInfo.SendChatMessage("Hei fra NL II", "GUILD")
Advance(5)
ok(has(Lines(A), "[Nerdelandslaget II] |Hplayer:Cato Cobalt|h[" .. A.R.ClassName("Cato Cobalt", "MAGE") .. "]|h: Hei fra NL II"), "NL II's /g reaches NL (Aria), in class colour: " .. tostring(Lines(A)[1]))
ok(has(Lines(B), "Hei fra NL II"), "NL II's /g reaches NL (Bjorn)")
ok(not has(Lines(D), "Hei fra NL II"), "outsiders see nothing")

-- A repeat from a second relay (both think they relay for a moment) is dropped.
A.Fire("CHAT_MSG_ADDON", "NLRIKET1", "C;Nerdelandslaget II;Cato Cobalt;Hei fra NL II", "CHANNEL", "Someone Else-X")
ok(#Lines(A) == 1, "a repeated line within 20 seconds is dropped")
A.Fire("CHAT_MSG_ADDON", "NLRIKET1", "C;Nerdelandslaget II;Ghost Writer;boo", "CHANNEL", "Cato Cobalt-X")
ok(has(Lines(A), "[Nerdelandslaget II] |Hplayer:Ghost Writer|h[Ghost Writer]|h: boo"), "someone whose class nobody knows keeps the guild chat colour")
A.R.db.roster["Ghost Writer"] = { g = "Nerdelandslaget II", l = 20, c = "MAGE", s = now - 86400 }
A.Fire("CHAT_MSG_ADDON", "NLRIKET1", "C;Nerdelandslaget II;Ghost Writer;boo again", "CHANNEL", "Cato Cobalt-X")
ok(has(Lines(A), "[Nerdelandslaget II] |Hplayer:Ghost Writer|h[" .. A.R.ClassName("Ghost Writer", "MAGE") .. "]|h: boo again"), "the class from the members kept between sessions, when the online list hasn't come yet")
A.R.db.roster["Ghost Writer"] = nil

-- Secret lines (an encounter) are neither read nor repeated.
local before = #A.sent
A.Fire("CHAT_MSG_GUILD", "SECRET", "Aria Ashfall-X")
ok(#A.sent == before, "a secret line is not repeated")

-- The toggle turns chat-window lines off.
Cc.R.db.toChatFrame = false
A.env.C_ChatInfo.SendChatMessage("silent", "GUILD")
Advance(5)
ok(not has(Lines(Cc), "silent") and has({ Cc.R.db.chatLog[#Cc.R.db.chatLog].x }, "silent"), "toggle off: only the window shows it")
Cc.R.db.toChatFrame = true

-- Members: wait for the roster round.
Advance(130)
local nl2 = A.ns.Members.Get("Nerdelandslaget II")
ok(nl2 and nl2.online == 60 and #nl2.list == 60, "a 60-member online list crosses in parts (got " .. tostring(nl2 and #nl2.list) .. ")")
ok(nl2 and nl2.list[1].class == "MAGE", "classes travel as ids")
local nl = Cc.ns.Members.Get("Nerdelandslaget")
ok(nl and nl.online == 2 and nl.members == 4, "NL's online count and size reach NL II")
ok(B.ns.Members.Get("Nerdelandslaget II") ~= nil, "every client of the other guild gets the list")
local own = A.ns.Members.Get("Nerdelandslaget")
ok(own and own.own and own.online == 2, "our own guild comes from the roster")
for _, t in ipairs(Cc.sent) do ok(#t <= 250, "messages stay under 250 bytes") end

-- Guild ranks travel beside the list (G digits, N names).
ok(nl2.list[1].rankIndex == 1 and nl2.list[4].rankIndex == 0 and nl2.list[60].rankIndex == 0, "rank digits reach the other guild")
ok(A.ns.Members.RankName("Nerdelandslaget II", 0) == "Guild Master" and A.ns.Members.RankName("Nerdelandslaget II", 3) == "Member", "and the rank names")
ok(Cc.ns.Members.Get("Nerdelandslaget").list[1].rankIndex == 3, "both ways")
local oldOK, oldN = true, 0
for _, t in ipairs(Cc.sent) do
	local entries = t:match("^O;[^;]*;[^;]*;[^;]*;[^;]*;[^;]*;[^;]*;(.*)$")
	if entries then
		for e in entries:gmatch("[^/]+") do
			oldN = oldN + 1
			if not e:match("^([^,|]+),(%d+),(%d+)$") then oldOK = false end
		end
	end
end
ok(oldOK and oldN >= 60, "the list itself is unchanged, so a client from before 1.2 still reads every member (" .. oldN .. ")")
B.Fire("CHAT_MSG_ADDON", "NLRIKET1", "O;Nerdz;5;1;1;1;9;Old Timer,44,1", "CHANNEL", "Old Relay-X")
local nz = B.ns.Members.Get("Nerdz")
ok(nz and nz.list[1].name == "Old Timer" and nz.list[1].rankIndex == nil, "a relay from before 1.2 still works, just without ranks")
B.Fire("CHAT_MSG_ADDON", "NLRIKET1", "N;Nerdz;|TInterface\\Icons\\Huge:900|t/Officer", "CHANNEL", "Old Relay-X")
ok(not B.ns.Members.RankName("Nerdz", 0):find("|", 1, true) and B.ns.Members.RankName("Nerdz", 1) == "Officer", "rank names can't carry escape codes")
for _, t in ipairs(A.sent) do ok(#t <= 250, "rank messages stay under 250 bytes") end

-- Who is offline: our own guild from the roster, the other guilds from their relay (F).
local function OffNames(c) local t = {} for _, m in ipairs(c.ns.Members.Offline()) do t[m.name] = m end return t end
local aOff = OffNames(A)
ok(aOff["Offline Olaf"] and aOff["Offline Olaf"].guild == "Nerdelandslaget" and not aOff["Gone Gunnar"], "our own guild's offline members come from the roster, not those away over 30 days")
local sleepy = 0
for name in pairs(aOff) do if name:find("^Asleep") then sleepy = sleepy + 1 end end
ok(sleepy == 30, "the other guild's offline members cross in parts (got " .. sleepy .. ")")
local s7 = aOff["Asleep Number07"]
ok(s7 and s7.level == 27 and s7.class == "MAGE" and s7.rankIndex == 3 and s7.rank == "Member" and math.abs((now - s7.seen) - 7 * 86400) < 600,
	"with level, class, rank and when they were last online")
ok(OffNames(B)["Asleep Number07"] ~= nil, "every client of the other guild gets them")
local cOff = OffNames(Cc)
ok(cOff["Offline Olaf"] and not cOff["Gone Gunnar"] and not cOff["Aria Ashfall"] and not cOff["Member Number01"] and not cOff["Cato Cobalt"],
	"both ways, and nobody online counts as offline")
local fN, fOK = 0, true
for _, t in ipairs(Cc.sent) do
	if t:find("^F;") then fN = fN + 1 if #t > 250 then fOK = false end end
end
ok(fN >= 4 and fN <= 8 and fOK, "who is offline goes in a few messages under 250 bytes, not every minute (" .. fN .. ")")
ok(A.R.db.roster["Asleep Number07"] and A.R.db.roster["Asleep Number07"].g == "Nerdelandslaget II", "kept in the saved data, for the next login")
ok(not has(A.sent, "Gone Gunnar"), "someone away over 30 days isn't sent")
A.R.db.roster["Ancient One"] = { g = "Nerdelandslaget II", l = 10, c = "MAGE", s = now - 31 * 86400 }
ok(not OffNames(A)["Ancient One"], "someone away over 30 days isn't shown")
A.ns.Members.Prune()
ok(A.R.db.roster["Ancient One"] == nil, "and is forgotten")

-- The guild chat goes first: a line sent with a round of who is offline still waiting goes out
-- before it. And someone who left the guild is gone after the next round.
Advance(200)
table.remove(bigRoster, 90)   -- Asleep Number30 leaves
Cc.ns.Members.SendOffline()
local mark = #Cc.sent
Cc.env.C_ChatInfo.SendChatMessage("first things first", "GUILD")
Advance(15)
local iC, iF
for i = mark + 1, #Cc.sent do
	if Cc.sent[i]:find("^C;.*first things first") then iC = i end
	if Cc.sent[i]:find("^F;") then iF = iF or i end
end
ok(iC and iF and iC < iF, "a guild chat line goes before a round of who is offline")
ok(A.R.db.roster["Asleep Number30"] == nil and A.R.db.roster["Asleep Number29"] ~= nil, "someone who left the other guild is dropped at its next round")
Advance(30)
for i = 1, 10 do Cc.R.Send("Z;can wait " .. i, nil, true) end   -- a long round, from a kind nobody reads
Advance(0.3)
Cc.env.C_ChatInfo.SendChatMessage("no waiting", "GUILD")
local said = now
Advance(15)
local at
for i, t in ipairs(Cc.sent) do if t:find("^C;.*no waiting") then at = Cc.sentAt[i] end end
ok(at and at - said <= 0.31, "a long round of who is offline keeps a message back, so a guild chat line goes at once (after " .. tostring(at and at - said) .. "s)")

-- Professions.
local cr = Cc.R.db.crafters["Aria Ashfall"]
ok(cr and cr.profs[164] and cr.profs[164].rank == 250 and cr.profs[186].rank == 280, "professions with skill reach the other guild")
ok(A.R.db.crafters["Cato Cobalt"] and A.R.db.crafters["Cato Cobalt"].profs[171].rank == 300, "and the other way")
ok(not (cr and cr.links and cr.links[164]), "no link before the window was opened")
A.openProf = 164
A.Fire("TRADE_SKILL_SHOW")
Advance(5)
cr = Cc.R.db.crafters["Aria Ashfall"]
ok(cr and cr.links and cr.links[164] == "|cffffd000|Htrade:Player-1234-ABCD:2018:164|h[Blacksmithing]|h|r", "opening the window shares the link")
local rows = Cc.ns.Prof.Rows(164)
ok(#rows == 1 and rows[1].name == "Aria Ashfall" and rows[1].link, "the board lists the crafter with the link")
ok(Cc.ns.Prof.ValidLink("|cffffd000|Htrade:x|h[A]|h|r|TInterface\\Icons\\X:900|t") == false, "a link with anything after it is refused")
Cc.Fire("CHAT_MSG_ADDON", "NLRIKET1", "K;164;|TInterface\\Icons\\Huge:900|t", "CHANNEL", "Aria Ashfall-X")
ok(Cc.R.db.crafters["Aria Ashfall"].links[164]:find("Htrade", 1, true), "a bad link does not replace a good one")
local all = Cc.ns.Prof.Rows(0)
ok(#all == 3, "the board holds everyone's professions: Aria 2, Cato 1 (got " .. #all .. ")")

-- Recipes: opening a profession window reads the ones we know, and everyone gets them.
local Pc = Cc.ns.Prof
local aRec = A.R.char.recipes[164]
local aIds = A.ns.Prof.Decode(aRec)
ok(aIds and #aIds == 40, "opening a profession window reads the recipes we know, not the others (got " .. tostring(aIds and #aIds) .. ")")
local cRec = Pc.RecipesOf("Aria Ashfall", 164)
ok(cRec and cRec.n == 40 and cRec.s == aRec, "and they reach the other guild")
local s1, n1 = Pc.Encode({ 30, 10, 20, 10, 999999 })
ok(n1 == 4 and table.concat(Pc.Decode(s1), ",") == "10,20,30,999999", "recipe lists pack and unpack, sorted and once each: " .. s1)
ok(Pc.Decode("") == nil and Pc.Decode("a,,b") == nil and Pc.Decode("1,0") == nil and Pc.Decode("|Hx") == nil, "a bad recipe list is refused")
local xBefore = #Cc.sent
Cc.openProf = 171
Cc.Fire("TRADE_SKILL_SHOW")
Advance(20)
local xParts = 0
for i = xBefore + 1, #Cc.sent do
	local t = Cc.sent[i]
	if t:find("^X;171;") then xParts = xParts + 1 ok(#t <= 250, "recipe messages stay under 250 bytes") end
end
local big = A.ns.Prof.RecipesOf("Cato Cobalt", 171)
ok(big and big.n == 600 and xParts >= 5 and xParts <= 9, "600 recipes cross in a few parts (" .. xParts .. ")")
ok(Pc.AskRecipes("Aria Ashfall", 186) and not Pc.AskRecipes("Aria Ashfall", 186), "asking twice in a row asks once")
Advance(5)
ok(Pc.notRead["Aria Ashfall:186"] ~= nil, "someone who hasn't opened that window yet says so")
local bX = false
for _, t in ipairs(B.sent) do if t:find("^X;186;") then bX = true end end
ok(not bX, "only the one asked answers")

-- Discord names travel in the hello.
local tocVersion = io.open(DIR .. "/Nerdelandslaget_Riket.toc"):read("*a"):match("## Version: ([%d%.]+)")
ok(A.R.db.discords["Cato Cobalt"] == "cato_dc" and Cc.R.db.discords["Aria Ashfall"] == "aria_dc", "Discord names reach the other guild")
ok(has(A.sent, "H;Nerdelandslaget;" .. tocVersion .. ";aria_dc"), "the hello carries the Discord name")
B.Fire("CHAT_MSG_ADDON", "NLRIKET1", "H;Nerdz;1.1.0", "CHANNEL", "Old Timer-X")
ok(B.R.peers["Old Timer"] and B.R.peers["Old Timer"].version == "1.1.0" and B.R.db.discords["Old Timer"] == nil, "a hello from before 1.3 still counts")
B.Fire("CHAT_MSG_ADDON", "NLRIKET1", "H;Nerdz;1.3.0;|TInterface\\X:900|t", "CHANNEL", "Bad Actor-X")
ok(not (B.R.db.discords["Bad Actor"] or ""):find("|", 1, true), "a Discord name can't carry escape codes")

---------------------------------------------------------------------------
-- Riket in the guild window (J)
---------------------------------------------------------------------------

Cc.ns.UI.Open(1)
local host = Cc.env.CommunitiesFrame
local panel = Cc.env.NLRiketFrame
local tM, tP, tD = Cc.env.NLRiketTabMembers, Cc.env.NLRiketTabProfessions, Cc.env.NLRiketTabDiscord
ok(host and host.shown, "/riket opens the guild window, loading it the first time")
ok(panel and panel.inJ and panel.parent == host and panel.shown, "Riket's pages sit inside the guild window")
ok(tM and tP and tD and tM.parent == host and tM.template == "CommunitiesFrameTabTemplate", "three tabs of its own, drawn like the window's")
ok(tM.shown and tP.shown and tD.shown, "all three show")
local p1 = tM.points and tM.points[1]
ok(p1 and p1[1] == "TOP" and p1[2] == host.GuildBenefitsTab and p1[3] == "BOTTOM" and p1[5] == -17,
	"under the window's lowest tab (GuildBenefitsTab, though GuildInfoTab comes last in its code), with the window's gap")
ok(tP.points[1][2] == tM and tD.points[1][2] == tP, "one under the other")
ok(tM.checked and not tP.checked and host.ChatTab.checked == false, "Members marked, the window's own tab not")
ok(not Cc.env.NLRiketFrameTab1, "no window of its own any more")
ok(panel.credit.text:find("Made by Neophyte", 1, true) and panel.credit.text:find("v" .. tocVersion, 1, true), "the credit with the version: " .. tostring(panel.credit.text))
ok(panel.status.text and panel.status.text:find("Nerdelandslaget II", 1, true) and panel.status.text:find("60 of 89 online", 1, true), "the status strip shows who is online: " .. tostring(panel.status.text))

-- Members.
local mp = Cc.ns.UI.pages[1]
ok(mp.list.native and mp.list.box and mp.list.box.template == "WowScrollBoxList", "members sit in Blizzard's scroll box")
ok(#mp.list.box.dp.items == 62, "every online member is listed: 60 + 2 (got " .. #mp.list.box.dp.items .. ")")
local row1 = mp.list.box.rows[1]
ok(row1.name.text:find("Member Number01", 1, true), "own guild first, sorted by name: " .. tostring(row1.name.text))
ok(row1.rank.text == "Officer" and mp.list.box.rows[62].rank.text == "Member", "the Rank column, own guild and the other")
ok(#mp.headers == 6 and mp.headers[4].label.text == "Rank" and mp.headers[5].label.text == "Discord", "six columns, Rank and Discord among them")
local aria
for _, r in ipairs(mp.list.box.rows) do if r.item and r.item.name == "Aria Ashfall" then aria = r end end
ok(aria and aria.discord.text == "aria_dc", "the Discord column")
local function Sorted(items, key, desc)
	for i = 2, #items do
		local a, b = items[i - 1][key], items[i][key]
		if a and b and ((desc and a < b) or (not desc and a > b)) then return false end
	end
	return true
end
mp.headers[2].scripts.OnClick(mp.headers[2])
ok(Cc.R.db.memberSort.key == "level" and Cc.R.db.memberSort.desc == true and mp.list.items[1].level == 60 and Sorted(mp.list.items, "level", true), "Level: the first click sorts highest first")
ok(mp.headers[2].arrow.shown == true and mp.headers[1].arrow.shown == false, "the arrow sits on Level")
mp.headers[2].scripts.OnClick(mp.headers[2])
ok(Cc.R.db.memberSort.desc == false and Sorted(mp.list.items, "level", false) and mp.list.items[1].level == 10, "the second click turns it round")
mp.headers[4].scripts.OnClick(mp.headers[4])
ok(mp.list.items[1].rankIndex == 0 and Sorted(mp.list.items, "rankIndex", false), "Rank: guild master first")
Cc.R.db.memberSort.key, Cc.R.db.memberSort.desc = "guild", false
mp:Refresh()
local last = mp.list.box.rows[62]
last.scripts.OnClick(last, "RightButton")
local menu = Cc.menus[#Cc.menus]
ok(menu.items[1].title == "Bjorn Ironside" and menu.items[2].text == "Whisper" and menu.items[3].text == "Invite to group", "right-click opens whisper and invite")

-- Offline members, on request.
mp.offline.checked = true
mp.offline.scripts.OnClick(mp.offline)
ok(Cc.R.db.memberOffline and #mp.list.items == 62 + 29 + 1, "\"Show offline players\" adds who is offline: 29 of ours, 1 of theirs (got " .. #mp.list.items .. ")")
local items = mp.list.items
ok(not items[60].offline and items[61].offline and items[61].name == "Asleep Number01" and items[89].offline and items[90].name == "Aria Ashfall"
	and items[92].name == "Offline Olaf", "online first in each guild, then who is offline")
local olaf
for _, r in ipairs(mp.list.box.rows) do if r.item and r.item.name == "Offline Olaf" then olaf = r end end
ok(olaf and olaf.alpha == 0.55 and olaf.zone.text == "Offline 2 days" and olaf.level.text == 40 and olaf.rank.text == "Member",
	"greyed, with how long since: " .. tostring(olaf and olaf.zone.text))
local menus = #Cc.menus
olaf.scripts.OnClick(olaf, "LeftButton")
olaf.scripts.OnClick(olaf, "RightButton")
ok(has(Cc.prints, "Offline Olaf is offline (last online 2 days ago).") and #Cc.menus == menus, "clicking someone offline says so instead of whispering")
olaf.scripts.OnEnter(olaf)
ok(has(Cc.env.GameTooltip.tlines, "Offline, last online 2 days ago"), "and the tooltip says it")
mp.offline.checked = false
mp.offline.scripts.OnClick(mp.offline)
ok(not Cc.R.db.memberOffline and #mp.list.items == 62, "unticking hides them again")

-- Professions.
tP.scripts.OnClick(tP)
local pp = Cc.ns.UI.pages[2]
ok(pp.shown and not mp.shown and tP.checked and not tM.checked and Cc.R.db.tab == 2, "the Professions tab shows its page")
local names = {}
for _, it in ipairs(pp.filter.root.items) do names[#names + 1] = it.text end
ok(names[1] == "All professions" and has(names, "Alchemy") and has(names, "Blacksmithing"), "the dropdown offers every known profession")
ok(#pp.list.box.dp.items == 3, "all three professions listed")
for _, it in ipairs(pp.filter.root.items) do if it.text == "Alchemy" then it.set(it.data) end end
ok(Cc.R.db.profFilter == 171 and #pp.list.box.dp.items == 1, "choosing Alchemy filters the list")
for _, it in ipairs(pp.filter.root.items) do if it.text == "All professions" then it.set(it.data) end end
local function RowOf(list, fn)
	for _, r in ipairs(list.box.rows) do if r.item and fn(r.item) then return r end end
end
local rv = pp.recipes

-- Clicking a profession shows its recipes in Riket, asking the player for them when needed.
Cc.R.db.recipes["Aria Ashfall"] = nil
Advance(25)   -- (past the time Aria waits before sending the same recipes again)
local bs = RowOf(pp.list, function(it) return it.id == 164 end)
bs.link.scripts.OnClick(bs.link, "LeftButton")
ok(rv.shown and not pp.listView.shown and rv.list.empty.text:find("Asking Aria", 1, true), "clicking a profession opens its recipes, asking the player: " .. tostring(rv.list.empty.text))
Advance(3)
ok(has(Cc.sent, "W;Aria Ashfall;164"), "the question goes out")
local ritems = rv.list.items
ok(#ritems == 40 and ritems[1].name == "Bronze Thing 01" and ritems[40].name == "Copper Thing 38", "the answer fills the list, A to Z (" .. #ritems .. ")")
ok(rv.title.text:find("Blacksmithing 250/300", 1, true) and rv.title.text:find("40 recipes", 1, true), "the title: who, profession, skill, how many: " .. tostring(rv.title.text))
local r1 = rv.list.box.rows[1]
ok(r1.name.text == "Bronze Thing 01", "a row shows the recipe's name")
rv.search.text = "copper"
rv.search.scripts.OnTextChanged(rv.search)
ok(#rv.list.items == 20 and rv.search.hint.shown == false, "the search box filters by name")
rv.search.text = "nothing like this"
rv.search.scripts.OnTextChanged(rv.search)
ok(#rv.list.items == 0 and rv.list.empty.text:find("No recipes match", 1, true), "and says when nothing matches")
rv.search.text = ""
rv.search.scripts.OnTextChanged(rv.search)
r1 = rv.list.box.rows[1]
r1.scripts.OnEnter(r1)
ok(Cc.env.GameTooltip.tlines[1] == "spell " .. r1.item.id and has(Cc.env.GameTooltip.tlines, "Click to ask Aria to make it"), "its tooltip is the recipe's, with what a click does")
Cc.insertedAll = {}
r1.scripts.OnClick(r1, "LeftButton")
ok(Cc.tellTo == "Aria Ashfall" and Cc.inserted == "Can you make |cff71d5ff|Hspell:" .. r1.item.id .. ":0|h[Bronze Thing 01]|h|r?", "a click whispers Aria: can you make it? " .. tostring(Cc.inserted))
Cc.tellTo, Cc.shift = nil, true
r1.scripts.OnClick(r1, "LeftButton")
Cc.shift = false
ok(Cc.tellTo == nil and Cc.inserted == "|cff71d5ff|Hspell:" .. r1.item.id .. ":0|h[Bronze Thing 01]|h|r", "shift-click puts the recipe in chat")

-- Riket never opens the game's profession window: one opened from an addon stays blank.
ok(rv.game == nil, "no \"Open in game\" button any more")
rv.back.scripts.OnClick(rv.back)
ok(not rv.shown and pp.listView.shown and #pp.list.items == 3, "Back returns to everyone's professions")

-- Our own recipes: no asking, no whispering.
local mineRow = RowOf(pp.list, function(it) return it.me end)
mineRow.scripts.OnClick(mineRow, "LeftButton")
ok(rv.shown and #rv.list.items == 600 and not has(Cc.sent, "W;Cato Cobalt"), "our own profession shows our recipes, with no question")
Cc.tellTo = nil
rv.list.box.rows[1].scripts.OnClick(rv.list.box.rows[1], "LeftButton")
ok(Cc.tellTo == nil, "and a click on our own recipe whispers nobody")
rv.back.scripts.OnClick(rv.back)

-- Someone online with an older Riket: no answer, and it says so.
Cc.R.db.crafters["Old Smith"] = { guild = "Nerdelandslaget", class = "WARRIOR", level = 60, t = now, profs = { [164] = { rank = 200, max = 300 } }, links = {} }
Cc.R.peers["Old Smith"] = { guild = "Nerdelandslaget", t = now, version = "1.4.2" }
pp:Refresh()
local old = RowOf(pp.list, function(it) return it.name == "Old Smith" end)
old.scripts.OnClick(old, "LeftButton")
ok(rv.list.empty.text:find("Asking Old", 1, true), "asking someone with an older Riket")
Advance(9)
ok(rv.list.empty.text:find("No answer from Old", 1, true) and rv.list.empty.text:find("1.4.4", 1, true), "no answer: it says they may need to update: " .. tostring(rv.list.empty.text))
rv.back.scripts.OnClick(rv.back)

-- Offline players are hidden; their recipes show if Riket has heard them, with no question.
Cc.R.db.crafters["Emo Lock"] = { guild = "Nerdelandslaget", class = "WARLOCK", level = 40, t = now - 3600,
	profs = { [197] = { rank = 100, max = 150 } }, links = { [197] = "|cffffd000|Htrade:Player-1-EMO:3908:197|h[Tailoring]|h|r" } }
Cc.R.db.crafters["Quiet Smith"] = { guild = "Nerdelandslaget", class = "WARRIOR", level = 30, t = now - 3600, profs = { [164] = { rank = 50, max = 75 } }, links = {} }
Cc.R.db.recipes["Emo Lock"] = { [197] = { s = (Pc.Encode({ 2660, 2667, 2674 })), n = 3, t = now - 2 * 86400 } }
pp:Refresh()
local names2 = {}
for _, it in ipairs(pp.list.items) do names2[#names2 + 1] = it.name end
ok(not has(names2, "Emo Lock") and not has(names2, "Quiet Smith"), "an offline player's professions are hidden")
pp.offline.checked = true
pp.offline.scripts.OnClick(pp.offline)
local emo = RowOf(pp.list, function(it) return it.name == "Emo Lock" end)
ok(Cc.R.db.profOffline and emo and emo.item.online == false and emo.alpha == 0.55 and emo.name.text:find("(offline)", 1, true), "\"Show offline players\" shows them, greyed")
local sentBefore = #Cc.sent
emo.scripts.OnClick(emo, "LeftButton")
local askedEmo = false
for i = sentBefore + 1, #Cc.sent do if Cc.sent[i]:find("^W;Emo Lock") then askedEmo = true end end
ok(#rv.list.items == 3 and not askedEmo and rv.title.text:find("heard 2d ago", 1, true), "an offline player's recipes, as last heard, without asking: " .. tostring(rv.title.text))
rv.back.scripts.OnClick(rv.back)
local quiet = RowOf(pp.list, function(it) return it.name == "Quiet Smith" end)
quiet.scripts.OnClick(quiet, "LeftButton")
ok(#rv.list.items == 0 and rv.list.empty.text:find("Quiet is offline, and Riket hasn't seen", 1, true), "someone offline whose recipes nobody has heard: it says so")
rv.back.scripts.OnClick(rv.back)
emo = RowOf(pp.list, function(it) return it.name == "Emo Lock" end)
Cc.shift = true
emo.link.scripts.OnClick(emo.link, "LeftButton")
Cc.shift = false
ok(Cc.inserted and Cc.inserted:find("Tailoring", 1, true) and not rv.shown, "shift-click on a profession link still puts it in chat")
emo.scripts.OnClick(emo, "RightButton")
local pm = Cc.menus[#Cc.menus]
ok(pm.items[1].title == "Emo Lock" and pm.items[2].text == "Show recipes" and pm.items[3].text == "Whisper" and #pm.items == 3, "right-click: recipes and whisper, not the game's window")
pp.offline.checked = false
pp.offline.scripts.OnClick(pp.offline)
local emoShown = false
for _, it in ipairs(pp.list.items) do if it.name == "Emo Lock" then emoShown = true end end
ok(not Cc.R.db.profOffline and not emoShown, "and unticking hides them again")
Cc.R.db.crafters["Old Smith"], Cc.R.peers["Old Smith"] = nil, nil
pp:Refresh()

-- Discord, for a player whose rank can't edit notes.
tD.scripts.OnClick(tD)
local dpc = Cc.ns.UI.pages[3]
ok(dpc.shown and dpc.input.text == "cato_dc" and dpc.state.text:find("Riket is on", 1, true), "the Discord tab shows the name and that Riket is on")
ok(dpc.noteBtn.enabled == false and dpc.noteInfo.text:find("can't edit", 1, true), "where the rank can't edit notes, it says so")

-- The window's own tabs and ours.
host.RosterTab.scripts.OnClick(host.RosterTab)
ok(not panel.shown and not tD.checked, "the window's own tab takes Riket away")
host.ChatTab.checked = true
tP.scripts.OnClick(tP)
ok(panel.shown and tP.checked and host.ChatTab.checked == false, "a Riket tab brings its page back")
tP.scripts.OnClick(tP)
ok(not panel.shown and not tP.checked and host.ChatTab.checked == true, "and clicking it again gives the window back as it was")

-- The guild chat, merged.
local mf = host.Chat.MessageFrame
local CO = Cc.ns.UI.CO
local merged = rawget(CO.smf, "lines") or {}
ok(CO.box.shown and mf.alpha == 0 and CO.box.parent == host.Chat, "the merged chat takes the guild chat's place")
local iNL, iOwn, iSilent = find(merged, "Hello from NL"), find(merged, "Hei fra NL II"), find(merged, "silent")
ok(iNL and iOwn and iSilent and iNL < iOwn and iOwn < iSilent, "both guilds' lines, in time order")
ok(has(merged, "|cffffd100[Nerdelandslaget]|r |Hplayer:Aria Ashfall|h["), "the other guild's lines carry its name")
ok(merged[iOwn] and merged[iOwn]:find("^|Hplayer:Cato Cobalt|h%[|c") ~= nil, "our own lines look like the guild chat's, name in class colour: " .. tostring(merged[iOwn]))
A.env.C_ChatInfo.SendChatMessage("live from NL", "GUILD")
Advance(5)
merged = rawget(CO.smf, "lines")
ok(merged[#merged]:find("live from NL", 1, true), "a new line from the other guild comes in at the bottom")
local n = #merged
Cc.env.C_ChatInfo.SendChatMessage("live from NL II", "GUILD")
Advance(1)
merged = rawget(CO.smf, "lines")
ok(#merged == n + 1 and merged[#merged]:find("live from NL II", 1, true), "our own new line comes once, from the game's message")
host:SelectStream(GUILD_CLUB, OFFICER_STREAM)
ok(not CO.box.shown and mf.alpha == 1, "officer chat stays the window's own")
host:SelectStream(GUILD_CLUB, GUILD_STREAM)
ok(CO.box.shown and mf.alpha == 0 and has(rawget(CO.smf, "lines"), "live from NL II"), "back on guild chat it's merged again")
host:SelectClub(OTHER_CLUB)
ok(not tM.shown and not CO.box.shown and mf.alpha == 1, "another community: no Riket tabs, and its own chat")
host:SelectClub(GUILD_CLUB)
ok(tM.shown and CO.box.shown, "back on the guild: tabs and merged chat return")
-- Links in the merged chat: safe ones open, a profession's goes to Riket, the rest are left
-- to the normal chat window (opening the game's windows from an addon spoils them).
local click = CO.smf.scripts.OnHyperlinkClick
Cc.opened = nil
click(CO.smf, "item:19019::::::::60:::::", "|cffa335ee|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r", "LeftButton")
ok(Cc.opened == "item:19019::::::::60:::::", "an item link opens as usual")
Cc.opened = nil
click(CO.smf, "achievement:6:Player-1:0:0:0:0:0:0:0:0", "|cffffff00|Hachievement:6:Player-1:0:0:0:0:0:0:0:0|h[Level 10]|h|r", "LeftButton")
ok(Cc.opened == nil and has(Cc.prints, "click that link in your normal chat window"), "an achievement link isn't opened from Riket's chat, and it says where to click it")
Cc.R.db.profFilter = 0
click(CO.smf, "trade:Player-1-ABC:2259:171", "|cffffd000|Htrade:Player-1-ABC:2259:171|h[Alchemy]|h|r", "LeftButton")
ok(Cc.opened == nil and Cc.R.db.profFilter == 171 and Cc.ns.UI.pages[2].shown and has(Cc.prints, "profession links don't open"), "a profession link opens Riket's professions for it, never the game's window")
Cc.R.db.profFilter = 0
Cc.ns.UI.Open(1)
host.ChatTab.scripts.OnClick(host.ChatTab)
host:SelectStream(GUILD_CLUB, GUILD_STREAM)
host:SetDisplayMode("MINIMIZED")
ok(not tM.shown, "the small chat-only mode has no Riket tabs")
host:SetDisplayMode("CHAT")
ok(tM.shown, "full size brings them back")

-- Closing and toggling.
Cc.ns.UI.Open(2)
host:Hide()
ok(not panel.shown and not tP.checked and not CO.box.shown and mf.alpha == 1, "closing the guild window closes Riket and gives back its chat")
Cc.ns.UI.Open(1)
ok(host.shown and panel.shown and tM.checked, "/riket members opens it again")
Cc.ns.UI.Toggle()
ok(not host.shown and not panel.shown, "toggling closes the guild window")

-- Minimap button and the addon list entry.
local MB = Cc.env.NLRiketMapButton
MB.scripts.OnEnter(MB)
ok(has(Cc.env.GameTooltip.tlines, "Made by Neophyte"), "the minimap tooltip carries the credit")
MB.scripts.OnClick(MB, "RightButton")
local mm = Cc.menus[#Cc.menus]
ok(mm.items[1].title == "Nerdelandslaget: Riket" and mm.items[2].text == "Members" and mm.items[4].text == "Discord", "the minimap menu reaches the three pages")
MB.scripts.OnClick(MB, "LeftButton")
ok(host.shown and panel.shown, "the minimap button opens Riket in the guild window")
ok(type(Cc.env.NLRiket_OnAddonCompartmentClick) == "function" and type(Cc.env.NLRiket_OnAddonCompartmentEnter) == "function", "the addon list entry has its functions")

-- /riket check, and errors said out loud.
ok(not has(Cc.prints, "in the guild window:"), "no errors in the guild window: " .. tostring(Cc.prints[find(Cc.prints, "in the guild window:") or 0]))
Cc.env.SlashCmdList.NLRIKET("check")
ok(has(Cc.prints, "its tabs: ChatTab, RosterTab, GuildBenefitsTab, GuildInfoTab") and has(Cc.prints, "Riket's tabs under GuildBenefitsTab, shown true"), "/riket check tells what it sees")
local r = Cc.ns.UI.Safe("test something", function() error("boom") end)
ok(r == nil and has(Cc.prints, "couldn't test something in the guild window") and Cc.ns.UI.J.lastError:find("boom", 1, true), "an error in the guild window is said in chat, not swallowed")
local okSlash = pcall(function() Cc.env.SlashCmdList.NLRIKET("status") Cc.env.SlashCmdList.NLRIKET("help") end)
ok(okSlash, "/riket status and help work")

-- Outside the nerd guilds: no tabs, nothing to open.
D.ns.UI.Open(1)
ok(has(D.prints, "Riket is for the guilds") and not D.env.NLRiketFrame, "outside the network /riket just says so")
D.env.ToggleGuildFrame()
ok(D.env.NLRiketTabMembers and D.env.NLRiketTabMembers.shown == false, "and the guild window has no Riket tabs")

---------------------------------------------------------------------------
-- A newcomer: nothing until the Discord name is set, in the Discord tab
---------------------------------------------------------------------------

local N = Client("Nora Nyhet", "Nerdelandslaget", { discord = false, canEdit = true })
Advance(30)
ok(not N.R.ready and N.R.waiting and #N.sent == 0, "without a Discord name Riket stays off and sends nothing")
ok(N.popups[1] and N.popups[1].which == "NLRIKET_DISCORD", "the login points to the Discord tab")
N.env.StaticPopupDialogs.NLRIKET_DISCORD.OnAccept()
local Nhost, Npanel = N.env.CommunitiesFrame, N.env.NLRiketFrame
ok(Nhost and Nhost.shown and Npanel and Npanel.shown and N.R.db.tab == 3 and N.env.NLRiketTabDiscord.checked, "its button opens the guild window on the Discord tab")
N.env.NLRiketTabMembers.scripts.OnClick(N.env.NLRiketTabMembers)
ok(N.R.db.tab == 3 and N.env.NLRiketTabDiscord.checked and not N.env.NLRiketTabMembers.checked, "the other tabs wait for the Discord name")
local dp = N.ns.UI.pages[3]
ok(dp.state.text:find("Riket is off", 1, true) and not N.ns.UI.CO.box.shown, "the Discord tab says Riket is off, and the chat isn't merged yet")
dp.input.text = "x"
dp.save.scripts.OnClick(dp.save)
ok(not N.R.Discord() and dp.state.text:find("two letters", 1, true), "one letter is refused")
dp.input.text = "  nora|nyhet  "
dp.input.scripts.OnEnterPressed(dp.input)
ok(N.R.Discord() == "noranyhet", "Enter saves it, trimmed and cleaned: " .. tostring(N.R.Discord()))
Advance(5)
ok(N.R.ready and has(N.sent, ";noranyhet"), "setting it starts Riket")
ok(N.ns.UI.CO.box.shown, "and merges the guild chat")
dp:Refresh()
ok(dp.note.text:find("(empty)", 1, true) and dp.noteBtn.enabled == true, "her rank may edit notes: the button is on")
dp.noteBtn.scripts.OnClick(dp.noteBtn)
ok(N.noteSet and N.noteSet.text == "noranyhet" and N.noteSet.public == true and N.noteSet.guid == "Player-1-Nora Nyhet", "the button writes her public guild note")
Advance(3)
ok(dp.note.text:find("noranyhet", 1, true) and dp.noteBtn.enabled == false and dp.noteInfo.text:find("holds", 1, true), "and the tab then shows it there")
dp.show.checked = false
dp.show.scripts.OnClick(dp.show)
ok(N.R.db.toChatFrame == false, "the chat window setting lives in the Discord tab")
N.env.NLRiketTabMembers.scripts.OnClick(N.env.NLRiketTabMembers)
ok(N.R.db.tab == 1 and N.env.NLRiketTabMembers.checked, "with the name set, the other tabs open")
ok(not has(N.prints, "in the guild window:"), "no errors for the newcomer")

---------------------------------------------------------------------------
-- Forever's names: the game gives us only "Aria", everyone else sees "Aria Ashfall"
---------------------------------------------------------------------------

ok(A.env.UnitName("player") == "Aria" and A.R.Me() == "Aria Ashfall" and Cc.R.Me() == "Cato Cobalt", "our whole name: by our GUID in the roster (Aria), or by our own hello coming back (Cato, not in his test roster)")
ok(A.R.db.crafters["Aria"] == nil and A.R.db.crafters["Aria Ashfall"] ~= nil, "our professions are kept once, under our whole name")
local mine = 0
for _, row in ipairs(A.ns.Prof.Rows(0)) do if row.name:find("^Aria") then mine = mine + 1 end end
ok(mine == 2, "and listed once each, as ours (got " .. mine .. ")")
local G = Client("Gro Gullsmed", "Nerdelandslaget", { noGuid = true, roster = { { "Gro Gullsmed", 30, "WARRIOR", true }, { "Groa Stein", 20, "MAGE", true } } })
Advance(15)
ok(G.R.Me() == "Gro Gullsmed", "without GUIDs: the only roster name that starts with ours (\"Groa Stein\" doesn't)")
local Hh = Client("Hans Hval", "Nerdelandslaget", { noGuid = true, roster = { { "Hans Hval", 30, "WARRIOR", true }, { "Hans Hogg", 20, "MAGE", true } } })
Advance(15)
ok(Hh.R.Me() == "Hans Hval", "two roster names start with ours: our own hello coming back tells which (got " .. tostring(Hh.R.Me()) .. ")")
ok(Hh.R.db.discords["Hans"] == nil and Hh.R.db.discords["Hans Hval"] == "hans_dc", "and nothing stays under the short name")

---------------------------------------------------------------------------
-- Guild chat text the game only hands addons as a protected code
---------------------------------------------------------------------------

local K = Client("Kari Kode", "Nerdelandslaget II", { protectedChat = true, class = "MAGE" })
Advance(15)
K.ns.UI.Open(3)
host = K.env.CommunitiesFrame
host.RosterTab.scripts.OnClick(host.RosterTab)   -- (back to the window's own view, its guild chat)
local sentBefore = #K.sent
K.env.C_ChatInfo.SendChatMessage("secret plans", "GUILD")
Advance(3)
local kLines = rawget(K.ns.UI.CO.smf, "lines") or {}
ok(K.ns.UI.CO.box.shown and has(kLines, "|Kw") and not has(kLines, "||Kw"), "the game's protected text goes to the merged chat as the game gave it, for it to draw")
local relayed = false
for i = sentBefore + 1, #K.sent do if K.sent[i]:find("^C;") then relayed = true end end
ok(not relayed, "it is not passed to the other guilds, where it would mean nothing")
ok(has(K.prints, "hides guild chat text from addons"), "and Riket says so once")
ok(K.env.NLRiketFrame.strata == "HIGH", "Riket's panel lies a layer above the guild window, so its chat box doesn't show through")
ok(K.ns.UI.CO.ourBar and K.ns.UI.CO.ourBar.template == "MinimalScrollBar" and K.ns.UI.CO.ourBar.points[1][1] == "TOP", "the merged chat's scroll bar is the thin one, centred in the window's bar's place")

-- A game that doesn't say when someone was last online: they show as just "Offline".
local L = Client("Lise Lang", "Nerdelandslaget", { roster = { { "Lise Lang", 60, "WARRIOR", true }, { "Quiet Quinn", 30, "MAGE", false } } })
L.env.GetGuildRosterLastOnline = nil
Advance(15)
L.R.db.memberOffline = true
L.ns.UI.Open(1)
local qrow
for _, r in ipairs(L.ns.UI.pages[1].list.box.rows) do if r.item and r.item.name == "Quiet Quinn" then qrow = r end end
ok(qrow and qrow.item.unknown and qrow.zone.text == "Offline", "without the game's last-online time, someone offline shows as just \"Offline\"")
qrow.scripts.OnClick(qrow, "LeftButton")
ok(has(L.prints, "Quiet Quinn is offline.") and not has(L.prints, "Quiet Quinn is offline (last"), "and clicking says only that")

---------------------------------------------------------------------------
-- Promoting: a captain or higher promotes ferskinger online with a guild note to spiller
---------------------------------------------------------------------------

local PROMO_RANKS = { [0] = "Sjef", "Kaptein", "Spiller", "Fersking" }
local KP = Client("Kaia Kaptein", "Nerdeskolen", { rankIndex = 1, ranks = PROMO_RANKS, canPromote = true, roster = {
	{ "Kaia Kaptein", 60, "WARRIOR", true, 1, "Kaptein", "kaia_dc" },
	{ "Ny Spiller", 12, "MAGE", true, 3, "Fersking", "nyspiller" },
	{ "Annen Ny", 14, "MAGE", true, 3, "Fersking", "annen_dc" },
	{ "Uten Note", 10, "MAGE", true, 3, "Fersking", "   " },
	{ "Bare Proff", 15, "MAGE", true, 3, "Fersking", "Ench/Tailor 300" },
	{ "Proff Navn", 16, "MAGE", true, 3, "Fersking", "BS/LW - Ola" },
	{ "Borte Bort", 20, "MAGE", false, 3, "Fersking", "borte" },
	{ "Gammel Spiller", 60, "MAGE", true, 2, "Spiller", "gammel" } } })
Advance(30)
local PRm = KP.ns.Promote
local plan = PRm.Plan()
ok(plan.allowed and plan.steps == 1 and table.concat(plan.list, ",") == "Annen Ny,Ny Spiller,Proff Navn",
	"ferskinger online with a name in the note, and only them (not \"Ench/Tailor 300\"): " .. table.concat(plan.list, ","))
local NH = KP.ns.Promote.NoteHasName
local noName = { "", "   ", "Ench", "BS", "bs", "LW 300", "Alch/Herb", "alchherb", "AlchHerb", "Leatherworking + Skinning", "Ench & Tailor",
	"First Aid 300", "Gruvedrift og smed", "Lær/flå", "LÆR", "JCs", "Prof: BS/Mining", "discord", "Engi (gnomish)", "Herbalism 300/300",
	"Tailor, Enchanter", "BSLW", "max cooking + fishing", "Skinning/LW 375", "alch transmute master", "Mining - 300 - Smelting" }
local bad = {}
for _, n in ipairs(noName) do if NH(n) then bad[#bad + 1] = n end end
ok(#bad == 0, "professions alone are no name: " .. table.concat(bad, " | "))
local withName = { "Kalle", "kalle_99", "Ench - Kalle", "Alch (Kristian)", "nyspiller", "annen_dc", "BS/Mining - Ola", "Lærke", "Øystein",
	"Minna", "Herbert", "Engelbert", "Tina", "Faen", "Desmond", "Chefen", "Lars", "LW - Mats" }
bad = {}
for _, n in ipairs(withName) do if not NH(n) then bad[#bad + 1] = n end end
ok(#bad == 0, "a name, with or without professions, counts: " .. table.concat(bad, " | "))
KP.ns.UI.Open(1)
local pbtn = KP.env.NLRiketPromoteButton
ok(pbtn and pbtn.shown and pbtn.text == "Promote to Spiller (3)" and pbtn.enabled ~= false and pbtn.template:find("SecureActionButtonTemplate", 1, true),
	"a captain sees a secure button on the Members page: " .. tostring(pbtn and pbtn.text))
ok(pbtn.parent ~= KP.env.NLRiketFrame and pbtn.strata == "DIALOG", "it belongs to no frame of Riket's, so nothing of Riket's gets locked in combat")
pbtn.scripts.PreClick(pbtn, "LeftButton", false)
ok(pbtn.attrs.type == "macro" and pbtn.attrs.macrotext == "/gpromote Annen Ny\n/gpromote Ny Spiller\n/gpromote Proff Navn", "the click runs /gpromote for each: " .. tostring(pbtn.attrs.macrotext))
ok(has(KP.prints, "promoting Annen Ny, Ny Spiller, Proff Navn to Spiller."), "and says who")
pbtn.scripts.OnEnter(pbtn)
ok(has(KP.env.GameTooltip.tlines, "Annen Ny, Ny Spiller, Proff Navn"), "its tooltip names them")
KP.env.C_GuildInfo.IsGuildRankAssignmentAllowed = function(guid, order) return not (guid == "Player-1-Ny Spiller" and order == 3) end
ok(table.concat(PRm.Plan().list, ",") == "Annen Ny,Proff Navn", "someone the game says can't get that rank is left out")
KP.env.C_GuildInfo.IsGuildRankAssignmentAllowed = nil
local m2 = PRm.Macro({ list = { "Aa Bb" }, steps = 2 })
ok(m2 == "/gpromote Aa Bb\n/gpromote Aa Bb", "a rank between them: one /gpromote for each step")
local many = {}
for i = 1, 30 do many[i] = ("Fersk Nummer%02d"):format(i) end
local m3, done3 = PRm.Macro({ list = many, steps = 1 })
ok(#m3 <= 255 and #done3 > 5 and #done3 < 30, "a macro holds 255 characters: the rest wait for the next click (" .. #done3 .. " now)")
KP.rankIndex = 2
PRm.Update()
ok(not pbtn.shown and not PRm.Plan().allowed, "a spiller doesn't get the button")
KP.rankIndex = nil
PRm.Update()
ok(pbtn.shown, "a captain again does")
KP.combat = true
KP.Fire("PLAYER_REGEN_DISABLED")
pbtn.attrs.macrotext = "untouched"
pbtn.scripts.PreClick(pbtn, "LeftButton", false)
PRm.Update()
ok(not pbtn.shown and pbtn.attrs.macrotext == "untouched", "in combat it hides and nothing on it changes")
KP.combat = false
KP.Fire("PLAYER_REGEN_ENABLED")
ok(pbtn.shown, "and comes back after")
KP.env.NLRiketTabProfessions.scripts.OnClick(KP.env.NLRiketTabProfessions)
ok(not pbtn.shown, "only on the Members page")
KP.ns.UI.Open(1)
KP.env.CommunitiesFrame:Hide()
ok(not pbtn.shown, "and not once the guild window closes")
ok(Cc.env.NLRiketPromoteButton == nil, "a guild without those ranks never gets the button")

-- Riket's admin (Sexy Neophyte) sees the button everywhere; without the rank a click only says so.
local SN = Client("Sexy Neophyte", "Nerdeskolen", { rankIndex = 2, ranks = PROMO_RANKS, canPromote = true, roster = {
	{ "Sexy Neophyte", 60, "WARRIOR", true, 2, "Spiller", "neophyte" },
	{ "Ny Spiller", 12, "MAGE", true, 3, "Fersking", "nyspiller" } } })
Advance(30)
ok(SN.R.Me() == "Sexy Neophyte" and SN.ns.Promote.IsAdmin() and not KP.ns.Promote.IsAdmin(), "Sexy Neophyte is the admin, nobody else")
SN.ns.UI.Open(1)
local sbtn = SN.env.NLRiketPromoteButton
ok(sbtn and sbtn.shown and sbtn.text == "Promote to Spiller" and sbtn.enabled ~= false, "the admin sees the button though he is only a spiller")
sbtn.scripts.OnEnter(sbtn)
ok(has(SN.env.GameTooltip.tlines, "You don't have the rank for this in Nerdeskolen: only Kaptein and higher can promote."), "its tooltip says why it won't work")
sbtn.scripts.PreClick(sbtn, "LeftButton", false)
ok(sbtn.attrs.macrotext == "" and has(SN.prints, "you don't have the rank for this in Nerdeskolen: only Kaptein and higher can promote. Nothing was done."),
	"a click says he doesn't have the rank, and runs nothing: " .. tostring(SN.prints[#SN.prints]))
SN.rankIndex = 1
sbtn.scripts.PreClick(sbtn, "LeftButton", false)
SN.ns.Promote.Update()
ok(sbtn.attrs.macrotext == "/gpromote Ny Spiller" and sbtn.text == "Promote to Spiller (1)", "with the rank it promotes, like for anyone")
SN.rankIndex = nil
local SN2 = Client("Sexy Neophyte", "Nerdelandslaget II", { rankIndex = 3, roster = { { "Sexy Neophyte", 60, "WARRIOR", true, 3, "Member", "neophyte" } } })
Advance(30)
SN2.ns.UI.Open(1)
local sbtn2 = SN2.env.NLRiketPromoteButton
sbtn2.scripts.PreClick(sbtn2, "LeftButton", false)
ok(sbtn2.shown and sbtn2.attrs.macrotext == "" and has(SN2.prints, "Nerdelandslaget II has no ranks Kaptein, Spiller and Fersking, so there is nobody to promote. Nothing was done."),
	"in a guild without those ranks too: it says so and does nothing")
ok(not has(KP.prints, "in the guild window:"), "no errors: " .. tostring(KP.prints[find(KP.prints, "in the guild window:") or 0]))

-- A client without any of the templates still builds, with plain stand-ins.
local F = Client("Frida Fjell", "Nerdelandslaget II", { noTemplates = true, class = "MAGE" })
Advance(30)
local okF, errF = pcall(function() F.ns.UI.Open(1) F.ns.UI.Open(2) F.ns.UI.Open(3) F.ns.UI.Refresh() end)
ok(okF and F.env.NLRiketFrame and F.env.NLRiketFrame.shown, "without the templates it still builds: " .. tostring(errF))
ok(F.env.NLRiketTabMembers.template == nil and F.ns.UI.pages[1].list.plain and F.ns.UI.pages[2].filter.standIn, "plain tabs, list and filter button")
ok(not has(F.prints, "in the guild window:"), "and no errors: " .. tostring(F.prints[find(F.prints, "in the guild window:") or 0]))

-- Someone seen in a list from a relay before 1.4.3 (no F) is still kept, and shows as offline
-- once that list is old.
Advance(30)   -- (his hello has run out too)
local bo = OffNames(B)["Old Timer"]
ok(bo and bo.guild == "Nerdz" and bo.level == 44, "seen online once, offline later")

-- Guilds with "nørd" in the name are in the network too (1.4.6), Ø or ø.
local IsNerd = A.R.IsNerdGuild
ok(IsNerd("Nørdeklubben") and IsNerd("DE NØRDE GUTTA") and IsNerd("Nerdelandslaget") and IsNerd("nerdz"), "\"nørd\" counts, in any case, beside \"nerd\"")
ok(not IsNerd("Nordmenn") and not IsNerd("Nørrøna") and not IsNerd("Some Other Guild") and not IsNerd(nil), "other names don't")
ok(A.R.CleanGuild("Nørdeklubben") == "Nørdeklubben", "a nørd guild's name travels in messages")
local Z = Client("Zara Zink", "Nørdeklubben", { class = "MAGE" })
Advance(30)
ok(Z.R.MyGuild() == "Nørdeklubben" and Z.R.ready, "a player in a nørd guild starts Riket")
A.env.C_ChatInfo.SendChatMessage("hei nørder", "GUILD")
Advance(5)
ok(has(Lines(Z), "[Nerdelandslaget] |Hplayer:Aria Ashfall|h[" .. Z.R.ClassName("Aria Ashfall", "WARRIOR") .. "]|h: hei nørder"), "and gets the other guilds' chat")
Z.env.C_ChatInfo.SendChatMessage("hei nerder", "GUILD")
Advance(5)
ok(has(Lines(A), "[Nørdeklubben] |Hplayer:Zara Zink|h[" .. A.R.ClassName("Zara Zink", A.ns.Members.ClassOf("Zara Zink") or "?") .. "]|h: hei nerder"), "and the others get theirs")

-- Without the channel: falls back to GUILD (own guild only), no errors.
local E = Client("Eirik Edge", "Nerdelandslaget", { noChannel = true })
Advance(30)
ok(E.R.ready and E.R.ChannelID() == nil, "a client without the channel still starts")

print(("%d/%d checks passed"):format(checks - fails, checks))
os.exit(fails == 0 and 0 or 1)
