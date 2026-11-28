-- Chat: one guild chat for every guild of the network. Each guild's relay repeats its /g to
-- the others (C), and every client shows the other guilds' lines in the chat windows that show
-- its own guild chat, in guild chat colour, as "[Guild] [Name]: text". The window keeps the
-- last lines of all of them.
-- A line the game hands us as a secret (in an encounter, under Midnight's rules) can't be read,
-- so it isn't repeated.

local ADDON_NAME, ns = ...
local R = ns.R
local IsSecret = R.IsSecret

local Chat = {}
ns.Chat = Chat

Chat.LOG_MAX = 200
Chat.REPEAT_FOR = 20     -- the same line from the same author again this soon is a repeat

local recent = {}        -- [author .. "\0" .. text] = time
local recentCount = 0

-- Another player's text, safe to show: every escape sequence is shown as typed but
-- well-formed links (items, spells, professions, players), which stay clickable.
function Chat.SafeText(s)
	s = tostring(s or ""):gsub("|", "||")
	s = s:gsub("||c([^|]-)||H([^|]-)||h(%[[^|]-%])||h||r", "|c%1|H%2|h%3|h|r")
	return s
end

-- [Name], clickable, in the player's class colour when Riket knows the class.
local function PlayerLink(name)
	local class = ns.Members and ns.Members.ClassOf(name)
	return "|Hplayer:" .. name .. "|h[" .. (class and R.ClassName(name, class) or name) .. "]|h"
end

function Chat.Format(guild, author, text)
	return "[" .. guild .. "] " .. PlayerLink(author) .. ": " .. Chat.SafeText(text)
end

function Chat.Color()
	local c = ChatTypeInfo and ChatTypeInfo.GUILD
	if type(c) == "table" and c.r then return c.r, c.g, c.b end
	return 0.25, 1, 0.25
end

local function Log(guild, author, text, other, protected)
	local log = R.db.chatLog
	local e = { t = time(), g = guild, a = author, x = text, o = other or nil, p = protected or nil }
	log[#log + 1] = e
	while #log > Chat.LOG_MAX do table.remove(log, 1) end
	R.Changed("chat", e)
end

-- The chat windows that show our guild chat (the first window if none says so).
local function GuildFrames()
	local out = {}
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local f = _G["ChatFrame" .. i]
		local types = f and f.messageTypeList
		if type(types) == "table" then
			for _, t in ipairs(types) do
				if t == "GUILD" then out[#out + 1] = f break end
			end
		end
	end
	if #out == 0 and DEFAULT_CHAT_FRAME then out[1] = DEFAULT_CHAT_FRAME end
	return out
end

function Chat.ShowInChat(guild, author, text)
	if not R.db.toChatFrame then return end
	local line = Chat.Format(guild, author, text)
	local r, g, b = Chat.Color()
	for _, f in ipairs(GuildFrames()) do pcall(f.AddMessage, f, line, r, g, b) end
end

-- Our own guild's /g: kept for the window, and repeated to the other guilds by our relay.
R.On("CHAT_MSG_GUILD", function(text, sender)
	if IsSecret(text) or IsSecret(sender) or type(text) ~= "string" or text == "" then return end
	local guild = R.MyGuild()
	local author = R.Name(sender)
	if not guild or not author or not R.db then return end
	-- Text the game hands addons only as a protected code (|K...|k) shows right here, but means
	-- nothing on another player's client: it is kept, not repeated.
	local protected = text:find("|K", 1, true) ~= nil
	Log(guild, author, text, false, protected)
	if protected then
		if not Chat.toldProtected then
			Chat.toldProtected = true
			R.Print("the game hides guild chat text from addons here, so Riket can't pass it to the other guilds.")
		end
		return
	end
	if R.ready and R.IAmRelay() and R.OtherGuildOnline() then
		local head = "C;" .. guild .. ";" .. author .. ";"
		R.Send(head .. R.Cut(text, R.MAX_BYTES - #head))
	end
end)

-- Another guild's /g, from its relay.
R.Handle("C", function(rest, who)
	local f = R.Split(rest, 3)
	if not f then return end
	local guild, author, text = R.CleanGuild(f[1]), f[2], f[3]
	if not guild or guild == R.MyGuild() or author == "" or author:find("[|;]") or text == "" then return end
	R.Heard(who, guild)
	local key, now = author .. "\0" .. text, time()
	if recent[key] and now - recent[key] < Chat.REPEAT_FOR then return end
	if recentCount > 200 then
		for k, t in pairs(recent) do if now - t >= Chat.REPEAT_FOR then recent[k] = nil recentCount = recentCount - 1 end end
	end
	if not recent[key] then recentCount = recentCount + 1 end
	recent[key] = now
	Log(guild, author, text, true)
	Chat.ShowInChat(guild, author, text)
end)

-- Writes to our own /g (from the window's box: a key press, which the game asks for).
function Chat.Say(text)
	if type(text) ~= "string" or text:match("^%s*$") or not IsInGuild() then return end
	local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
	local ok, err = pcall(send, text, "GUILD")
	if not ok then R.Log("guild chat failed:", err) end
end
