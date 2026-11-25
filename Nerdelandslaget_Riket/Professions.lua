-- Professions: everyone's professions with their skill and link, across the network.
-- Each client reads its own professions from the character's skill lines, and the link to each
-- crafting profession when the player opens it (the game hands out a profession's link only
-- while its window is open, so a profession shows a link once its owner has opened it with
-- Riket). It sends them (P, then K for each link) when ready, after a change, every 20 minutes
-- and when someone asks (Q). Every client keeps what it heard for three weeks, so crafters who
-- are offline still show.

local ADDON_NAME, ns = ...
local R = ns.R
local IsSecret, Plain = R.IsSecret, R.Plain

local P = {}
ns.Prof = P

P.KEEP = 21 * 86400
P.SEND_EVERY = 20 * 60
P.ANSWER_GAP = 60

-- The professions, by skill line, with English names for when the game names none.
P.LINES = {
	{ 171, "Alchemy" }, { 164, "Blacksmithing" }, { 333, "Enchanting" }, { 202, "Engineering" },
	{ 182, "Herbalism" }, { 773, "Inscription" }, { 755, "Jewelcrafting" }, { 165, "Leatherworking" },
	{ 186, "Mining" }, { 393, "Skinning" }, { 197, "Tailoring" },
	{ 185, "Cooking" }, { 129, "First Aid" }, { 356, "Fishing" },
}
local ENGLISH = {}
for _, l in ipairs(P.LINES) do ENGLISH[l[1]] = l[2] end

local function SkillInfo(id)
	local S = C_SkillInfo
	if not S or type(S.GetSkillLineInfoByID) ~= "function" then return nil end
	local ok, info = pcall(S.GetSkillLineInfoByID, id)
	if ok and type(info) == "table" and not IsSecret(info) then return info end
	return nil
end

local names = {}
-- A profession's name in the player's language.
function P.Name(id)
	id = tonumber(id)
	if not id then return "?" end
	if names[id] then return names[id] end
	local info = SkillInfo(id)
	local n = info and (Plain(info.name) or Plain(info.skillLineDisplayName) or Plain(info.displayName))
	if type(n) ~= "string" or n == "" then n = ENGLISH[id] or ("#" .. id) end
	names[id] = n
	return n
end

-- Our skill line for a profession window's id (the window may number it otherwise).
function P.Canonical(id, name)
	if ENGLISH[id] then return id end
	if type(name) == "string" then
		for _, l in ipairs(P.LINES) do
			if P.Name(l[1]) == name or l[2] == name then return l[1] end
		end
	end
	return id
end

-- A link we can show and click: exactly one well-formed hyperlink.
function P.ValidLink(l)
	return type(l) == "string" and #l <= 240 and l:match("^|c[^|]+|H[^|]+|h%[[^|%]]+%]|h|r$") ~= nil
end

---------------------------------------------------------------------------
-- Our own professions
---------------------------------------------------------------------------

-- { [skillLine] = { rank, max } } for this character.
function P.ReadMine()
	local mine = {}
	for _, l in ipairs(P.LINES) do
		local id = l[1]
		local info = SkillInfo(id)
		if info then
			local rank = tonumber(Plain(info.rank) or Plain(info.skillRank) or Plain(info.currentRank))
			local max = tonumber(Plain(info.maxRank) or Plain(info.max) or Plain(info.skillMaxRank) or Plain(info.maxSkillRank))
			if rank and rank > 0 then
				mine[id] = { rank = rank, max = max or 0 }
			elseif rank == 0 then
				R.char.profs[id], R.char.links[id] = nil, nil   -- unlearned
			end
		end
	end
	-- what a profession window told us, where the skill lines say nothing of it
	for id, seen in pairs(R.char.profs) do
		if not mine[id] and type(seen) == "table" and (seen.rank or 0) > 0 then
			mine[id] = { rank = seen.rank, max = seen.max or 0 }
		end
	end
	return mine
end

-- Someone else's profession in the window (a link, a guild's list, an NPC's): not ours.
local function External()
	local T = C_TradeSkillUI
	for _, f in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsTradeSkillGuildMember", "IsNPCCrafting" }) do
		local fn = T and T[f]
		if type(fn) == "function" then
			local ok, v = pcall(fn)
			if ok and v then return true end
		end
	end
	return false
end

-- The profession window is open: its skill, and its link.
function P.ReadWindow()
	local T = C_TradeSkillUI
	if not R.char or not T or type(T.GetBaseProfessionInfo) ~= "function" or External() then return end
	local ok, base = pcall(T.GetBaseProfessionInfo)
	if not ok or type(base) ~= "table" or IsSecret(base) then return end
	local id = tonumber(Plain(base.professionID))
	if not id or id == 0 then return end
	local name = Plain(base.professionName)
	local rank, max = tonumber(Plain(base.skillLevel)), tonumber(Plain(base.maxSkillLevel))
	if type(T.GetChildProfessionInfo) == "function" then
		local okc, c = pcall(T.GetChildProfessionInfo)
		if okc and type(c) == "table" and not IsSecret(c) and (tonumber(Plain(c.skillLevel)) or 0) > 0 then
			rank, max = tonumber(Plain(c.skillLevel)), tonumber(Plain(c.maxSkillLevel))
		end
	end
	id = P.Canonical(id, name)
	local changed = false
	local saved = R.char.profs[id]
	if rank and rank > 0 and (not saved or saved.rank ~= rank or saved.max ~= max) then
		R.char.profs[id] = { rank = rank, max = max or 0, name = name }
		changed = true
	end
	if type(T.GetTradeSkillListLink) == "function" then
		local okl, link = pcall(T.GetTradeSkillListLink)
		if okl and not IsSecret(link) and P.ValidLink(link) and R.char.links[id] ~= link then
			R.char.links[id] = link
			changed = true
		end
	end
	if changed then
		P.SendMine(true)
		R.Changed("profs")
	end
end

local readSoon = false
local function ReadSoon()
	if readSoon then return end
	readSoon = true
	C_Timer.After(1, function()
		readSoon = false
		P.ReadWindow()
	end)
end
R.On("TRADE_SKILL_SHOW", ReadSoon)
R.On("TRADE_SKILL_LIST_UPDATE", ReadSoon)

---------------------------------------------------------------------------
-- The board
---------------------------------------------------------------------------

function P.Store(name, guild, class, level, profs, links)
	if not name or not guild then return end
	local c = R.db.crafters[name] or {}
	c.guild, c.class, c.level, c.profs, c.t = guild, class, level, profs, time()
	c.links = c.links or {}
	if links then
		for id, link in pairs(links) do if profs[id] then c.links[id] = link end end
	end
	for id in pairs(c.links) do if not profs[id] then c.links[id] = nil end end
	R.db.crafters[name] = c
	R.Changed("profs")
end

local lastSent = 0
function P.SendMine(force)
	local g = R.MyGuild()
	if not g or not R.db then return end
	if not force and time() - lastSent < 30 then return end
	lastSent = time()
	local mine = P.ReadMine()
	local list = {}
	for id, p in pairs(mine) do list[#list + 1] = id .. "." .. p.rank .. "." .. (p.max or 0) end
	table.sort(list)
	local _, class = UnitClass("player")
	class = Plain(class)
	local level = Plain(UnitLevel("player")) or 0
	P.Store(R.Me(), g, class, level, mine, R.char.links)
	if not R.ready then return end
	R.Send("P;" .. g .. ";" .. R.ClassID(class) .. ";" .. level .. ";" .. table.concat(list, ","), "P")
	for id in pairs(mine) do
		local link = R.char.links[id]
		if link and #link + 12 <= R.MAX_BYTES then R.Send("K;" .. id .. ";" .. link, "K" .. id) end
	end
end

function P.Ask()
	R.Send("Q", "Q")
end

R.Handle("P", function(rest, who)
	local f = R.Split(rest, 4)
	if not f then return end
	local g = R.CleanGuild(f[1])
	if not g then return end
	R.Heard(who, g)
	local profs = {}
	for id, rank, max in f[4]:gmatch("(%d+)%.(%d+)%.(%d+)") do
		profs[tonumber(id)] = { rank = tonumber(rank), max = tonumber(max) }
	end
	P.Store(who, g, R.ClassFile(f[2]), tonumber(f[3]), profs)
end)

R.Handle("K", function(rest, who)
	local f = R.Split(rest, 2)
	if not f then return end
	local id, link = tonumber(f[1]), f[2]
	local c = R.db.crafters[who]
	if not id or not c or not c.profs or not c.profs[id] or not P.ValidLink(link) then return end
	c.links = c.links or {}
	c.links[id] = link
	R.Changed("profs")
end)

-- Someone asks: we answer after a moment, once a minute at most.
local answering, lastAnswer = false, 0
R.Handle("Q", function()
	if answering or time() - lastAnswer < P.ANSWER_GAP then return end
	answering = true
	C_Timer.After(2 + math.random() * 6, function()
		answering = false
		lastAnswer = time()
		P.SendMine(true)
	end)
end)

-- Rows for the window: { id, profession, name, guild, class, level, rank, max, link, t, me },
-- one profession (skill line) or all (0), best skill first.
function P.Rows(filter)
	local rows, now = {}, time()
	for name, c in pairs(R.db.crafters) do
		if type(c) == "table" and type(c.profs) == "table" and now - (c.t or 0) <= P.KEEP then
			for id, p in pairs(c.profs) do
				if filter == 0 or filter == id then
					rows[#rows + 1] = { id = id, profession = P.Name(id), name = name, guild = c.guild, class = c.class,
						level = c.level, rank = p.rank or 0, max = p.max or 0, link = c.links and c.links[id], t = c.t,
						me = name == R.Me() }
				end
			end
		end
	end
	table.sort(rows, function(a, b)
		if a.profession ~= b.profession then return a.profession < b.profession end
		if a.rank ~= b.rank then return a.rank > b.rank end
		return a.name < b.name
	end)
	return rows
end

-- The professions anyone on the board has, for the filter.
function P.Known()
	local seen, out = {}, {}
	for _, row in ipairs(P.Rows(0)) do
		if not seen[row.id] then seen[row.id] = true out[#out + 1] = { id = row.id, name = row.profession } end
	end
	return out
end

R.On("ADDON_LOADED", function(name)
	if name ~= ADDON_NAME or not R.db then return end
	local now = time()
	for who, c in pairs(R.db.crafters) do
		if type(c) ~= "table" or now - (c.t or 0) > P.KEEP then R.db.crafters[who] = nil end
	end
end)

R.WhenReady(function()
	C_Timer.After(4, P.Ask)
	C_Timer.After(8 + math.random() * 6, function() P.SendMine(true) end)
	C_Timer.NewTicker(P.SEND_EVERY, function() P.SendMine(true) end)
end)
