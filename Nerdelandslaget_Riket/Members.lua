-- Members: who is online in every guild of the network. Our own guild comes live from the
-- game's roster; each other guild's relay sends its online members (O) every two minutes, and
-- at once when someone with Riket in another guild comes online. A guild nobody has sent for
-- five and a half minutes is shown as unknown.
-- Guild ranks (1.2) travel beside the list, so a client from before then still reads it: G is
-- one digit per member in the list's order (the rank's index, 0 = guild master), N the names.

local ADDON_NAME, ns = ...
local R = ns.R
local Plain = R.Plain

local M = {}
ns.Members = M

M.SEND_EVERY = 120
M.KEEP = 330
M.PARTS_MAX = 20

M.guilds = {}        -- [guild] = { list = { { name, level, class, zone, rank, rankIndex } }, online, members, t, own, ranks, stamp, from }
local assembling = {} -- [guild] = { stamp, from, parts, got, n }
local rankNames = {}  -- [guild] = { [index] = name }, from N
local rankDigits = {} -- [guild] = { stamp, from, digits }, from G, until the list it belongs to is in

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
	local names = (e and e.ranks) or rankNames[guild]
	return names and names[index]
end

-- Our own guild's online members, from the game's roster.
function M.ReadOwn()
	local g = R.MyGuild()
	if not g then return nil end
	local total = Plain((GetNumGuildMembers())) or 0
	local list, ranks = {}, {}
	for i = 1, total do
		local ok, name, rank, rankIndex, level, _, zone, _, _, online, _, class = pcall(GetGuildRosterInfo, i)
		name = ok and R.Name(Plain(name))
		if name and Plain(online) then
			rank, rankIndex = Plain(rank), Plain(rankIndex)
			if type(rankIndex) ~= "number" then rankIndex = nil end
			if rankIndex and not ranks[rankIndex] then ranks[rankIndex] = CleanRank(rank) end
			list[#list + 1] = { name = name, level = Plain(level), class = Plain(class), zone = Plain(zone), rank = rank, rankIndex = rankIndex }
		end
	end
	M.guilds[g] = { list = list, online = #list, members = total, t = time(), own = true, ranks = ranks }
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
	R.Changed("members")
end)

R.Handle("G", function(rest, who)
	local f = R.Split(rest, 3)
	if not f then return end
	local g, st = R.CleanGuild(f[1]), tonumber(f[2])
	if not g or g == R.MyGuild() or not st or not f[3]:match("^[%d%-]*$") then return end
	rankDigits[g] = { stamp = st, from = who, digits = f[3] }
	if ApplyRanks(g) then R.Changed("members") end
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
	end)
end)

R.WhenReady(function()
	M.Ask()
	C_Timer.NewTicker(M.SEND_EVERY, function()
		M.Ask()
		C_Timer.After(2, M.Send)
	end)
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
