-- Nerdelandslaget: Riket. One guild chat, one list of who is online and one list of everyone's
-- professions for every guild with "nerd" in its name (Nerdelandslaget, Nerdelandslaget II,
-- Nerdealtslaget...). A standalone addon: it needs nothing else, and sits beside Hans's
-- Nerdelandslaget suite without sharing anything with it (its own channel, data and commands).
--
-- The guilds meet in a hidden chat channel (addon messages only; it never shows in chat). If it
-- can't be joined, messages go to GUILD, which reaches at least our own guild.
--
-- Messages (prefix NLRIKET1, fields separated by ';', free text last):
--   H;guild;version                       I have Riket (when ready, then every minute)
--   C;guild;author;text                   a line of that guild's /g, sent by its relay
--   O;guild;stamp;part;parts;online;members;entries
--                                         who is online in that guild, sent by its relay
--                                         entries: name,level,classID joined by '/'
--   P;guild;classID;level;professions     my professions: skillLine.rank.max joined by ','
--   K;skillLine;link                      the link to one of my professions
--   Q                                     please send me your professions
--
-- A guild's relay is its member with Riket whose name sorts first among those heard in the last
-- 150 seconds. Only the relay repeats its guild's /g and roster, so every line crosses once
-- (receivers drop a repeat within 20 seconds, in case two think they are the relay).
-- Nothing is verified: a message says what its sender says.
-- WoW Forever runs Midnight's secret values: anything the game hands us is checked first.

local ADDON_NAME, ns = ...

local R = {}
ns.R = R

R.PREFIX = "NLRIKET1"
R.CHANNEL = "NLRiketNet"
R.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")) or "0"
R.HELLO_EVERY = 60     -- seconds between our "I have Riket"
R.PEER_FOR = 150       -- a member with Riket counts as online this long after we last heard him
R.MAX_BYTES = 250      -- an addon message at most (the game's limit is 255)
R.MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\"

local DEFAULTS = {
	toChatFrame = true,   -- the other guilds' /g shows in the chat windows that show our /g
	window = {},
	tab = 1,
	profFilter = 0,       -- 0 = every profession
	memberSort = { key = "guild", desc = false },   -- the Members list's sort: name, level, guild, rank or zone
	mapButton = true,
	mapAngle = 200,
	debug = false,
	-- discord = "name": this player's Discord name, for every character on the account. Riket
	-- stays off until it is set.
	discords = {},        -- [character] = Discord name, as each one's Riket says it
	crafters = {},        -- [name] = { guild, class, level, profs = { [skillLine] = { rank, max } }, links, t }
	chatLog = {},         -- the last lines of every guild's /g, for the window
	log = {},
}
local CHAR_DEFAULTS = {
	profs = {},           -- [skillLine] = { rank, max, name }: what the profession window said last
	links = {},           -- [skillLine] = the profession's link, from the profession window
	noteAsked = false,    -- whether we have offered to put the Discord name in this character's guild note
}

---------------------------------------------------------------------------
-- Secret values (Midnight's rules, active on Forever)
---------------------------------------------------------------------------

local issecretvalue = issecretvalue
function R.IsSecret(v) return issecretvalue ~= nil and issecretvalue(v) == true end
-- The value if it can be read, else nil. Use before any comparison or arithmetic.
function R.Plain(v)
	if v == nil or R.IsSecret(v) then return nil end
	return v
end
local IsSecret, Plain = R.IsSecret, R.Plain

---------------------------------------------------------------------------
-- Events: any number of handlers per event
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local events = {}
function R.On(event, fn)
	if not events[event] then
		if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then return end
		events[event] = {}
		frame:RegisterEvent(event)
	end
	table.insert(events[event], fn)
end
frame:SetScript("OnEvent", function(_, event, ...)
	for _, fn in ipairs(events[event] or {}) do
		local ok, err = pcall(fn, ...)
		if not ok then R.Log("error in", event, err) end
	end
end)

---------------------------------------------------------------------------
-- Log (in the saved data; /riket debug shows it in chat as it happens)
---------------------------------------------------------------------------

function R.Log(...)
	local parts = {}
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		parts[i] = IsSecret(v) and "<secret>" or tostring(v)
	end
	local line = date("%H:%M:%S ") .. table.concat(parts, " ")
	if not R.db then return end
	local log = R.db.log
	log[#log + 1] = line
	while #log > 300 do table.remove(log, 1) end
	if R.db.debug then print("|cffe8642bRiket|r " .. line) end
end

function R.Print(msg) print("|cffe8642bRiket:|r " .. tostring(msg)) end

---------------------------------------------------------------------------
-- Names and guilds
---------------------------------------------------------------------------

-- A character's name without its realm. Forever's names ("First Surname") are one across the
-- realm group, and the realm part is an internal id the server won't take back.
function R.Name(full)
	if type(full) ~= "string" or IsSecret(full) or full == "" then return nil end
	return full:match("^([^%-]+)") or full
end

-- Forever's names are "First Surname", and the game may give us only the first part of our own
-- (while the roster and everyone else see the whole). Our full name is found by our GUID in the
-- guild roster, by being the only roster name that starts with ours, or by hearing our own
-- hello come back on the channel.
function R.Me()
	return R.fullName or R.Name(UnitName("player"))
end

function R.LearnName(full)
	full = R.Name(full)
	if not full or full == R.fullName then return end
	local short = R.Name(UnitName("player"))
	R.fullName = full
	if R.db and short and short ~= full then   -- what was kept under the short name was us
		R.db.crafters[short] = nil
		R.db.discords[short] = nil
	end
	if R.db and R.Discord() then R.db.discords[full] = R.Discord() end
	R.Log("my name", full)
	R.Changed("me")
end

function R.FindMyName()
	if R.fullName then return R.fullName end
	local short = R.Name(UnitName("player"))
	if short and short:find(" ", 1, true) then R.LearnName(short) return short end
	if not (GetNumGuildMembers and GetGuildRosterInfo) then return nil end
	local guid = UnitGUID and R.Plain(UnitGUID("player"))
	local prefix = short and (short .. " ")
	local match, count = nil, 0
	for i = 1, R.Plain((GetNumGuildMembers())) or 0 do
		local res = { pcall(GetGuildRosterInfo, i) }
		local name = res[1] and R.Name(R.Plain(res[2]))
		if name then
			if guid and R.Plain(res[18]) == guid then R.LearnName(name) return name end
			if name == short then return nil end   -- the game's name is our whole name after all
			if prefix and name:sub(1, #prefix) == prefix then match, count = name, count + 1 end
		end
	end
	if count == 1 then R.LearnName(match) return match end
	return nil
end

-- Is this a guild of the network? Every guild with "nerd" in its name, any case.
function R.IsNerdGuild(name)
	return type(name) == "string" and not IsSecret(name) and name:lower():find("nerd", 1, true) ~= nil
end

-- Our guild's name, or nil when we are in no guild of the network.
function R.MyGuild()
	if not IsInGuild() then return nil end
	local g = GetGuildInfo("player")
	if R.IsNerdGuild(g) then return g end
	return nil
end

-- A guild name as it may travel in a field.
function R.CleanGuild(g)
	if not R.IsNerdGuild(g) or #g > 32 or g:find("[;|/,]") then return nil end
	return g
end

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

-- s cut to at most max bytes, never in the middle of a UTF-8 character.
function R.Cut(s, max)
	if type(s) ~= "string" or #s <= max then return s end
	local cut = max
	while cut > 0 do
		local b = s:byte(cut + 1)
		if not b or b < 0x80 or b >= 0xC0 then break end
		cut = cut - 1
	end
	return s:sub(1, cut)
end

-- The first n - 1 ';' fields of s and the rest of it as field n; nil if s has fewer.
function R.Split(s, n)
	if type(s) ~= "string" then return nil end
	local out, pos = {}, 1
	for i = 1, n - 1 do
		local a = s:find(";", pos, true)
		if not a then return nil end
		out[i] = s:sub(pos, a - 1)
		pos = a + 1
	end
	out[n] = s:sub(pos)
	return out
end

-- "now", "4m", "2h", "3d"
function R.Ago(t)
	if type(t) ~= "number" then return "" end
	local s = math.max(0, time() - t)
	if s < 60 then return "now" end
	if s < 3600 then return math.floor(s / 60) .. "m" end
	if s < 86400 then return math.floor(s / 3600) .. "h" end
	return math.floor(s / 86400) .. "d"
end

local CLASS_ID = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, DEATHKNIGHT = 6, SHAMAN = 7,
	MAGE = 8, WARLOCK = 9, MONK = 10, DRUID = 11, DEMONHUNTER = 12, EVOKER = 13 }
local CLASS_FILE = {}
for file, id in pairs(CLASS_ID) do CLASS_FILE[id] = file end
function R.ClassID(file) return CLASS_ID[file or ""] or 0 end
function R.ClassFile(id) return CLASS_FILE[tonumber(id) or 0] end

function R.ClassColor(file)
	local c
	if file and C_ClassColor and C_ClassColor.GetClassColor then c = C_ClassColor.GetClassColor(file) end
	if not c and file and RAID_CLASS_COLORS then c = RAID_CLASS_COLORS[file] end
	if not c then return "ffe8dcb5" end
	if c.GenerateHexColor then return c:GenerateHexColor() end
	return string.format("ff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end

function R.ClassName(name, file) return "|c" .. R.ClassColor(file) .. tostring(name) .. "|r" end

local listeners = {}
function R.OnChange(fn) listeners[#listeners + 1] = fn end
function R.Changed(what, ...)
	for _, fn in ipairs(listeners) do
		local ok, err = pcall(fn, what, ...)
		if not ok then R.Log("listener error", err) end
	end
end

-- Opens a whisper to name in the chat box.
function R.Whisper(name)
	if not name then return end
	for _, fn in ipairs({ ChatFrameUtil and ChatFrameUtil.SendTell, ChatFrame_SendTell }) do
		if type(fn) == "function" and pcall(fn, name) then return end
	end
end

function R.Invite(name)
	local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
	if name and fn then pcall(fn, name) end
end

---------------------------------------------------------------------------
-- The hidden channel and the send queue
---------------------------------------------------------------------------

local BURST, REFILL, QUEUE_MAX = 5, 1.25, 60   -- messages at once, seconds per new one, waiting at most
local queue, tokens, lastRefill = {}, BURST, 0

function R.ChannelID()
	local id = GetChannelName and GetChannelName(R.CHANNEL)
	if type(id) ~= "number" or IsSecret(id) or id <= 0 then return nil end
	return id
end

function R.JoinChannel()
	if R.ChannelID() then return true end
	if not R.MyGuild() then return false end   -- only members of the network sit in it
	local join = JoinTemporaryChannel or JoinChannelByName
	if not join then return false end
	local ok, err = pcall(join, R.CHANNEL)
	if not ok then R.Log("joining the channel failed:", err) end
	return ok
end

-- "NLRiketNet", "6. NLRiketNet" or "NLRiketNet - ..."
local function IsOurChannel(name)
	if type(name) ~= "string" or IsSecret(name) then return false end
	local base = name:gsub("^%d+%.%s*", "")
	base = base:match("^(.-) %- ") or base
	return base:lower() == R.CHANNEL:lower()
end

local function ChannelFilter(_, _, _, _, _, channelString, _, _, _, _, channelBase)
	return IsOurChannel(channelString) or IsOurChannel(channelBase)
end

local function SendOne(m)
	local dist, target = "GUILD", nil
	local id = R.ChannelID()
	if id then
		dist, target = "CHANNEL", id
	elseif not IsInGuild() then
		return true                    -- nowhere to send it: drop
	end
	local ok, res = pcall(C_ChatInfo.SendAddonMessage, R.PREFIX, m.text, dist, target)
	if not ok then
		R.Log("send failed", dist, res)
		return true
	end
	local E = Enum and Enum.SendAddonMessageResult
	if E and res ~= nil and res ~= E.Success then
		if res == E.AddonMessageThrottle or res == E.ChannelThrottle then return false end
		R.Log("send result", res, dist)
	end
	return true
end

local function Flush()
	local now = GetTime()
	tokens = math.min(BURST, tokens + (now - lastRefill) / REFILL)
	lastRefill = now
	if #queue == 0 then return end
	if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return end
	while #queue > 0 and tokens >= 1 do
		if SendOne(queue[1]) then
			table.remove(queue, 1)
			tokens = tokens - 1
		else
			tokens = 0
			break
		end
	end
end

-- key: a newer message with the same key replaces one still waiting in the queue.
function R.Send(text, key)
	if not R.ready then return end
	local m = { text = R.Cut(text, R.MAX_BYTES), key = key }
	if key then
		for i, q in ipairs(queue) do
			if q.key == key then queue[i] = m return end
		end
	end
	if #queue >= QUEUE_MAX then table.remove(queue, 1) end
	queue[#queue + 1] = m
end

local handlers = {}
function R.Handle(kind, fn) handlers[kind] = fn end

R.On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
	if IsSecret(prefix) or IsSecret(text) or IsSecret(sender) or prefix ~= R.PREFIX or type(text) ~= "string" then return end
	if not R.MyGuild() then return end   -- outside the network we hear nothing
	if not R.Discord() then return end   -- nor before the Discord name is set
	local who = R.Name(sender)
	if not who then return end
	if not R.fullName and R.lastHello and text == R.lastHello and who ~= R.Me() then
		local short = R.Me()
		if short and who:sub(1, #short + 1) == short .. " " then R.LearnName(who) end   -- our own hello, under our whole name
	end
	if who == R.Me() then return end
	local kind, rest = text:match("^(%u);?(.*)$")
	local fn = kind and handlers[kind]
	if not fn then return end
	local ok, err = pcall(fn, rest, who)
	if not ok then R.Log("handler error", kind, err) end
end)

---------------------------------------------------------------------------
-- Who has Riket, and each guild's relay
---------------------------------------------------------------------------

R.peers = {}   -- [name] = { guild, t, version }

---------------------------------------------------------------------------
-- Discord names: every player sets theirs once, and Riket starts only then
---------------------------------------------------------------------------

-- A Discord name as typed: trimmed, without separators or escape codes, 2 to 32 bytes.
function R.CleanDiscord(s)
	if type(s) ~= "string" or IsSecret(s) then return nil end
	s = s:gsub("[%c;|/,]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	s = R.Cut(s, 32)
	if #s < 2 then return nil end
	return s
end

function R.Discord()
	return R.db and R.CleanDiscord(R.db.discord)
end

function R.DiscordOf(name)
	if not name or not R.db then return nil end
	if name == R.Me() then return R.Discord() end
	return R.db.discords[name]
end

local Start
function R.SetDiscord(name)
	local d = R.CleanDiscord(name)
	if not d or not R.db then return false end
	R.db.discord = d
	local me = R.Me()
	if me then R.db.discords[me] = d end
	if R.ready then R.Hello() elseif Start then Start() end
	R.Changed("discord")
	return true
end

function R.Heard(name, guild, version, discord)
	guild = R.CleanGuild(guild)
	if not name or not guild then return end
	discord = R.CleanDiscord(discord)
	if discord and R.db then R.db.discords[name] = discord end
	local p = R.peers[name]
	local fresh = not p or p.guild ~= guild or time() - p.t > R.PEER_FOR
	p = p or {}
	p.guild, p.t = guild, time()
	if version and version ~= "" then p.version = version end
	R.peers[name] = p
	if fresh then R.Changed("peer", name, guild) end
end

-- The name of a guild's relay: its member with Riket heard lately whose name sorts first (we
-- count ourselves for our own guild).
function R.Relay(guild)
	local best
	if guild == R.MyGuild() then best = R.Me() end
	local now = time()
	for name, p in pairs(R.peers) do
		if p.guild == guild and now - p.t <= R.PEER_FOR and (not best or name < best) then best = name end
	end
	return best
end

function R.IAmRelay()
	local g = R.MyGuild()
	return g ~= nil and R.Me() ~= nil and R.Relay(g) == R.Me()
end

-- Is someone with Riket in another guild online (so there is anyone to send our guild to)?
function R.OtherGuildOnline()
	local mine, now = R.MyGuild(), time()
	for _, p in pairs(R.peers) do
		if p.guild ~= mine and now - p.t <= R.PEER_FOR then return true end
	end
	return false
end

-- The guilds of the network we know of, ours first, then the others heard lately.
function R.Guilds()
	local out, seen, now = {}, {}, time()
	local mine = R.MyGuild()
	if mine then out[1], seen[mine] = mine, true end
	for _, p in pairs(R.peers) do
		if not seen[p.guild] and now - p.t <= R.PEER_FOR then
			seen[p.guild] = true
			out[#out + 1] = p.guild
		end
	end
	table.sort(out, function(a, b)
		if a == mine then return true elseif b == mine then return false end
		return a < b
	end)
	return out
end

-- H;guild;version;discord (before 1.3 without the Discord name; a client from then reads the
-- version and the name together as its version, which it only ever shows in /riket status)
R.Handle("H", function(rest, who)
	local f = R.Split(rest, 3) or R.Split(rest, 2)
	if f then R.Heard(who, f[1], f[2], f[3]) end
end)

function R.Hello()
	local g = R.MyGuild()
	if g then
		R.lastHello = "H;" .. g .. ";" .. R.VERSION .. ";" .. (R.Discord() or "")
		R.Send(R.lastHello, "H")
	end
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------

R.onReady = {}
function R.WhenReady(fn) R.onReady[#R.onReady + 1] = fn end

local function Defaults(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			Defaults(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end

R.On("ADDON_LOADED", function(name)
	if name ~= ADDON_NAME then return end
	NLRiketDB = NLRiketDB or {}
	R.db = Defaults(NLRiketDB, DEFAULTS)
	NLRiketCharDB = NLRiketCharDB or {}
	R.char = Defaults(NLRiketCharDB, CHAR_DEFAULTS)
	R.Changed("loaded")
end)

R.On("PLAYER_LOGIN", function()
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, R.PREFIX) end
	local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
	if add then
		for _, ev in ipairs({ "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER", "CHAT_MSG_CHANNEL",
			"CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE" }) do
			pcall(add, ev, ChannelFilter)
		end
	end
	lastRefill = GetTime()
	C_Timer.NewTicker(0.3, Flush)
end)

-- Join a while after logging in, once General and Trade have their numbers, so ours never
-- takes one of theirs; then say hello and start the parts. Without a Discord name nothing
-- starts: the window asks for it, and setting it starts everything.
local loggedIn, starting = false, false
Start = function()
	if R.ready or starting or not loggedIn then return end
	R.FindMyName()
	if not R.Discord() then
		R.waiting = true
		R.Changed("needsDiscord")
		return
	end
	starting, R.waiting = true, false
	local me = R.Me()
	if me then R.db.discords[me] = R.Discord() end
	R.JoinChannel()
	C_Timer.After(2, function()
		R.ready = true
		R.Log("ready", R.VERSION, "guild", R.MyGuild(), "channel", R.ChannelID())
		R.Hello()
		C_Timer.NewTicker(R.HELLO_EVERY, R.Hello)
		for _, fn in ipairs(R.onReady) do
			local ok, err = pcall(fn)
			if not ok then R.Log("start error", err) end
		end
		R.Changed("ready")
	end)
end
local started = false
R.On("PLAYER_ENTERING_WORLD", function()
	if started then return end
	started = true
	C_Timer.After(10, function()
		loggedIn = true
		Start()
	end)
end)

-- Rejoin if something (a chat addon, a /leave) dropped us.
R.On("CHANNEL_UI_UPDATE", function()
	if R.ready and not R.ChannelID() then
		C_Timer.After(5, function() if not R.ChannelID() then R.JoinChannel() end end)
	end
end)

-- A new guild: say hello there at once.
R.On("PLAYER_GUILD_UPDATE", function()
	if not R.ready then
		if R.waiting and R.MyGuild() then R.Changed("needsDiscord") end
		return
	end
	if R.MyGuild() then R.JoinChannel() end
	R.Hello()
	R.Changed("guild")
end)
