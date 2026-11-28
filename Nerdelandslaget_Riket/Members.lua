-- Members: who is online in every guild of the network. Our own guild comes live from the
-- game's roster; each other guild's relay sends its online members (O) every two minutes, and
-- at once when someone with Riket in another guild comes online. A guild nobody has sent for
-- five and a half minutes is shown as unknown.
-- Guild ranks (1.2) travel beside the list, so a client from before then still reads it: G is
-- one digit per member in the list's order (the rank's index, 0 = guild master), N the names.
-- Who is offline (1.4.3): every guild's members are kept between sessions (R.db.roster), with
-- when each was last online. Our own guild's come from the roster; each other guild's relay
-- sends its members offline within the last 30 days (F) when the channel has room, and anyone
-- seen in an online list is kept too, so a relay from before 1.4.3 still fills it in part.

local ADDON_NAME, ns = ...
local R = ns.R
local Plain = R.Plain

local M = {}
ns.Members = M

M.SEND_EVERY = 120
M.KEEP = 330
M.PARTS_MAX = 20
M.OFFLINE_DAYS = 30       -- members offline longer are neither sent nor shown
M.OFFLINE_EVERY = 900     -- a relay sends who is offline this often
M.OFFLINE_GAP = 180       -- and not again sooner, however many come online
M.OFFLINE_PARTS_MAX = 40  -- about 280 members, the most recent

M.guilds = {}        -- [guild] = { list = { { name, level, class, zone, rank, rankIndex } }, online, members, t, own, ranks, stamp, from }
local assembling = {} -- [guild] = { stamp, from, parts, got, n }
local rankNames = {}  -- [guild] = { [index] = name }, from N
local rankDigits = {} -- [guild] = { stamp, from, digits }, from G, until the list it belongs to is in
local offAssembling = {} -- [guild] = { stamp, from, parts, got, n }, for F

-- A rank name safe to send and to show: no separators, no escape codes, at most 20 bytes.
local function CleanRank(s)
	if type(s) ~= "string" then return nil end
	s = s:gsub("[;/|]", "")
	s = R.Cut(s, 20)
	return s ~= "" and s or nil
end

function M.RankName(guild, index)
	if type(index) ~= "number" then return nil end
	local e = M.guilds[guild]
	local names = (e and e.ranks) or rankNames[guild] or (R.db and R.db.ranks[guild])
	return names and names[index]
end

---------------------------------------------------------------------------
-- Everyone in the guilds, online or not, kept between sessions
---------------------------------------------------------------------------

local DAY = 86400

-- Notes a member of guild g, last online at `seen` (or offline since we don't know when, if the
-- game didn't say: m.days == false).
local function Keep(m, g, seen)
	if not (R.db and m.name) then return end
	local k = R.db.roster[m.name]
	if not k then k = {} R.db.roster[m.name] = k end
	if k.g ~= g then k.s = nil end
	k.g, k.l, k.c = g, m.level or k.l, m.class or k.c
	if m.rankIndex then k.r = m.rankIndex end
	if not k.s or seen > k.s then k.s = seen end
	k.u = (m.days == false) or nil
end

-- A guild's members as one of its lists says: everyone online and offline. Members of g in
-- neither have left it, or were away too long.
local function Replace(g, online, offline)
	local t, listed = time(), {}
	for _, m in ipairs(online) do listed[m.name] = true Keep(m, g, t) end
	for _, m in ipairs(offline) do listed[m.name] = true Keep(m, g, t - (m.days or 0) * DAY) end   -- (days false: unknown)
	for name, k in pairs(R.db.roster) do
		if k.g == g and not listed[name] then R.db.roster[name] = nil end
	end
end

-- Forgets members not online for longer than OFFLINE_DAYS.
function M.Prune()
	if not R.db then return end
	local limit = time() - M.OFFLINE_DAYS * DAY
	for name, k in pairs(R.db.roster) do
		if type(k) ~= "table" or not k.s or k.s < limit then R.db.roster[name] = nil end
	end
end

-- Members of the guilds who are offline, last online within OFFLINE_DAYS: { name, guild, level,
-- class, rankIndex, rank, seen }.
function M.Offline()
	if not R.db then return {} end
	local online, t = {}, time()
	for g, e in pairs(M.guilds) do
		if M.Get(g) then for _, m in ipairs(e.list) do online[m.name] = true end end
	end
	for name, p in pairs(R.peers) do
		if t - p.t <= R.PEER_FOR then online[name] = true end
	end
	online[R.Me() or ""] = true
	local out, limit = {}, t - M.OFFLINE_DAYS * DAY
	for name, k in pairs(R.db.roster) do
		if not online[name] and type(k) == "table" and k.g and k.s and k.s >= limit then
			out[#out + 1] = { name = name, guild = k.g, level = k.l, class = k.c, rankIndex = k.r,
				rank = M.RankName(k.g, k.r), seen = math.min(k.s, t), unknown = k.u }
		end
	end
	return out
end

-- Days since a roster member was last online, or nil if the game doesn't say.
local function DaysOffline(i)
	if not GetGuildRosterLastOnline then return nil end
	local ok, y, mo, d, h = pcall(GetGuildRosterLastOnline, i)
	if not ok then return nil end
	y, mo, d, h = Plain(y), Plain(mo), Plain(d), Plain(h)
	if type(y) ~= "number" and type(mo) ~= "number" and type(d) ~= "number" and type(h) ~= "number" then return nil end
	return (tonumber(y) or 0) * 365 + (tonumber(mo) or 0) * 30 + (tonumber(d) or 0) + (tonumber(h) or 0) / 24
end

-- Our own guild's members, from the game's roster: list = online, offline = the rest last
-- online within OFFLINE_DAYS, most recent first.
function M.ReadOwn()
	local g = R.MyGuild()
	if not g then return nil end
	local total = Plain((GetNumGuildMembers())) or 0
	local list, offline, ranks = {}, {}, {}
	for i = 1, total do
		local ok, name, rank, rankIndex, level, _, zone, _, _, online, _, class = pcall(GetGuildRosterInfo, i)
		name = ok and R.Name(Plain(name))
		if name then
			rank, rankIndex = Plain(rank), Plain(rankIndex)
			if type(rankIndex) ~= "number" then rankIndex = nil end
			if rankIndex and not ranks[rankIndex] then ranks[rankIndex] = CleanRank(rank) end
			local m = { name = name, level = Plain(level), class = Plain(class), rank = rank, rankIndex = rankIndex }
			if Plain(online) then
				m.zone = Plain(zone)
				list[#list + 1] = m
			else
				m.days = DaysOffline(i) or false
				if not m.days or m.days <= M.OFFLINE_DAYS then offline[#offline + 1] = m end
			end
		end
	end
	table.sort(offline, function(a, b)
		if (a.days or 1e9) ~= (b.days or 1e9) then return (a.days or 1e9) < (b.days or 1e9) end
		return a.name < b.name
	end)
	M.guilds[g] = { list = list, offline = offline, online = #list, members = total, t = time(), own = true, ranks = ranks }
	if R.db and #list > 0 then   -- (a roster still loading lists nobody, not even us)
		Replace(g, list, offline)
		if next(ranks) then R.db.ranks[g] = ranks end
	end
	if not R.fullName then R.FindMyName() end
	return M.guilds[g]
end

-- This character's public guild note and roster index, or nil while the roster isn't in.
function M.MyNote()
	local me = R.Me()
	local total = Plain((GetNumGuildMembers())) or 0
	for i = 1, total do
		local ok, name, _, _, _, _, _, note = pcall(GetGuildRosterInfo, i)
		if ok and R.Name(Plain(name)) == me then return Plain(note) or "", i end
	end
	return nil
end

function M.CanEditNote()
	if not CanEditPublicNote then return false end
	local ok, can = pcall(CanEditPublicNote)
	return ok and Plain(can) and true or false
end

-- Writes this character's public guild note (31 bytes at most). True if the game took it.
function M.WriteNote(text)
	text = R.Cut(tostring(text or ""), 31)
	local guid = UnitGUID and Plain(UnitGUID("player"))
	if C_GuildInfo and C_GuildInfo.SetNote and guid then
		if pcall(C_GuildInfo.SetNote, guid, text, true) then return true end
	end
	local _, index = M.MyNote()
	if GuildRosterSetPublicNote and index then
		return (pcall(GuildRosterSetPublicNote, index, text))
	end
	return false
end

-- Is this player online? Everyone who shares professions runs Riket, and Riket says hello every
-- minute; the guilds' online lists cover the rest.
function M.IsOnline(name)
	if not name then return false end
	if name == R.Me() then return true end
	local p = R.peers[name]
	if p and time() - p.t <= R.PEER_FOR then return true end
	for g, e in pairs(M.guilds) do
		if M.Get(g) then
			for _, m in ipairs(e.list or {}) do
				if m.name == name then return true end
			end
		end
	end
	return false
end

-- A player's class (its file name, "MAGE"), from whatever Riket knows of them: the guilds'
-- online lists, the members kept between sessions, the professions board. Nil if none says.
function M.ClassOf(name)
	if not name then return nil end
	for _, e in pairs(M.guilds) do
		for _, m in ipairs(e.list or {}) do
			if m.name == name and m.class then return m.class end
		end
	end
	local k = R.db and R.db.roster[name]
	if type(k) == "table" and k.c then return k.c end
	local c = R.db and R.db.crafters[name]
	if type(c) == "table" and c.class then return c.class end
	return nil
end

-- A guild's entry if it is fresh enough to show, else nil.
function M.Get(guild)
	local e = M.guilds[guild]
	if e and (e.own or time() - e.t <= M.KEEP) then return e end
	return nil
end

function M.Ask()
	if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
end

local stamp = 0
function M.Send()
	if not R.ready or not R.IAmRelay() or not R.OtherGuildOnline() then return end
	local own = M.ReadOwn()
	if not own then return end
	local g = R.MyGuild()
	stamp = stamp % 999 + 1
	local head = ("O;%s;%d;99;99;%d;%d;"):format(g, stamp, own.online, own.members)
	local budget = R.MAX_BYTES - #head
	local parts, counts, cur = {}, {}, {}
	for _, m in ipairs(own.list) do
		local e = m.name .. "," .. (m.level or 0) .. "," .. R.ClassID(m.class)
		if #cur > 0 and #table.concat(cur, "/") + 1 + #e > budget then
			parts[#parts + 1], counts[#parts + 1] = table.concat(cur, "/"), #cur
			cur = {}
		end
		cur[#cur + 1] = e
	end
	parts[#parts + 1], counts[#parts + 1] = table.concat(cur, "/"), #cur   -- (nobody online still says so)
	local n = math.min(#parts, M.PARTS_MAX)
	local listed = 0
	for i = 1, n do
		R.Send(("O;%s;%d;%d;%d;%d;%d;%s"):format(g, stamp, i, n, own.online, own.members, parts[i]), "O" .. i)
		listed = listed + counts[i]
	end
	-- the ranks of the members just sent, one digit each, then the rank names
	local digits = {}
	for i = 1, listed do
		local ri = own.list[i].rankIndex
		digits[i] = (ri and ri >= 0 and ri <= 9) and tostring(ri) or "-"
	end
	R.Send(R.Cut(("G;%s;%d;%s"):format(g, stamp, table.concat(digits)), R.MAX_BYTES), "G")
	local names, last = {}, 0
	for i = 0, 9 do
		names[i + 1] = own.ranks[i] or ""
		if own.ranks[i] then last = i + 1 end
	end
	if last > 0 then R.Send(R.Cut("N;" .. g .. ";" .. table.concat(names, "/", 1, last), R.MAX_BYTES), "N") end
end

-- Who in our guild is offline, for the other guilds. Only the relay sends it, OFFLINE_GAP apart
-- at the closest, and only when the channel has nothing else to send.
local offStamp, lastOffline = 0, nil
function M.SendOffline()
	if not R.ready or not R.IAmRelay() or not R.OtherGuildOnline() then return end
	if lastOffline and GetTime() - lastOffline < M.OFFLINE_GAP then return end
	local own = M.ReadOwn()
	if not own or #own.list == 0 then return end
	lastOffline = GetTime()
	local g = R.MyGuild()
	offStamp = offStamp % 999 + 1
	local budget = R.MAX_BYTES - #("F;%s;%d;99;99;"):format(g, offStamp)
	local parts, cur = {}, {}
	for _, m in ipairs(own.offline) do
		local ri = m.rankIndex
		local e = m.name .. "," .. (m.level or 0) .. "," .. R.ClassID(m.class) .. "," ..
			((ri and ri >= 0 and ri <= 9) and tostring(ri) or "-") .. "," .. (m.days and math.floor(m.days) or "-")
		if #cur > 0 and #table.concat(cur, "/") + 1 + #e > budget then
			parts[#parts + 1] = table.concat(cur, "/")
			cur = {}
			if #parts == M.OFFLINE_PARTS_MAX then break end
		end
		cur[#cur + 1] = e
	end
	if #parts < M.OFFLINE_PARTS_MAX then parts[#parts + 1] = table.concat(cur, "/") end   -- (nobody offline still says so)
	for i = 1, #parts do
		R.Send(("F;%s;%d;%d;%d;%s"):format(g, offStamp, i, #parts, parts[i]), "F" .. i, true)
	end
end

-- Puts the G digits on the list they belong to (same sender, same round), once both are in.
local function ApplyRanks(g)
	local e, d = M.guilds[g], rankDigits[g]
	if not (e and d and not e.own and e.stamp == d.stamp and e.from == d.from) then return false end
	for i, m in ipairs(e.list) do m.rankIndex = tonumber(d.digits:sub(i, i)) end
	rankDigits[g] = nil
	return true
end

R.Handle("O", function(rest, who)
	local f = R.Split(rest, 7)
	if not f then return end
	local g = R.CleanGuild(f[1])
	local st, part, parts = tonumber(f[2]), tonumber(f[3]), tonumber(f[4])
	if not g or g == R.MyGuild() or not st or not part or not parts or part < 1 or part > parts or parts > M.PARTS_MAX then return end
	R.Heard(who, g)
	local a = assembling[g]
	if not a or a.stamp ~= st or a.from ~= who or a.parts ~= parts then
		a = { stamp = st, from = who, parts = parts, got = {}, n = 0 }
		assembling[g] = a
	end
	if a.got[part] then return end
	local list = {}
	for e in f[7]:gmatch("[^/]+") do
		local name, level, class = e:match("^([^,|]+),(%d+),(%d+)$")
		if name then list[#list + 1] = { name = name, level = tonumber(level), class = R.ClassFile(class) } end
	end
	a.got[part], a.n = list, a.n + 1
	if a.n < a.parts then return end
	local all = {}
	for i = 1, a.parts do
		for _, m in ipairs(a.got[i]) do all[#all + 1] = m end
	end
	M.guilds[g] = { list = all, online = tonumber(f[5]) or #all, members = tonumber(f[6]), t = time(), from = who,
		stamp = st, ranks = rankNames[g] }
	assembling[g] = nil
	ApplyRanks(g)
	for _, m in ipairs(all) do Keep(m, g, time()) end
	R.Changed("members")
end)

R.Handle("G", function(rest, who)
	local f = R.Split(rest, 3)
	if not f then return end
	local g, st = R.CleanGuild(f[1]), tonumber(f[2])
	if not g or g == R.MyGuild() or not st or not f[3]:match("^[%d%-]*$") then return end
	rankDigits[g] = { stamp = st, from = who, digits = f[3] }
	if ApplyRanks(g) then
		for _, m in ipairs(M.guilds[g].list) do Keep(m, g, time()) end
		R.Changed("members")
	end
end)

R.Handle("F", function(rest, who)
	local f = R.Split(rest, 5)
	if not f then return end
	local g = R.CleanGuild(f[1])
	local st, part, parts = tonumber(f[2]), tonumber(f[3]), tonumber(f[4])
	if not g or g == R.MyGuild() or not st or not part or not parts or part < 1 or part > parts or parts > M.OFFLINE_PARTS_MAX then return end
	local a = offAssembling[g]
	if not a or a.stamp ~= st or a.from ~= who or a.parts ~= parts then
		a = { stamp = st, from = who, parts = parts, got = {}, n = 0 }
		offAssembling[g] = a
	end
	if a.got[part] then return end
	local list = {}
	for e in f[5]:gmatch("[^/]+") do
		local name, level, class, rank, days = e:match("^([^,|]+),(%d+),(%d+),([%d%-]),([%d%-]+)$")
		days = tonumber(days)
		if name and (not days or days <= M.OFFLINE_DAYS) then
			list[#list + 1] = { name = name, level = tonumber(level), class = R.ClassFile(class), rankIndex = tonumber(rank), days = days or false }
		end
	end
	a.got[part], a.n = list, a.n + 1
	if a.n < a.parts then return end
	local all = {}
	for i = 1, a.parts do
		for _, m in ipairs(a.got[i]) do all[#all + 1] = m end
	end
	offAssembling[g] = nil
	local e = M.Get(g)
	Replace(g, e and e.list or {}, all)
	R.Changed("members")
end)

R.Handle("N", function(rest, who)
	local f = R.Split(rest, 2)
	if not f then return end
	local g = R.CleanGuild(f[1])
	if not g or g == R.MyGuild() then return end
	local names, i = {}, 0
	for name in (f[2] .. "/"):gmatch("([^/]*)/") do
		if i > 9 then break end
		names[i] = CleanRank(name)
		i = i + 1
	end
	rankNames[g] = names
	R.db.ranks[g] = names
	if M.guilds[g] and not M.guilds[g].own then M.guilds[g].ranks = names end
	R.Changed("members")
end)

-- Someone with Riket in another guild came online: our relay sends our roster soon.
local soon = false
R.OnChange(function(what, _, guild)
	if what ~= "peer" or guild == R.MyGuild() or soon then return end
	soon = true
	C_Timer.After(3 + math.random() * 4, function()
		soon = false
		M.Send()
		M.SendOffline()
	end)
end)

R.WhenReady(function()
	M.Ask()
	M.Prune()
	C_Timer.NewTicker(M.SEND_EVERY, function()
		M.Ask()
		C_Timer.After(2, M.Send)
	end)
	C_Timer.NewTicker(M.OFFLINE_EVERY, function() C_Timer.After(5, M.SendOffline) end)
end)

-- The roster changes often: read it once a second at most.
local rosterSoon = false
R.On("GUILD_ROSTER_UPDATE", function()
	if not R.db or rosterSoon then return end
	rosterSoon = true
	C_Timer.After(1, function()
		rosterSoon = false
		M.ReadOwn()
		R.Changed("members")
	end)
end)
