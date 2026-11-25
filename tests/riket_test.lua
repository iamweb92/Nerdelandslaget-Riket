-- Offline test for Nerdelandslaget: Riket. Simulates several WoW clients (each its own globals)
-- in different "nerd" guilds on one shared channel, with a fake clock, and checks the guild chat
-- bridge, the online lists, the professions board and that the window builds.
-- Usage: luajit riket_test.lua <addon folder>
local DIR = assert(arg[1], "addon folder")
local FILES = { "Core.lua", "Chat.lua", "Members.lua", "Professions.lua", "UI.lua" }

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
		if k == "IsShown" then return function(self) return self.shown ~= false end end
		if k == "Show" then return function(self) self.shown = true if self.scripts.OnShow then self.scripts.OnShow(self) end end end
		if k == "Hide" then return function(self) self.shown = false end end
		if k == "SetShown" then return function(self, v) self.shown = v and true or false end end
		if k == "GetText" then return function(self) return self.text or "" end end
		if k == "SetText" then return function(self, v) self.text = v end end
		if k == "AddMessage" then return function(self, line) local l = rawget(self, "lines") or {} rawset(self, "lines", l) table.insert(l, line) end end
		if k == "GetPoint" then return function() return "CENTER", nil, "CENTER", 0, 0 end end
		if k == "GetMinMaxValues" then return function() return 0, 0 end end
		if k == "GetHeight" then return function() return 400 end end
		if k == "GetWidth" then return function() return 700 end end
		if k == "GetCenter" then return function() return 100, 100 end end
		if k == "GetChecked" then return function(self) return self.checked == true end end
		if k == "SetChecked" then return function(self, v) self.checked = v and true or false end end
		if k == "HasFocus" then return function() return false end end
		if type(k) == "string" and k:match("^Get") then return function() return 0 end end
		if type(k) == "string" and k:match("^Create") then return function() return Stub() end end
		if type(k) == "string" and k:match("^%u") then return function() end end
		return nil
	end })
end

local clients, byName = {}, {}

local function Client(name, guild, opts)
	opts = opts or {}
	local env = setmetatable({}, { __index = _G })
	local c = { name = name, guild = guild, env = env, frames = {}, sent = {}, chat = {} }
	env._G = env
	env.time = function() return now end
	env.GetTime = function() return now end
	env.date = function(fmt, t) return os.date(fmt, t or now) end
	env.print = function(...) c.printed = (c.printed or 0) + 1 end
	env.C_Timer = {
		After = function(s, fn) Schedule(now + s, fn) end,
		NewTicker = function(s, fn) Schedule(now + s, fn, s) end,
	}
	local KNOWN = { ButtonFrameTemplate = true, PanelTabButtonTemplate = true, UIPanelButtonTemplate = true,
		UICheckButtonTemplate = true, InputBoxTemplate = true, WowStyle1DropdownTemplate = true, WowScrollBoxList = true,
		MinimalScrollBar = true, UIPanelCloseButton = true, BackdropTemplate = true }
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
		if template and not env.C_XMLUtil.GetTemplateInfo(template) then error("Couldn't find inherited node " .. template) end
		local f = Stub(fname)
		f.kind, f.template, f.parent = kind, template, parent
		if template == "ButtonFrameTemplate" then
			f.Inset, f.CloseButton = Stub(), Stub()
			f.PortraitContainer = { portrait = Stub() }
			f.TitleContainer = { TitleText = Stub() }
			f.SetTitle = function(self, t) self.title = t end
			f.SetPortraitToAsset = function(self, path) self.portraitPath = path end
		elseif template == "WowScrollBoxList" then
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
	env.PanelTemplates_SetNumTabs = function(f, n) f.numTabs = n end
	env.PanelTemplates_SetTab = function(f, i) f.selectedTab = i end
	env.PanelTemplates_TabResize = function() end
	env.SOUNDKIT = { IG_CHARACTER_INFO_TAB = 841, IG_CHARACTER_INFO_OPEN = 839, IG_CHARACTER_INFO_CLOSE = 840 }
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
	env.UISpecialFrames = {}
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
	env.UnitName = function() return name end
	env.UnitClass = function() return "Warrior", opts.class or "WARRIOR" end
	env.UnitLevel = function() return opts.level or 60 end
	env.IsInGuild = function() return c.guild ~= nil end
	env.GetGuildInfo = function() return c.guild, "Member", 3 end
	local roster = opts.roster or { { name, 60, "WARRIOR", true } }
	env.GetNumGuildMembers = function() return #roster, #roster end
	env.GetGuildRosterInfo = function(i)
		local r = roster[i]
		local note = (c.notes and c.notes[r[1]]) or r[7] or ""
		return r[1] .. "-CAMWOWEU5Realm2PvP", r[6] or "Member", r[5] or 3, r[2], "Class", "Stormwind", note, "", r[4], 0, r[3]
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
	-- the guild window (J): Blizzard_Communities, loaded at the first ToggleGuildFrame
	local function Communities()
		local host = Stub("CommunitiesFrame")
		host.shown = false
		host.GetWidth = function() return opts.hostWidth or 814 end
		host.GetHeight = function() return 426 end
		host.mode = "CHAT"
		host.GetDisplayMode = function(self) return self.mode end
		host.SetDisplayMode = function(self, m) self.mode = m end
		host.Hide = function(self) self.shown = false if self.scripts.OnHide then self.scripts.OnHide(self) end end
		for i, key in ipairs({ "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab" }) do
			local t = Stub(key)
			t.checked, t.shown = (i == 1), true
			host[key] = t
		end
		env.CommunitiesFrame = host
		env.COMMUNITIES_FRAME_DISPLAY_MODES = { MINIMIZED = "MINIMIZED", CHAT = "CHAT", ROSTER = "ROSTER" }
		return host
	end
	if opts.communities then
		env.ToggleGuildFrame = function()
			if not env.CommunitiesFrame then Communities() c.Fire("ADDON_LOADED", "Blizzard_Communities") end
			local h = env.CommunitiesFrame
			if h.shown then h:Hide() else h:Show() end
		end
	end
	env.GetChannelName = function(n) if n == "NLRiketNet" and c.joined then return 5, n end return 0 end
	env.JoinTemporaryChannel = function(n) if not opts.noChannel then c.joined = true end end
	env.C_ChatInfo = {
		RegisterAddonMessagePrefix = function() end,
		InChatMessagingLockdown = function() return c.lockdown == true end,
		SendAddonMessage = function(prefix, text, dist, target)
			assert(#text <= 255, "addon message too long: " .. #text)
			c.sent[#c.sent + 1] = text
			for _, o in ipairs(clients) do
				if o ~= c and o.loaded and ((dist == "CHANNEL" and o.joined) or (dist == "GUILD" and o.guild == c.guild)) then
					o.Fire("CHAT_MSG_ADDON", prefix, text, dist, name .. "-CAMWOWEU5Realm2PvP")
				end
			end
			return 0
		end,
		SendChatMessage = function(text, kind)
			for _, o in ipairs(clients) do
				if o.guild == c.guild then o.Fire("CHAT_MSG_GUILD", text, name .. "-CAMWOWEU5Realm2PvP") end
			end
		end,
	}
	env.Enum = { SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3, ChannelThrottle = 8 } }
	env.C_SkillInfo = { GetSkillLineInfoByID = function(id)
		local p = (opts.profs or {})[id]
		return { name = ({ [164] = "Blacksmithing", [186] = "Mining", [171] = "Alchemy" })[id] or ("Skill" .. id),
			rank = p and p[1] or 0, maxRank = p and p[2] or 0 }
	end }
	env.C_TradeSkillUI = {
		GetBaseProfessionInfo = function() return { professionID = c.openProf, professionName = "Blacksmithing", skillLevel = 250, maxSkillLevel = 300 } end,
		GetTradeSkillListLink = function() return "|cffffd000|Htrade:Player-1234-ABCD:2018:164|h[Blacksmithing]|h|r" end,
	}
	env.MenuUtil = { CreateContextMenu = function(owner, gen) local root = Root() gen(owner, root) c.menus[#c.menus + 1] = root end }
	env.SetItemRef = function(ref, link) c.opened = ref end
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
	for _, l in ipairs(list or {}) do if l:find(pat, 1, true) then return true end end
	return false
end

-- Two guilds: Aria and Bjorn in <Nerdelandslaget>, Cato in <Nerdelandslaget II>; Dina is in no
-- nerd guild.
local A = Client("Aria Ashfall", "Nerdelandslaget", { roster = { { "Aria Ashfall", 60, "WARRIOR", true }, { "Bjorn Ironside", 58, "MAGE", true }, { "Offline Olaf", 40, "MAGE", false } },
	profs = { [164] = { 250, 300 }, [186] = { 280, 300 } } })
local B = Client("Bjorn Ironside", "Nerdelandslaget", { class = "MAGE", roster = { { "Aria Ashfall", 60, "WARRIOR", true }, { "Bjorn Ironside", 58, "MAGE", true } } })
local bigRoster = {}
local RANKS = { [0] = "Guild Master", "Officer", "Veteran", "Member" }
for i = 1, 60 do bigRoster[i] = { ("Member Number%02d"):format(i), 10 + i % 50, "MAGE", true, i % 4, RANKS[i % 4] } end
local Cc = Client("Cato Cobalt", "Nerdelandslaget II", { class = "MAGE", roster = bigRoster, profs = { [171] = { 300, 300 } } })
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
ok(has(cLines, "[Nerdelandslaget] |Hplayer:Aria Ashfall|h[Aria Ashfall]|h: Hello from NL"), "shown as [Guild] [Name]: text")
ok(has(cLines, "|cffa335ee|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r"), "item links stay clickable")
ok(has(cLines, "||TInterface"), "texture codes are shown as text, not drawn")
ok(#(Lines(B)) == 0, "our own guild's line is not shown twice to our guild")
ok(#Cc.R.db.chatLog == 1 and Cc.R.db.chatLog[1].o == true, "kept in the window's log as another guild's line")

-- The other direction: Cato writes in <Nerdelandslaget II>.
Cc.env.C_ChatInfo.SendChatMessage("Hei fra NL II", "GUILD")
Advance(5)
ok(has(Lines(A), "[Nerdelandslaget II] |Hplayer:Cato Cobalt|h[Cato Cobalt]|h: Hei fra NL II"), "NL II's /g reaches NL (Aria)")
ok(has(Lines(B), "Hei fra NL II"), "NL II's /g reaches NL (Bjorn)")
ok(not has(Lines(D), "Hei fra NL II"), "outsiders see nothing")

-- A repeat from a second relay (both think they relay for a moment) is dropped.
A.Fire("CHAT_MSG_ADDON", "NLRIKET1", "C;Nerdelandslaget II;Cato Cobalt;Hei fra NL II", "CHANNEL", "Someone Else-X")
ok(#Lines(A) == 1, "a repeated line within 20 seconds is dropped")

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
ok(nl and nl.online == 2 and nl.members == 3, "NL's online count and size reach NL II")
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

-- The window builds and every tab fills.
local okUI, err = pcall(function()
	Cc.ns.UI.Open(1) Cc.ns.UI.Open(2) Cc.ns.UI.Open(3) Cc.ns.UI.Refresh()
end)
ok(okUI, "the window builds and fills: " .. tostring(err))
local okD = pcall(function() D.ns.UI.Open(2) end)
ok(okD, "the window opens outside the network too (behind its curtain)")
local okSlash = pcall(function() Cc.env.SlashCmdList.NLRIKET("status") Cc.env.SlashCmdList.NLRIKET("") end)
ok(okSlash, "/riket works")

-- The native look: Blizzard's portrait window with the NL emblem, bottom tabs, the credit.
local W = Cc.env.NLRiketFrame
ok(W and W.template == "ButtonFrameTemplate", "the window is Blizzard's portrait window")
ok(W.title == "Nerdelandslaget: Riket", "its title")
ok(W.portraitPath and W.portraitPath:find("media\\portrait128", 1, true), "the NL emblem sits in the portrait")
ok(W.credit and W.credit.text and W.credit.text:find("Made by Neophyte", 1, true), "the credit: " .. tostring(W.credit and W.credit.text))
local tocVersion = io.open(DIR .. "/Nerdelandslaget_Riket.toc"):read("*a"):match("## Version: ([%d%.]+)")
ok(W.credit.text:find("v" .. tocVersion, 1, true), "the credit carries the version from the .toc: " .. W.credit.text)
ok(W.numTabs == 3 and Cc.env.NLRiketFrameTab1 and Cc.env.NLRiketFrameTab3 and Cc.env.NLRiketFrameTab2.template == "PanelTabButtonTemplate", "three Blizzard tabs along the bottom")
ok(W.selectedTab == 3, "the open page's tab is marked")
Cc.env.NLRiketFrameTab2.scripts.OnClick(Cc.env.NLRiketFrameTab2, "LeftButton")
ok(W.selectedTab == 2 and Cc.R.db.tab == 2, "clicking a tab switches page")
ok(W.status.text and W.status.text:find("Nerdelandslaget II", 1, true) and W.status.text:find("60 of 60 online", 1, true), "the status strip shows who is online: " .. tostring(W.status.text))

-- Members in the scroll box.
local mp = Cc.ns.UI.pages[2]
ok(mp.list.native and mp.list.box and mp.list.box.template == "WowScrollBoxList", "members sit in Blizzard's scroll box")
ok(#mp.list.box.dp.items == 62, "every online member is listed: 60 + 2 (got " .. #mp.list.box.dp.items .. ")")
local row1 = mp.list.box.rows[1]
ok(row1.name and row1.name.text and row1.name.text:find("Member Number01", 1, true), "own guild first, sorted by name: " .. tostring(row1.name and row1.name.text))
ok(row1.rank.text == "Officer" and mp.list.box.rows[62].rank.text == "Member", "the Rank column, own guild and the other: " .. tostring(row1.rank.text) .. " / " .. tostring(mp.list.box.rows[62].rank.text))
ok(#mp.headers == 6 and mp.headers[4].label.text == "Rank", "six columns, Rank among them")
local function Sorted(items, key, desc)
	for i = 2, #items do
		local a, b = items[i - 1][key], items[i][key]
		if a and b and ((desc and a < b) or (not desc and a > b)) then return false end
	end
	return true
end
mp.headers[2].scripts.OnClick(mp.headers[2])
ok(Cc.R.db.memberSort.key == "level" and Cc.R.db.memberSort.desc == true, "Level: the first click sorts highest first")
ok(mp.list.items[1].level == 60 and Sorted(mp.list.items, "level", true), "the list follows, highest level on top")
ok(mp.headers[2].arrow.shown == true and mp.headers[1].arrow.shown == false, "the arrow sits on Level")
mp.headers[2].scripts.OnClick(mp.headers[2])
ok(Cc.R.db.memberSort.desc == false and Sorted(mp.list.items, "level", false) and mp.list.items[1].level == 10, "the second click turns it round")
mp.headers[4].scripts.OnClick(mp.headers[4])
ok(mp.list.items[1].rankIndex == 0 and Sorted(mp.list.items, "rankIndex", false), "Rank: guild master first")
mp.headers[1].scripts.OnClick(mp.headers[1])
ok(Sorted(mp.list.items, "name", false), "Name: A to Z")
Cc.R.db.memberSort.key, Cc.R.db.memberSort.desc = "guild", false
mp:Refresh()
row1 = mp.list.box.rows[1]
ok(row1.stripe and row1.item.index == 1, "rows get their stripe and index")
local last = mp.list.box.rows[62]
ok(last.guild.text:find("Nerdelandslaget", 1, true) and last.name.text:find("Bjorn Ironside", 1, true), "the other guild after: " .. tostring(last.name.text))
last.scripts.OnClick(last, "RightButton")
local menu = Cc.menus[#Cc.menus]
ok(menu and menu.items[1].title == "Bjorn Ironside" and menu.items[2].text == "Whisper" and menu.items[3].text == "Invite to group", "right-click opens whisper and invite")
last.scripts.OnEnter(last)
ok(has(Cc.env.GameTooltip.tlines, "Click to whisper"), "a row's tooltip says what a click does")

-- Professions with the dropdown.
Cc.ns.UI.Open(3)
local pp = Cc.ns.UI.pages[3]
ok(pp.filter.root and pp.filter.root.items[1].text == "All professions", "the dropdown starts with all professions")
local names = {}
for _, it in ipairs(pp.filter.root.items) do names[#names + 1] = it.text end
ok(has(names, "Alchemy") and has(names, "Blacksmithing") and has(names, "Mining"), "and offers every known profession: " .. table.concat(names, ", "))
ok(#pp.list.box.dp.items == 3, "all three professions listed")
for _, it in ipairs(pp.filter.root.items) do if it.text == "Alchemy" then it.set(it.data) end end
ok(Cc.R.db.profFilter == 171 and #pp.list.box.dp.items == 1 and pp.list.box.dp.items[1].name == "Cato Cobalt", "choosing Alchemy filters the list")
ok(pp.filter.root.items[1].is(0) == false, "the radio follows the choice")
for _, it in ipairs(pp.filter.root.items) do if it.text == "All professions" then it.set(it.data) end end
local bs
for _, r in ipairs(pp.list.box.rows) do if r.item and r.item.id == 164 then bs = r end end
ok(bs and bs.link.text.text:find("Htrade", 1, true), "the profession link shows in its row")
bs.link.scripts.OnClick(bs.link, "LeftButton")
ok(Cc.opened and Cc.opened:find("^trade:"), "clicking the link opens the recipes")

-- Chat page parts.
local cp = Cc.ns.UI.pages[1]
ok(cp.input and cp.input.template == "InputBoxTemplate" and cp.show.template == "UICheckButtonTemplate", "Blizzard's input box and check button")
ok(Cc.chatBar ~= nil, "the chat log gets the thin Blizzard scroll bar")

-- Minimap button and the addon list entry.
local MB = Cc.env.NLRiketMapButton
MB.scripts.OnEnter(MB)
ok(has(Cc.env.GameTooltip.tlines, "Made by Neophyte"), "the minimap tooltip carries the credit")
MB.scripts.OnClick(MB, "RightButton")
ok(Cc.menus[#Cc.menus].items[1].title == "Nerdelandslaget: Riket", "the minimap menu")
ok(type(Cc.env.NLRiket_OnAddonCompartmentClick) == "function" and type(Cc.env.NLRiket_OnAddonCompartmentEnter) == "function", "the addon list entry has its functions")
Cc.env.NLRiket_OnAddonCompartmentEnter("Nerdelandslaget_Riket", Cc.env.UIParent)
ok(has(Cc.env.GameTooltip.tlines, "Nerdelandslaget: Riket"), "the addon list entry shows a tooltip")

-- Discord names travel in the hello and show in the Members list.
ok(A.R.db.discords["Cato Cobalt"] == "cato_dc" and Cc.R.db.discords["Aria Ashfall"] == "aria_dc", "Discord names reach the other guild")
ok(has(A.sent, "H;Nerdelandslaget;" .. tocVersion .. ";aria_dc"), "the hello carries the Discord name")
local aria
for _, r in ipairs(mp.list.box.rows) do if r.item and r.item.name == "Aria Ashfall" then aria = r end end
ok(aria and aria.discord.text == "aria_dc" and #mp.headers == 6 and mp.headers[5].label.text == "Discord", "the Discord column")
B.Fire("CHAT_MSG_ADDON", "NLRIKET1", "H;Nerdz;1.1.0", "CHANNEL", "Old Timer-X")
ok(B.R.peers["Old Timer"] and B.R.peers["Old Timer"].version == "1.1.0" and B.R.db.discords["Old Timer"] == nil, "a hello from before 1.3 still counts")
B.Fire("CHAT_MSG_ADDON", "NLRIKET1", "H;Nerdz;1.3.0;|TInterface\\X:900|t", "CHANNEL", "Bad Actor-X")
ok(not (B.R.db.discords["Bad Actor"] or ""):find("|", 1, true), "a Discord name can't carry escape codes")

-- A newcomer without a Discord name: nothing starts until it is set.
local N = Client("Nora Nyhet", "Nerdelandslaget", { discord = false, canEdit = true })
Advance(30)
ok(not N.R.ready and N.R.waiting and #N.sent == 0, "without a Discord name Riket stays off and sends nothing")
ok(N.popups[1] and N.popups[1].which == "NLRIKET_DISCORD", "the login asks for the Discord name")
N.ns.UI.Open(1)
ok(N.ns.UI.setup.shown == true and N.ns.UI.pages[1]:GetParent() ~= nil, "the window shows the Discord setup")
ok(rawget(N.env.NLRiketFrame, "shown") ~= false and N.ns.UI.setup.shown and not N.ns.UI.lock.shown, "the setup, not the curtain")
local popupSelf = { editBox = Stub() }
popupSelf.editBox.text = "x"
ok(N.env.StaticPopupDialogs.NLRIKET_DISCORD.OnAccept(popupSelf) == true and not N.R.Discord(), "one letter is refused and the box stays open")
popupSelf.editBox.text = "  nora|nyhet  "
N.env.StaticPopupDialogs.NLRIKET_DISCORD.OnAccept(popupSelf)
ok(N.R.Discord() == "noranyhet", "the name is saved, trimmed and cleaned: " .. tostring(N.R.Discord()))
ok(N.ns.UI.setup.shown == false, "the setup goes away")
Advance(5)
ok(N.R.ready and has(N.sent, ";noranyhet"), "setting it starts Riket")
local np = N.popups[#N.popups]
ok(np.which == "NLRIKET_NOTE" and np.a == "(empty)" and np.b == "noranyhet", "it offers the guild note")
N.env.StaticPopupDialogs.NLRIKET_NOTE.OnAccept()
ok(N.noteSet and N.noteSet.text == "noranyhet" and N.noteSet.public == true and N.noteSet.guid == "Player-1-Nora Nyhet", "yes writes the public note")
local before = #N.popups
N.ns.UI.OfferNote(true)
ok(#N.popups == before, "no offer once the note holds the name")
ok(not has({ (A.popups[1] or {}).which }, "NLRIKET_NOTE"), "no offer where the guild doesn't let members edit notes")

-- The guild window (J): Riket is a tab on its side.
local Jc = Client("Jonas Jord", "Nerdelandslaget", { communities = true })
Advance(30)
Jc.ns.UI.Open(2)
local host = Jc.env.CommunitiesFrame
local panel, gtab = Jc.env.NLRiketFrame, Jc.env.NLRiketGuildTab
ok(host and host.shown, "opening Riket opens the guild window, loading it the first time")
ok(panel and panel.inJ and panel.parent == host and panel.shown, "Riket's pages sit inside the guild window")
ok(gtab and gtab.parent == host and gtab.checked and gtab.shown, "with its own tab on the window's side, marked")
ok(host.ChatTab.checked == false, "the window's own tab is unmarked while Riket shows")
ok(#Jc.ns.UI.pages[2].list.items >= 1, "the Members page fills inside the guild window")
ok(not has(Jc.env.UISpecialFrames, "NLRiketFrame"), "no window of its own")
host.RosterTab.scripts.OnClick(host.RosterTab)
ok(panel.shown == false and gtab.checked == false, "the window's own tab takes Riket away")
host.ChatTab.checked = true
gtab.scripts.OnClick(gtab)
ok(panel.shown and host.ChatTab.checked == false, "our tab brings it back")
gtab.scripts.OnClick(gtab)
ok(panel.shown == false and host.ChatTab.checked == true, "and a second click gives the window back as it was")
Jc.ns.UI.Open(3)
host:Hide()
ok(panel.shown == false and gtab.checked == false, "closing the guild window closes Riket")
Jc.env.ToggleGuildFrame()
host:SetDisplayMode("MINIMIZED")
ok(gtab.shown == false, "the small chat-only mode has no Riket tab")
host:SetDisplayMode("CHAT")
ok(gtab.shown == true, "full size brings it back")
Jc.ns.UI.Open(1)
Jc.ns.UI.Toggle()
ok(host.shown == false and panel.shown == false, "toggling closes the guild window")
local Jw = Client("Juni Smal", "Nerdelandslaget", { communities = true, hostWidth = 400 })
Advance(30)
Jw.ns.UI.Open(2)
ok(Jw.env.NLRiketFrame and not Jw.env.NLRiketFrame.inJ, "a guild window too small for Riket: its own window instead")

-- A client without any of the templates still builds, with plain stand-ins.
local F = Client("Frida Fjell", "Nerdelandslaget II", { noTemplates = true, class = "MAGE" })
Advance(10)
local okF, errF = pcall(function() F.ns.UI.Open(1) F.ns.UI.Open(2) F.ns.UI.Open(3) F.ns.UI.Refresh() end)
ok(okF, "without the templates the window still builds: " .. tostring(errF))
local FW = F.env.NLRiketFrame
ok(FW and FW.template ~= "ButtonFrameTemplate" and FW.credit.text:find("Made by Neophyte", 1, true), "and keeps the credit")
ok(F.ns.UI.pages[2].list.plain and not F.ns.UI.pages[2].list.native, "and uses the plain list")
ok(F.ns.UI.pages[3].filter.standIn, "and a button in place of the dropdown")

-- Without the channel: falls back to GUILD (own guild only), no errors.
local E = Client("Eirik Edge", "Nerdelandslaget", { noChannel = true })
Advance(30)
ok(E.R.ready and E.R.ChannelID() == nil, "a client without the channel still starts")

print(("%d/%d checks passed"):format(checks - fails, checks))
os.exit(fails == 0 and 0 or 1)
