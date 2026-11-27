-- Professions: everyone's professions with their skill and link, across the network.
-- Each client reads its own professions from the character's skill lines, and the link to each
-- crafting profession when the player opens it (the game hands out a profession's link only
-- while its window is open, so a profession shows a link once its owner has opened it with
-- Riket). It sends them (P, then K for each link) when ready, after a change, every 20 minutes
-- and when someone asks (Q). Every client keeps what it heard for three weeks, so crafters who
-- are offline still show.
-- Recipes (1.4.4): Forever doesn't open other players' profession links, so Riket reads the
-- recipes each player knows when they open their profession window, and sends them (X) after
-- a change and when someone asks for them (W). Everyone keeps what they hear, so the recipes
-- of a player who is offline show too, once anyone has heard them.

local ADDON_NAME, ns = ...
local R = ns.R
local IsSecret, Plain = R.IsSecret, R.Plain

local P = {}
ns.Prof = P

P.KEEP = 21 * 86400
P.SEND_EVERY = 20 * 60
P.ANSWER_GAP = 60
P.RECIPE_GAP = 20          -- sending one profession's recipes again, at the soonest
P.RECIPE_ASK_GAP = 30      -- asking a player for the same recipes again, at the soonest
P.RECIPE_PARTS_MAX = 16
P.RECIPES_MAX = 3000

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
-- Recipe lists, as X carries them: sorted ids, the first whole, then each the step from the one
-- before, all in base 36. 150 recipes fit in about 450 bytes.
---------------------------------------------------------------------------

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function B36(n)
	if n == 0 then return "0" end
	local s = ""
	while n > 0 do
		local d = n % 36
		s = DIGITS:sub(d + 1, d + 1) .. s
		n = (n - d) / 36
	end
	return s
end

function P.Encode(ids)
	local sorted, seen = {}, {}
	for _, id in ipairs(ids) do
		id = tonumber(id)
		if id and id > 0 and id == math.floor(id) and not seen[id] then seen[id] = true sorted[#sorted + 1] = id end
	end
	table.sort(sorted)
	local out, prev = {}, 0
	for i, id in ipairs(sorted) do
		out[i] = B36(id - prev)
		prev = id
	end
	return table.concat(out, ","), #sorted
end

-- The ids, or nil if the text isn't a recipe list.
function P.Decode(s)
	if type(s) ~= "string" or s == "" or not s:match("^[0-9a-z,]+$") then return nil end
	local ids, prev = {}, 0
	for part in (s .. ","):gmatch("([^,]*),") do
		local step = tonumber(part, 36)
		if not step or step == 0 then return nil end
		prev = prev + step
		ids[#ids + 1] = prev
		if #ids > P.RECIPES_MAX then return nil end
	end
	return ids
end

-- A recipe's name, icon and link, from the game's spell data (a recipe's id is its spell's).
local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, v = pcall(fn, ...)
	if ok and not IsSecret(v) then return v end
	return nil
end

function P.RecipeName(id)
	local n = Try(C_Spell and C_Spell.GetSpellName, id)
	if type(n) ~= "string" or n == "" then n = Try(GetSpellInfo, id) end
	if type(n) ~= "string" or n == "" then
		local info = Try(C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo, id)
		n = type(info) == "table" and Plain(info.name) or nil
	end
	if type(n) ~= "string" or n == "" then return nil end
	return n
end

function P.RecipeIcon(id)
	local i = Try(C_Spell and C_Spell.GetSpellTexture, id) or Try(GetSpellTexture, id)
	if i then return i end
	local info = Try(C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo, id)
	return type(info) == "table" and Plain(info.icon) or nil
end

function P.RecipeLink(id)
	local l = Try(C_TradeSkillUI and C_TradeSkillUI.GetRecipeLink, id)
	if type(l) ~= "string" or l == "" then l = Try(C_Spell and C_Spell.GetSpellLink, id) end
	if type(l) ~= "string" or l == "" then l = Try(GetSpellLink, id) end
	return type(l) == "string" and l ~= "" and l or nil
end

-- The recipes the open profession window says we know, sorted.
local function ReadRecipeIDs()
	local T = C_TradeSkillUI
	local out, seen = {}, {}
	if T and type(T.GetAllRecipeIDs) == "function" and type(T.GetRecipeInfo) == "function" then
		local ids = Try(T.GetAllRecipeIDs)
		if type(ids) == "table" then
			for _, id in ipairs(ids) do
				id = tonumber(Plain(id))
				if id and not seen[id] then
					local info = Try(T.GetRecipeInfo, id)
					if type(info) == "table" and Plain(info.learned) then seen[id] = true out[#out + 1] = id end
				end
			end
		end
	end
	if #out == 0 and type(GetNumTradeSkills) == "function" and type(GetTradeSkillRecipeLink) == "function" then
		for i = 1, tonumber(Try(GetNumTradeSkills)) or 0 do
			local ok, _, kind = pcall(GetTradeSkillInfo, i)
			kind = ok and Plain(kind)
			if ok and kind ~= "header" and kind ~= "subheader" then
				local link = Try(GetTradeSkillRecipeLink, i)
				local id = type(link) == "string" and tonumber(link:match("enchant:(%d+)"))
				if id and not seen[id] then seen[id] = true out[#out + 1] = id end
			end
		end
	end
	table.sort(out)
	return out
end

function P.KeepRecipes(name, id, s, n)
	if not (R.db and name and id) then return end
	R.db.recipes[name] = R.db.recipes[name] or {}
	R.db.recipes[name][id] = { s = s, n = n, t = time() }
	R.Changed("recipes", name, id)
end

-- { s, n, t } for a player's profession, if anyone has heard it.
function P.RecipesOf(name, id)
	local r = R.db and R.db.recipes[name]
	return r and r[id]
end

local recipeStamp, recipeSent = 0, {}
-- Sends our recipes in a profession: at once when asked, after other messages after a change.
function P.SendRecipes(id, canWait)
	if not R.ready or not R.char then return end
	id = tonumber(id)
	if not id or (recipeSent[id] and time() - recipeSent[id] < P.RECIPE_GAP) then return end
	recipeSent[id] = time()
	recipeStamp = recipeStamp % 999 + 1
	local s = R.char.recipes[id]
	if type(s) ~= "string" or s == "" then
		R.Send(("X;%d;%d;0;0;"):format(id, recipeStamp), "X" .. id)
		return
	end
	local budget = R.MAX_BYTES - #("X;%d;%d;99;99;"):format(id, recipeStamp)
	local parts, cur = {}, ""
	for step in s:gmatch("[^,]+") do
		if cur ~= "" and #cur + 1 + #step > budget then
			parts[#parts + 1] = cur
			cur = ""
		end
		cur = cur == "" and step or (cur .. "," .. step)
	end
	parts[#parts + 1] = cur
	if #parts > P.RECIPE_PARTS_MAX then return end
	for i, part in ipairs(parts) do
		R.Send(("X;%d;%d;%d;%d;%s"):format(id, recipeStamp, i, #parts, part), "X" .. id .. ":" .. i, canWait)
	end
end

local asked = {}
-- Asks a player for their recipes in a profession. False if just asked.
function P.AskRecipes(name, id)
	local key = name .. ":" .. id
	if asked[key] and time() - asked[key] < P.RECIPE_ASK_GAP then return false end
	asked[key] = time()
	R.Send(("W;%s;%d"):format(name, id), "W" .. key)
	return true
end

R.Handle("W", function(rest, who)
	local f = R.Split(rest, 2)
	if not f or f[1] ~= R.Me() then return end
	local id = tonumber(f[2])
	if id then C_Timer.After(0.5 + math.random(), function() P.SendRecipes(id) end) end
end)

P.notRead = {}   -- ["name:skillLine"] = when the player said they haven't read those recipes yet
local recAssembling = {}
R.Handle("X", function(rest, who)
	local f = R.Split(rest, 5)
	if not f then return end
	local id, st, part, parts = tonumber(f[1]), tonumber(f[2]), tonumber(f[3]), tonumber(f[4])
	if not id or not st or not part or not parts or parts > P.RECIPE_PARTS_MAX then return end
	local key = who .. ":" .. id
	if parts == 0 then
		P.notRead[key] = time()
		R.Changed("recipes", who, id)
		return
	end
	if part < 1 or part > parts or not f[5]:match("^[0-9a-z,]+$") then return end
	local a = recAssembling[key]
	if not a or a.stamp ~= st or a.parts ~= parts then
		a = { stamp = st, parts = parts, got = {}, n = 0 }
		recAssembling[key] = a
	end
	if a.got[part] then return end
	a.got[part], a.n = f[5], a.n + 1
	if a.n < a.parts then return end
	recAssembling[key] = nil
	local s = table.concat(a.got, ",", 1, a.parts)
	local ids = P.Decode(s)
	if not ids then return end
	P.notRead[key] = nil
	P.KeepRecipes(who, id, s, #ids)
end)

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
				R.char.profs[id], R.char.links[id], R.char.recipes[id] = nil, nil, nil   -- unlearned
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
	local ids = ReadRecipeIDs()
	if #ids == 0 then R.Log("no recipes read from the", name, "window") end
	if #ids > 0 then
		local s, n = P.Encode(ids)
		if R.char.recipes[id] ~= s then
			R.char.recipes[id] = s
			P.KeepRecipes(R.Me(), id, s, n)
			P.SendRecipes(id, true)
		end
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
	for who, r in pairs(R.db.recipes) do   -- recipes go with their crafter
		if type(r) ~= "table" or not R.db.crafters[who] then R.db.recipes[who] = nil end
	end
end)

R.WhenReady(function()
	C_Timer.After(4, P.Ask)
	C_Timer.After(8 + math.random() * 6, function() P.SendMine(true) end)
	C_Timer.NewTicker(P.SEND_EVERY, function() P.SendMine(true) end)
end)
