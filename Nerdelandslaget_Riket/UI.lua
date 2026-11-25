-- UI: Riket inside the guild window (J). Three tabs of its own on the window's right side,
-- under the window's own tabs: Members (who is online in every nerd guild), Professions and
-- Discord (where everyone sets their Discord name; Riket stays off until then). While the window
-- shows the guild's chat, the other nerd guilds' lines are merged into it. Plus the minimap
-- button and /riket.
-- Built from Blizzard's own templates so it looks like the rest of the game. Each template is
-- looked up before use; a client that lacks one gets a plain stand-in instead of an error.
-- Riket only draws on top of the guild window and listens to it; nothing of Blizzard's is
-- replaced. Errors in those parts are said once in chat, and /riket check shows what it sees.

local ADDON_NAME, ns = ...
local R, Chat, M, P = ns.R, ns.Chat, ns.Members, ns.Prof

local UI = {}
ns.UI = UI

local TITLE = "Nerdelandslaget: Riket"
local CREDIT = "Made by Neophyte"
UI.TITLE, UI.CREDIT = TITLE, CREDIT

local GREY = "|cff808080"

local function HasTemplate(t)
	if not (C_XMLUtil and C_XMLUtil.GetTemplateInfo) then return false end
	local ok, info = pcall(C_XMLUtil.GetTemplateInfo, t)
	return ok and info ~= nil
end
UI.HasTemplate = HasTemplate

local function IsTable(v) return type(v) == "table" end

local function Sound(kit)
	if PlaySound and SOUNDKIT and SOUNDKIT[kit] then pcall(PlaySound, SOUNDKIT[kit]) end
end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------

local function Text(parent, font, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false)
	return fs
end

-- Tooltip the Blizzard way: white title, gold lines, green instructions.
local function Tip(owner, title, lines, hints, anchor)
	GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
	GameTooltip:SetText(title or "", 1, 1, 1)
	for _, l in ipairs(lines or {}) do GameTooltip:AddLine(l, 1, 0.82, 0, true) end
	for _, l in ipairs(hints or {}) do GameTooltip:AddLine(l, 0.1, 1, 0.1, true) end
	GameTooltip:Show()
end
local function HideTip() GameTooltip:Hide() end

local function Button(parent, label, w)
	local b
	if HasTemplate("UIPanelButtonTemplate") then
		b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	else
		b = CreateFrame("Button", nil, parent)
		b:SetNormalFontObject("GameFontNormal")
		b:SetHighlightFontObject("GameFontHighlight")
		local bg = b:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.35, 0.05, 0.05, 0.9)
	end
	b:SetSize(w or 120, 22)
	b:SetText(label or "")
	return b
end

local function Check(parent, label, checked, onChange, tip)
	local b
	if HasTemplate("UICheckButtonTemplate") then
		b = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	else
		b = CreateFrame("CheckButton", nil, parent)
		b:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
		b:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
		b:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
		b:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
	end
	b:SetSize(24, 24)
	b.label = Text(b, "GameFontHighlightSmall")
	b.label:SetPoint("LEFT", b, "RIGHT", 0, 1)
	b.label:SetText(label)
	b:SetHitRectInsets(0, -((R.Plain(b.label:GetStringWidth()) or 0) + 4), 0, 0)
	b:SetChecked(checked and true or false)
	b:SetScript("OnClick", function(self)
		local on = self:GetChecked() and true or false
		Sound(on and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
		onChange(on)
	end)
	if tip then
		b:SetScript("OnEnter", function(self) Tip(self, label, { tip }) end)
		b:SetScript("OnLeave", HideTip)
	end
	return b
end

local function Input(parent)
	local e
	if HasTemplate("InputBoxTemplate") then
		e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
		e.pad = 0
	else
		e = CreateFrame("EditBox", nil, parent)
		e:SetFontObject(ChatFontNormal or GameFontHighlight)
		e:SetTextInsets(6, 6, 0, 0)
		local bg = e:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.5)
		e.pad = 6
	end
	e:SetAutoFocus(false)
	e:SetHeight(20)
	e:SetMaxLetters(255)
	return e
end

local function Menu(owner, build)
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(owner, function(_, root) build(root) end)
	end
end

-- The Blizzard dropdown; on a client without it, a panel button that opens the same menu.
local function Dropdown(parent, width, defaultText, build)
	if HasTemplate("WowStyle1DropdownTemplate") then
		local ok, dd = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
		if ok and IsTable(dd) and dd.SetupMenu then
			dd:SetWidth(width)
			if dd.SetDefaultText then dd:SetDefaultText(defaultText) end
			dd:SetupMenu(function(_, root) build(root) end)
			function dd:RiketUpdate()
				if self.IsMenuOpen and self:IsMenuOpen() then return end
				if self.GenerateMenu then self:GenerateMenu() end
			end
			return dd
		end
	end
	local b = Button(parent, defaultText, width)
	b:SetScript("OnClick", function(self) Menu(self, build) end)
	b.standIn = true
	function b:RiketUpdate(text) self:SetText(text or defaultText) end
	return b
end

-- Column headers drawn with the Who list's header art. With onSort, a column that names a sort
-- key ({ label, x, width, key }) is a button: click to sort, click again to turn the order round.
local HEADER_ART = "Interface\\FriendsFrame\\WhoFrame-ColumnTabs"
local SORT_ARROW = "Interface\\Buttons\\UI-SortArrow"
local function Headers(parent, cols, onSort)
	local headers = {}
	for _, c in ipairs(cols) do
		local sortable = onSort and c[4]
		local h = CreateFrame(sortable and "Button" or "Frame", nil, parent)
		h:SetSize(c[3], 24)
		h:SetPoint("TOPLEFT", c[2], 0)
		local l = h:CreateTexture(nil, "BACKGROUND")
		l:SetTexture(HEADER_ART)
		l:SetTexCoord(0, 0.078125, 0, 0.75)
		l:SetSize(5, 24)
		l:SetPoint("TOPLEFT")
		local r = h:CreateTexture(nil, "BACKGROUND")
		r:SetTexture(HEADER_ART)
		r:SetTexCoord(0.90625, 0.96875, 0, 0.75)
		r:SetSize(4, 24)
		r:SetPoint("TOPRIGHT")
		local m = h:CreateTexture(nil, "BACKGROUND")
		m:SetTexture(HEADER_ART)
		m:SetTexCoord(0.078125, 0.90625, 0, 0.75)
		m:SetPoint("TOPLEFT", l, "TOPRIGHT")
		m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
		local t = Text(h, "GameFontHighlightSmall")
		t:SetPoint("LEFT", 8, 0)
		t:SetText(c[1])
		h.label = t
		if sortable then
			h.key = c[4]
			local hl = h:CreateTexture(nil, "HIGHLIGHT")
			hl:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight")
			hl:SetBlendMode("ADD")
			hl:SetPoint("TOPLEFT", -2, 5)
			hl:SetPoint("BOTTOMRIGHT", 2, -7)
			h.arrow = h:CreateTexture(nil, "OVERLAY")
			h.arrow:SetTexture(SORT_ARROW)
			h.arrow:SetSize(9, 8)
			h.arrow:SetPoint("LEFT", t, "RIGHT", 3, -1)
			h.arrow:Hide()
			h:SetScript("OnClick", function()
				Sound("U_CHAT_SCROLL_BUTTON")
				onSort(c[4])
			end)
		end
		headers[#headers + 1] = h
	end
	return headers
end

-- Shows the arrow on the column the list is sorted by: down for highest first, up for lowest.
local function MarkSort(headers, key, desc)
	for _, h in ipairs(headers) do
		if h.arrow then
			h.arrow:SetShown(h.key == key)
			if desc then h.arrow:SetTexCoord(0, 0.5625, 0, 1) else h.arrow:SetTexCoord(0, 0.5625, 1, 0) end
		end
	end
end

-- Lays columns out over a width: spec = { { label, share, sortKey }, ... }.
local function Columns(spec, width)
	local cols, x = {}, 0
	for i, c in ipairs(spec) do
		local w = (i == #spec) and (width - x) or math.floor(width * c[2] + 0.5)
		cols[i] = { c[1], x, w, c[3] }
		x = x + w
	end
	return cols
end
UI.Columns = Columns

local function Cell(row, col, font)
	local fs = Text(row, font or "GameFontHighlightSmall")
	fs:SetPoint("LEFT", col[2] + 8, 0)
	fs:SetWidth(col[3] - 12)
	return fs
end

---------------------------------------------------------------------------
-- Lists: Blizzard's scroll box with the thin scroll bar, or a plain pooled list
---------------------------------------------------------------------------

local function SetupRow(row, rowH)
	row:SetHeight(rowH)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.stripe = row:CreateTexture(nil, "BACKGROUND")
	row.stripe:SetAllPoints()
	row.stripe:SetColorTexture(1, 1, 1, 0.035)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
end

local function FillRow(row, item, update)
	row.item = item
	row.stripe:SetShown((item.index or 1) % 2 == 0)
	update(row, item)
end

local function NativeList(holder, rowH, create, update)
	local box = CreateFrame("Frame", nil, holder, "WowScrollBoxList")
	local bar = CreateFrame("EventFrame", nil, holder, "MinimalScrollBar")
	holder.box, holder.bar = box, bar
	bar:SetPoint("TOPRIGHT", 0, -2)
	bar:SetPoint("BOTTOMRIGHT", 0, 2)
	box:SetPoint("TOPLEFT")
	box:SetPoint("BOTTOMRIGHT", -16, 0)
	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(rowH)
	view:SetElementInitializer("Button", function(row, item)
		if not row.riketMade then
			SetupRow(row, rowH)
			create(row)
			row.riketMade = true
		end
		FillRow(row, item, update)
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
	if ScrollUtil.AddManagedScrollBarVisibilityBehavior then
		ScrollUtil.AddManagedScrollBarVisibilityBehavior(box, bar,
			{ CreateAnchor("TOPLEFT", holder, "TOPLEFT", 0, 0), CreateAnchor("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -16, 0) },
			{ CreateAnchor("TOPLEFT", holder, "TOPLEFT", 0, 0), CreateAnchor("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0) })
	end
	return function(items)
		box:SetDataProvider(CreateDataProvider(items), ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
	end
end

local function PlainList(holder, rowH, create, update)
	local list = CreateFrame("Frame", nil, holder)
	list:SetAllPoints()
	list:SetClipsChildren(true)
	list.items, list.rows, list.offset = {}, {}, 0
	local bar = CreateFrame("Slider", nil, list)
	bar:SetOrientation("VERTICAL")
	bar:SetWidth(12)
	bar:SetPoint("TOPRIGHT", 0, -2)
	bar:SetPoint("BOTTOMRIGHT", 0, 2)
	bar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
	local track = bar:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	track:SetColorTexture(0, 0, 0, 0.35)
	bar:SetMinMaxValues(0, 0)
	bar:SetValueStep(1)
	bar:SetObeyStepOnDrag(true)
	bar:SetScript("OnValueChanged", function(_, v)
		v = math.floor(v + 0.5)
		if v ~= list.offset then list.offset = v list:Refresh() end
	end)
	function list:Refresh()
		local n = math.max(1, math.floor((R.Plain(self:GetHeight()) or 0) / rowH))
		local maxOff = math.max(0, #self.items - n)
		if self.offset > maxOff then self.offset = maxOff end
		bar:SetMinMaxValues(0, maxOff)
		bar:SetShown(maxOff > 0)
		if bar:GetValue() ~= self.offset then bar:SetValue(self.offset) end
		local width = (R.Plain(self:GetWidth()) or 0) - (maxOff > 0 and 16 or 0)
		for i = 1, n do
			local row = self.rows[i]
			if not row then
				row = CreateFrame("Button", nil, self)
				SetupRow(row, rowH)
				row:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
				create(row)
				self.rows[i] = row
			end
			row:SetWidth(width)
			local item = self.items[self.offset + i]
			if item then FillRow(row, item, update) row:Show() else row.item = nil row:Hide() end
		end
		for i = n + 1, #self.rows do self.rows[i]:Hide() end
	end
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(self, delta)
		local _, maxOff = bar:GetMinMaxValues()
		bar:SetValue(math.max(0, math.min(maxOff, self.offset - delta * 2)))
	end)
	list:SetScript("OnSizeChanged", function(self) self:Refresh() end)
	holder.plain = list
	return function(items) list.items = items list:Refresh() end
end

local function List(parent, rowH, create, update, emptyText)
	local holder = CreateFrame("Frame", nil, parent)
	local set, native
	if HasTemplate("WowScrollBoxList") and HasTemplate("MinimalScrollBar") and ScrollUtil
		and ScrollUtil.InitScrollBoxListWithScrollBar and CreateScrollBoxListLinearView and CreateDataProvider and CreateAnchor then
		local ok, fn = pcall(NativeList, holder, rowH, create, update)
		if ok then set, native = fn, true
		else
			R.Log("scroll box failed:", fn)
			if holder.box then holder.box:Hide() end
			if holder.bar then holder.bar:Hide() end
		end
	end
	if not set then set = PlainList(holder, rowH, create, update) end
	holder.native = native
	holder.empty = Text(holder, "GameFontDisable", "CENTER")
	holder.empty:SetPoint("TOPLEFT", 20, -40)
	holder.empty:SetPoint("TOPRIGHT", -20, -40)
	holder.empty:SetWordWrap(true)
	holder.empty:SetText(emptyText or "")
	function holder:SetItems(items)
		items = items or {}
		for i, it in ipairs(items) do it.index = i end
		self.items = items
		local ok, err = pcall(set, items)
		if not ok and self.native then   -- the scroll box refused: use the plain list from now on
			R.Log("scroll box failed:", err)
			self.native = false
			if self.box then self.box:Hide() end
			if self.bar then self.bar:Hide() end
			set = PlainList(self, rowH, create, update)
			set(items)
		end
		self.empty:SetShown(#items == 0)
	end
	return holder
end

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

-- Opens a link the way the chat window would (a profession's recipes, a player, an item).
local function OpenLink(link, button)
	local ref = type(link) == "string" and link:match("|H(.-)|h")
	if not ref then return end
	if IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
		ChatEdit_InsertLink(link)
		return
	end
	if SetItemRef then pcall(SetItemRef, ref, link, button or "LeftButton") end
end

-- Our own guild in guild-chat green, the others in gold.
local function GuildTag(g)
	if g == R.MyGuild() then return "|cff40ff40" .. tostring(g) .. "|r" end
	return "|cffffd100" .. tostring(g) .. "|r"
end

local function GuildLines()
	local lines = {}
	for _, g in ipairs(R.Guilds()) do
		local e = M.Get(g)
		lines[#lines + 1] = g .. ": " .. (e and (e.online .. " online") or "waiting for its list")
	end
	return lines
end


---------------------------------------------------------------------------
-- The panel: Riket's pages laid over the guild window's content
---------------------------------------------------------------------------

local frame          -- the panel inside the guild window, once built
local pages = {}
local J = {}         -- the guild window (J)
local CO = {}        -- the merged guild chat in the guild window
UI.J, UI.CO = J, CO

local PAGE_MEMBERS, PAGE_PROFS, PAGE_DISCORD = 1, 2, 3
UI.PAGE_MEMBERS, UI.PAGE_PROFS, UI.PAGE_DISCORD = PAGE_MEMBERS, PAGE_PROFS, PAGE_DISCORD
local PAGES = {
	{ key = "Members", label = "Members", icon = R.MEDIA .. "round64", tip = "Who is online in every nerd guild." },
	{ key = "Professions", label = "Professions", icon = "Interface\\Icons\\Trade_BlackSmithing", tip = "Everyone's professions, with links to the recipes." },
	{ key = "Discord", label = "Discord", icon = "Interface\\Icons\\INV_Misc_Note_01", tip = "Your Discord name. Riket needs it." },
}

local function Host() return _G.CommunitiesFrame end
UI.Host = Host

-- The guild window parts run inside Blizzard's frames: an error there is said once in chat
-- instead of failing silently.
local said = {}
local function Safe(what, fn, ...)
	local res = { pcall(fn, ...) }
	if res[1] then return unpack(res, 2) end
	J.lastError = what .. ": " .. tostring(res[2])
	R.Log("guild window", J.lastError)
	if not said[what] then
		said[what] = true
		R.Print("couldn't " .. what .. " in the guild window: " .. tostring(res[2]) .. "  (/riket check)")
	end
	return nil
end
UI.Safe = Safe

local function Status()
	if not frame then return end
	local parts = {}
	for _, g in ipairs(R.Guilds()) do
		local e = M.Get(g)
		local s = GuildTag(g) .. " "
		if e then
			s = s .. e.online .. (e.members and e.members > 0 and (" of " .. e.members) or "") .. " online"
		else
			s = s .. GREY .. "waiting for its list|r"
		end
		parts[#parts + 1] = s
	end
	if R.ready and not R.ChannelID() then parts[#parts + 1] = "|cffff8040No shared channel: only your own guild|r" end
	if not R.Discord() then parts[#parts + 1] = "|cffff8040Riket is off until you set your Discord name|r" end
	frame.status:SetText(table.concat(parts, "     "))
end

local function Select(i)
	if not pages[i] then i = PAGE_MEMBERS end
	if i ~= PAGE_DISCORD and not R.Discord() then i = PAGE_DISCORD end   -- nothing else until the Discord name is set
	R.db.tab = i
	for k, p in ipairs(pages) do p:SetShown(k == i) end
	local open = frame ~= nil and frame:IsShown()
	for k, t in ipairs(J.tabs or {}) do t:SetChecked(open and k == i) end
	if i == PAGE_MEMBERS then M.Ask() M.ReadOwn() end
	if pages[i].Refresh then pages[i]:Refresh() end
end
UI.Select = Select

---------------------------------------------------------------------------
-- Page 1: Members
---------------------------------------------------------------------------

local MEMBER_SPEC = { { "Name", 0.20, "name" }, { "Level", 0.07, "level" }, { "Guild", 0.18, "guild" },
	{ "Rank", 0.15, "rank" }, { "Discord", 0.18, "discord" }, { "Zone", 0.22, "zone" } }
local FIRST_DESC = { level = true }   -- a column's first click: highest level first, the rest A to Z

-- What a member is sorted by in a column; nil (unknown) always sorts last.
local function MemberValue(m, key, mine)
	if key == "level" then return (m.level and m.level > 0) and m.level or nil
	elseif key == "rank" then return m.rankIndex
	elseif key == "guild" then return m.guild == mine and "" or m.guild:lower()
	elseif key == "zone" then return (m.zone and m.zone ~= "") and m.zone:lower() or nil
	elseif key == "discord" then return m.discord and m.discord:lower() or nil
	end
	return m.name:lower()
end

local function SortMembers(items, key, desc)
	local mine = R.MyGuild()
	table.sort(items, function(a, b)
		local va, vb = MemberValue(a, key, mine), MemberValue(b, key, mine)
		if va ~= vb then
			if va == nil then return false end
			if vb == nil then return true end
			if desc then return va > vb end
			return va < vb
		end
		if a.guild ~= b.guild then return a.guild == mine or (b.guild ~= mine and a.guild < b.guild) end
		return a.name < b.name
	end)
end
UI.SortMembers = SortMembers

local function MemberMenu(row)
	local m = row.item
	if not m then return end
	Menu(row, function(root)
		root:CreateTitle(m.name)
		root:CreateButton("Whisper", function() R.Whisper(m.name) end)
		root:CreateButton("Invite to group", function() R.Invite(m.name) end)
	end)
end

local function BuildMembers(page, width)
	local cols = Columns(MEMBER_SPEC, width)
	page.headers = Headers(page, cols, function(key)
		local s = R.db.memberSort
		if s.key == key then s.desc = not s.desc
		else s.key, s.desc = key, FIRST_DESC[key] or false end
		page:Refresh()
	end)
	local list = List(page, 20, function(row)
		row.name = Cell(row, cols[1])
		row.level = Cell(row, cols[2])
		row.guild = Cell(row, cols[3])
		row.rank = Cell(row, cols[4])
		row.discord = Cell(row, cols[5])
		row.discord:SetTextColor(0.6, 0.65, 1)
		row.zone = Cell(row, cols[6])
		row.zone:SetTextColor(0.82, 0.82, 0.82)
		row:SetScript("OnClick", function(self, button)
			if not self.item then return end
			if button == "RightButton" then MemberMenu(self) else R.Whisper(self.item.name) end
		end)
		row:SetScript("OnEnter", function(self)
			local m = self.item
			if not m then return end
			local lines = { m.guild }
			if m.rank then lines[#lines + 1] = "Rank: " .. m.rank end
			if m.discord then lines[#lines + 1] = "Discord: " .. m.discord end
			if m.zone and m.zone ~= "" then lines[#lines + 1] = m.zone end
			Tip(self, m.name, lines, { "Click to whisper", "Right-click for more" })
		end)
		row:SetScript("OnLeave", HideTip)
	end, function(row, m)
		row.name:SetText(R.ClassName(m.name, m.class))
		row.level:SetText(m.level and m.level > 0 and m.level or "")
		row.guild:SetText(GuildTag(m.guild))
		row.rank:SetText(m.rank or "")
		row.discord:SetText(m.discord or "")
		row.zone:SetText(m.zone or "")
	end, "Nobody online yet. Members of the other guilds show once one of them with Riket is online.")
	list:SetPoint("TOPLEFT", 0, -26)
	list:SetPoint("BOTTOMRIGHT")
	page.list = list

	local hint = Text(page, "GameFontDisableSmall")
	hint:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 9)
	hint:SetText("Click a column to sort   ·   Click a name to whisper   ·   Right-click for more")

	function page:Refresh()
		local items = {}
		for _, g in ipairs(R.Guilds()) do
			local e = M.Get(g)
			if e then
				for _, m in ipairs(e.list) do
					items[#items + 1] = { name = m.name, level = m.level, class = m.class, zone = m.zone, guild = g,
						rank = m.rank or M.RankName(g, m.rankIndex), rankIndex = m.rankIndex, discord = R.DiscordOf(m.name) }
				end
			end
		end
		local s = R.db.memberSort
		SortMembers(items, s.key, s.desc)
		MarkSort(self.headers, s.key, s.desc)
		list:SetItems(items)
	end
end

---------------------------------------------------------------------------
-- Page 2: Professions
---------------------------------------------------------------------------

local PROF_SPEC = { { "Profession", 0.20 }, { "Name", 0.25 }, { "Guild", 0.21 }, { "Skill", 0.10 }, { "Link", 0.24 } }

local function BuildProfessions(page, width)
	local cols = Columns(PROF_SPEC, width)
	local filter
	local function FilterLabel()
		local f = R.db.profFilter or 0
		return f == 0 and "All professions" or P.Name(f)
	end
	filter = Dropdown(page, 180, "All professions", function(root)
		local function is(id) return (R.db.profFilter or 0) == id end
		local function set(id)
			R.db.profFilter = id
			page:FillList()
			if filter.standIn then filter:RiketUpdate(FilterLabel()) end
		end
		root:CreateRadio("All professions", is, set, 0)
		for _, k in ipairs(P.Known()) do root:CreateRadio(k.name, is, set, k.id) end
	end)
	filter:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -30)
	page.filter = filter

	Headers(page, cols)
	local list = List(page, 20, function(row)
		row.prof = Cell(row, cols[1], "GameFontNormalSmall")
		row.name = Cell(row, cols[2])
		row.guild = Cell(row, cols[3])
		row.skill = Cell(row, cols[4])
		row.link = CreateFrame("Button", nil, row)
		row.link:SetPoint("LEFT", cols[5][2] + 8, 0)
		row.link:SetSize(cols[5][3] - 12, 18)
		row.link:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row.link.text = Text(row.link, "GameFontHighlightSmall")
		row.link.text:SetPoint("LEFT")
		row.link.text:SetPoint("RIGHT")
		row.link:SetScript("OnClick", function(self, button)
			local item = row.item
			if item and item.link then OpenLink(item.link, button) end
		end)
		row.link:SetScript("OnEnter", function(self)
			local item = row.item
			if item and item.link then
				Tip(self, item.profession, { item.name .. ", " .. (item.max and item.max > 0 and (item.rank .. "/" .. item.max) or tostring(item.rank)) },
					{ "Click to see the recipes", "Shift-click to put the link in chat" })
			elseif item then
				Tip(self, "No link yet", { item.me and "Open this profession's window once, and Riket shares its link."
					or (item.name .. " hasn't opened this profession with Riket yet.") })
			end
		end)
		row.link:SetScript("OnLeave", HideTip)
		row:SetScript("OnClick", function(self, button)
			local item = self.item
			if not item or item.me then return end
			if button == "RightButton" then
				Menu(self, function(root)
					root:CreateTitle(item.name)
					root:CreateButton("Whisper", function() R.Whisper(item.name) end)
				end)
			else
				R.Whisper(item.name)
			end
		end)
		row:SetScript("OnEnter", function(self)
			local item = self.item
			if not item then return end
			local ago = R.Ago(item.t)
			local lines = { item.guild, "Heard " .. ago .. (ago == "now" and "" or " ago") }
			Tip(self, item.name, lines, not item.me and { "Click to whisper" } or nil)
		end)
		row:SetScript("OnLeave", HideTip)
	end, function(row, item)
		row.prof:SetText(item.profession)
		row.name:SetText(R.ClassName(item.name, item.class) .. (item.me and (" " .. GREY .. "(you)|r") or ""))
		row.guild:SetText(GuildTag(item.guild))
		row.skill:SetText(item.max and item.max > 0 and (item.rank .. "/" .. item.max) or tostring(item.rank))
		row.link.text:SetText(item.link or (GREY .. "-|r"))
	end, "No professions yet. They show as members with Riket come online.")
	list:SetPoint("TOPLEFT", 0, -26)
	list:SetPoint("BOTTOMRIGHT")
	page.list = list

	local ask = Button(page, "Ask everyone again", 150)
	ask:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 3)
	ask:SetScript("OnClick", function()
		P.Ask()
		P.SendMine(true)
	end)
	ask:SetScript("OnEnter", function(self) Tip(self, "Ask everyone again", { "Everyone online with Riket sends their professions." }) end)
	ask:SetScript("OnLeave", HideTip)
	page.ask = ask
	local hint = Text(page, "GameFontDisableSmall")
	hint:SetPoint("LEFT", ask, "RIGHT", 10, 0)
	hint:SetPoint("RIGHT", frame, "RIGHT", -180, 0)
	hint:SetText("Open each of your profession windows once, and Riket shares its link.")

	function page:FillList() list:SetItems(P.Rows(R.db.profFilter or 0)) end
	function page:Refresh()
		filter:RiketUpdate(FilterLabel())
		self:FillList()
	end
end


---------------------------------------------------------------------------
-- Page 3: Discord. Everyone sets their Discord name here; Riket stays off until then. Where
-- the guild lets members edit notes, one click puts it in the guild note too.
---------------------------------------------------------------------------

local function BuildDiscord(page, width)
	local textWidth = math.min(width - 28, 640)
	local head = Text(page, "GameFontNormalLarge")
	head:SetPoint("TOPLEFT", 14, -12)
	head:SetText("Discord")
	local intro = Text(page, "GameFontHighlight")
	intro:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -8)
	intro:SetWidth(textWidth)
	intro:SetWordWrap(true)
	intro:SetText("Everyone in the nerd guilds sets their Discord name here. Riket stays off until you have, and the others see it next to your character.")

	local label = Text(page, "GameFontNormal")
	label:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -18)
	label:SetText("Your Discord name")
	local input = Input(page)
	input:SetSize(240, 20)
	input:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 6, -8)
	local save = Button(page, SAVE or "Save", 100)
	save:SetPoint("LEFT", input, "RIGHT", 12, 0)
	local state = Text(page, "GameFontHighlightSmall")
	state:SetPoint("TOPLEFT", input, "BOTTOMLEFT", -6, -10)
	state:SetWidth(textWidth)
	state:SetWordWrap(true)

	local noteHead = Text(page, "GameFontNormal")
	noteHead:SetPoint("TOPLEFT", state, "BOTTOMLEFT", 0, -22)
	noteHead:SetText("Guild note")
	local note = Text(page, "GameFontHighlightSmall")
	note:SetPoint("TOPLEFT", noteHead, "BOTTOMLEFT", 0, -8)
	note:SetWidth(textWidth)
	local noteBtn = Button(page, "Put my Discord name in my guild note", 280)
	noteBtn:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -8)
	local noteInfo = Text(page, "GameFontDisableSmall")
	noteInfo:SetPoint("TOPLEFT", noteBtn, "BOTTOMLEFT", 0, -6)
	noteInfo:SetWidth(textWidth)
	noteInfo:SetWordWrap(true)

	local show = Check(page, "Show the other guilds' guild chat in my chat windows too", R.db.toChatFrame,
		function(on) R.db.toChatFrame = on end,
		"Their lines always show in the guild window's guild chat. This puts them in your normal chat windows as well.")
	show:SetPoint("TOPLEFT", noteInfo, "BOTTOMLEFT", -2, -22)

	local function Save()
		if UI.SaveDiscord(input:GetText()) then
			input:ClearFocus()
			page:Refresh()
		else
			state:SetText("|cffff4040At least two letters, please.|r")
		end
	end
	input:SetScript("OnEnterPressed", Save)
	input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	save:SetScript("OnClick", Save)
	noteBtn:SetScript("OnClick", function()
		local d = R.Discord()
		if not d then return end
		if M.WriteNote(d) then R.Print("Your guild note is now your Discord name.")
		else R.Print("The game didn't take the guild note.") end
		M.Ask()
		C_Timer.After(2, function() if page:IsShown() then page:Refresh() end end)
	end)
	page.input, page.save, page.state, page.note, page.noteBtn, page.noteInfo, page.show = input, save, state, note, noteBtn, noteInfo, show

	function page:Refresh()
		local d = R.Discord()
		if not input:HasFocus() then input:SetText(d or "") end
		if d then state:SetText("|cff40ff40Riket is on.|r Your Discord name is " .. d .. ".")
		else state:SetText("|cffff8040Riket is off until you set your Discord name.|r") end
		local current = M.MyNote()
		if current == nil then note:SetText("Your guild note: " .. GREY .. "loading|r")
		else note:SetText("Your guild note: " .. (current ~= "" and (current:gsub("|", "||")) or (GREY .. "(empty)|r"))) end
		local can = M.CanEditNote()
		local holds = d ~= nil and current ~= nil and current:lower():find(R.Cut(d, 31):lower(), 1, true) ~= nil
		noteBtn:SetEnabled(d ~= nil and can and not holds)
		if holds then noteInfo:SetText("Your guild note holds your Discord name.")
		elseif not can then noteInfo:SetText("Your rank can't edit guild notes. Ask an officer to put your Discord name there.")
		else noteInfo:SetText("It shows in the guild roster, also for those without Riket.") end
		show:SetChecked(R.db.toChatFrame and true or false)
	end
end

---------------------------------------------------------------------------
-- Building the panel
---------------------------------------------------------------------------

local function Build(panel)
	frame = panel
	local width = R.Plain(panel:GetWidth()) or 0
	if width < 600 then width = 814 end   -- (the guild window's usual width, while it has none yet)
	local listWidth = width - 34          -- inside the inset, less the scroll bar

	-- the strip under the title bar: who is online, and each page's controls on the right
	frame.status = Text(frame, "GameFontHighlightSmall")
	frame.status:SetPoint("TOPLEFT", 66, -31)
	frame.status:SetPoint("RIGHT", frame, "RIGHT", -200, 0)
	frame.status:SetHeight(26)
	frame.status:SetJustifyV("TOP")
	frame.status:SetWordWrap(true)

	-- the bottom bar: the credit on the right
	frame.credit = Text(frame, "GameFontDisableSmall", "RIGHT")
	frame.credit:SetPoint("BOTTOMRIGHT", -12, 9)
	frame.credit:SetText(TITLE .. " v" .. tostring(R.VERSION) .. "   ·   " .. CREDIT)

	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", 4, -4)
	content:SetPoint("BOTTOMRIGHT", frame.Inset, "BOTTOMRIGHT", -4, 4)
	for i, build in ipairs({ BuildMembers, BuildProfessions, BuildDiscord }) do
		local page = CreateFrame("Frame", nil, content)
		page:SetAllPoints()
		page:Hide()
		build(page, listWidth)
		pages[i] = page
	end
	UI.pages, UI.frame = pages, frame
	frame:SetScript("OnShow", function() UI.Refresh() end)
end

function UI.Refresh()
	if not frame or not frame:IsShown() then return end
	Status()
	local i = R.db.tab or PAGE_MEMBERS
	if pages[i] and pages[i]:IsShown() and pages[i].Refresh then pages[i]:Refresh() end
end

---------------------------------------------------------------------------
-- The guild window (J): Riket's tabs under the window's own on its right side. Clicking one
-- lays Riket's pages over the window's content; the window's own tabs, closing the window or a
-- new mode take them away again.
---------------------------------------------------------------------------

local KNOWN_TABS = { "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab" }
J.keys = {}

-- The window's own side tabs: the ones we know, plus any other check button whose key ends in
-- "Tab" (a client may have more than we know of).
function J.BlizzardTabs()
	local host = Host()
	local list, seen = {}, {}
	if not IsTable(host) then return list end
	local function Add(key, t)
		if IsTable(t) and not seen[t] and not t.riket then
			seen[t] = true
			J.keys[t] = key
			list[#list + 1] = t
		end
	end
	for _, key in ipairs(KNOWN_TABS) do Add(key, host[key]) end
	for key, v in pairs(host) do
		if type(key) == "string" and key:match("Tab$") and IsTable(v) and type(v.IsObjectType) == "function"
			and v:IsObjectType("CheckButton") then Add(key, v) end
	end
	return list
end

-- The lowest of the window's shown tabs, by where it actually sits (the window's order of
-- them is its own); in our list's order while they have no position yet.
function J.LowestTab()
	local shown, all = {}, true
	for _, t in ipairs(J.BlizzardTabs()) do
		if t:IsShown() then
			local b = R.Plain(t:GetBottom())
			shown[#shown + 1] = { t = t, b = b }
			if type(b) ~= "number" then all = false end
		end
	end
	if #shown == 0 then return nil end
	if not all then return shown[#shown].t end
	table.sort(shown, function(x, y) return x.b > y.b end)
	return shown[#shown].t
end

-- The gap between the window's own tabs, so ours line up with them.
function J.TabGap()
	local tabs = {}
	for _, t in ipairs(J.BlizzardTabs()) do
		local top, bottom = R.Plain(t:GetTop()), R.Plain(t:GetBottom())
		if t:IsShown() and type(top) == "number" and type(bottom) == "number" then tabs[#tabs + 1] = { top = top, bottom = bottom } end
	end
	table.sort(tabs, function(x, y) return x.top > y.top end)
	if #tabs >= 2 then
		local gap = tabs[1].bottom - tabs[2].top
		if gap >= 0 and gap < 60 then return gap end
	end
	return 17
end

function J.Minimized()
	local host = Host()
	if IsTable(host) and host.GetDisplayMode and COMMUNITIES_FRAME_DISPLAY_MODES and COMMUNITIES_FRAME_DISPLAY_MODES.MINIMIZED ~= nil then
		local ok, mode = pcall(host.GetDisplayMode, host)
		if ok and mode == COMMUNITIES_FRAME_DISPLAY_MODES.MINIMIZED then return true end
	end
	return false
end

-- The club and stream the window shows.
function J.Selection()
	local host = Host()
	if not IsTable(host) then return nil end
	local clubId, streamId
	if host.GetSelectedClubId then
		local ok, id = pcall(host.GetSelectedClubId, host)
		if ok then clubId = R.Plain(id) end
	end
	if host.GetSelectedStreamId then
		local ok, id = pcall(host.GetSelectedStreamId, host)
		if ok then streamId = R.Plain(id) end
	end
	return clubId, streamId
end

-- Is it the guild (not another community)? strict: no when we can't tell.
function J.GuildSelected(strict)
	local clubId = J.Selection()
	if not clubId or not (C_Club and C_Club.GetClubInfo and Enum and Enum.ClubType) then return not strict end
	local ok, info = pcall(C_Club.GetClubInfo, clubId)
	if not ok or type(info) ~= "table" or info.clubType == nil then return not strict end
	return info.clubType == Enum.ClubType.Guild
end

-- Is it the guild's own chat (not officer chat)?
function J.GuildStreamSelected()
	if not J.GuildSelected(true) then return false end
	local clubId, streamId = J.Selection()
	if not streamId then return true end   -- (no way to tell: the guild's first stream is its chat)
	if not (C_Club and C_Club.GetStreamInfo and Enum and Enum.ClubStreamType) then return true end
	local ok, info = pcall(C_Club.GetStreamInfo, clubId, streamId)
	if not ok or type(info) ~= "table" or info.streamType == nil then return true end
	return info.streamType == Enum.ClubStreamType.Guild
end

function J.ShowTabs()
	local host = Host()
	if not (R.db and R.MyGuild() and IsTable(host)) then return false end
	if J.Minimized() then return false end
	return J.GuildSelected(false)
end

function J.PlaceTabs()
	local host = Host()
	if not J.tabs or not IsTable(host) then return end
	local show = J.ShowTabs()
	local lowest, gap = J.LowestTab(), J.TabGap()
	for i, t in ipairs(J.tabs) do
		t:ClearAllPoints()
		local above = (i == 1) and lowest or J.tabs[i - 1]
		if above then t:SetPoint("TOP", above, "BOTTOM", 0, -gap)
		else t:SetPoint("TOPLEFT", host, "TOPRIGHT", 0, -40 - (i - 1) * (32 + gap)) end
		t:SetShown(show)
	end
	if not show then J.Hide(false) end
end

-- One of our side tabs, drawn like the window's own.
local function SideTab(i, spec)
	local host = Host()
	local t
	if HasTemplate("CommunitiesFrameTabTemplate") then
		t = CreateFrame("CheckButton", "NLRiketTab" .. spec.key, host, "CommunitiesFrameTabTemplate")
	else
		t = CreateFrame("CheckButton", "NLRiketTab" .. spec.key, host)
		t:SetSize(32, 32)
		local bg = t:CreateTexture(nil, "BACKGROUND")
		bg:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
		bg:SetSize(64, 64)
		bg:SetPoint("TOPLEFT", -3, 11)
		t:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		t:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
		local checked = t:GetCheckedTexture()
		if IsTable(checked) then checked:SetBlendMode("ADD") end
	end
	if IsTable(t.Icon) then t.Icon:SetTexture(spec.icon) else t:SetNormalTexture(spec.icon) end
	t.riket, t.tooltip = true, spec.label
	t:SetScript("OnClick", function()
		Sound("IG_CHARACTER_INFO_TAB")
		Safe("open " .. spec.label, J.TabClicked, i)
	end)
	t:SetScript("OnEnter", function(self) Tip(self, spec.label, { spec.tip }, nil, "ANCHOR_RIGHT") end)
	t:SetScript("OnLeave", HideTip)
	t:Hide()
	return t
end

-- The panel Riket's pages are built into: the guild window's size, its own background and
-- inset over the window's content, leaving the title bar, close button and portrait alone.
function J.Panel()
	local host = Host()
	local f = CreateFrame("Frame", "NLRiketFrame", host)
	f:SetAllPoints(host)
	f:SetFrameLevel((R.Plain(host:GetFrameLevel()) or 0) + 200)
	f.inJ = true
	local function Cover(l, t, r, b, h)
		local c = CreateFrame("Frame", nil, f)
		c:SetFrameLevel(R.Plain(f:GetFrameLevel()) or 0)
		c:SetPoint("TOPLEFT", l, t)
		if h then c:SetPoint("TOPRIGHT", r, t) c:SetHeight(h) else c:SetPoint("BOTTOMRIGHT", r, b) end
		c:EnableMouse(true)   -- the window's own controls under it stay out of reach
		local bg = c:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock", "REPEAT", "REPEAT")
		bg:SetHorizTile(true)
		bg:SetVertTile(true)
		return c
	end
	Cover(58, -21, -2, nil, 39)   -- the strip under the title bar, right of the portrait
	Cover(2, -60, -2, 2)          -- everything below it
	local inset
	if HasTemplate("InsetFrameTemplate") then
		inset = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
	else
		inset = CreateFrame("Frame", nil, f)
		local t = inset:CreateTexture(nil, "BACKGROUND")
		t:SetAllPoints()
		t:SetColorTexture(0, 0, 0, 0.45)
	end
	inset:SetPoint("TOPLEFT", 4, -60)
	inset:SetPoint("BOTTOMRIGHT", -6, 26)
	f.Inset = inset
	f:Hide()
	return f
end

function J.TabClicked(i)
	if frame and frame:IsShown() and R.db.tab == i then J.Hide(true) else J.Show(i) end
end

function J.Show(i)
	local host = Host()
	if not IsTable(host) or not J.ShowTabs() then return false end
	if not frame then Build(J.Panel()) end
	if not frame:IsShown() then
		J.restore = {}
		for _, t in ipairs(J.BlizzardTabs()) do
			if t:GetChecked() then
				J.restore[#J.restore + 1] = t
				t:SetChecked(false)
			end
		end
		frame:Show()
	end
	Select(i or R.db.tab or PAGE_MEMBERS)
	return true
end

-- restore: put back the window's own tab marks (Riket was closed from its own tab).
function J.Hide(restore)
	for _, t in ipairs(J.tabs or {}) do t:SetChecked(false) end
	if not frame or not frame:IsShown() then return end
	frame:Hide()
	if restore and J.restore then
		for _, t in ipairs(J.restore) do t:SetChecked(true) end
	end
	J.restore = nil
end

-- Opens the guild window (loading it the first time) on one of Riket's pages.
function J.Open(i)
	local host = Host()
	if not (IsTable(host) and host:IsShown()) then
		if ToggleGuildFrame then pcall(ToggleGuildFrame) end
		host = Host()
	end
	if IsTable(host) and not J.attached then J.Attach() end
	if not (IsTable(host) and host:IsShown()) then return false end
	J.PlaceTabs()
	return J.Show(i)
end

function J.Close()
	local host = Host()
	if IsTable(host) and host:IsShown() and ToggleGuildFrame then pcall(ToggleGuildFrame) end
	J.Hide(true)
end

function J.Attach()
	local host = Host()
	if J.attached or not IsTable(host) or not R.db then return end
	J.attached = true
	J.tabs = {}
	for i, spec in ipairs(PAGES) do J.tabs[i] = SideTab(i, spec) end
	UI.tabs = J.tabs
	for _, t in ipairs(J.BlizzardTabs()) do
		if t.HookScript then t:HookScript("OnClick", function() Safe("close Riket", J.Hide, false) end) end
	end
	host:HookScript("OnHide", function()
		Safe("close Riket", J.Hide, true)
		Safe("merge the guild chat", CO.Update)
	end)
	host:HookScript("OnShow", function()
		Safe("place its tabs", J.PlaceTabs)
		Safe("merge the guild chat", CO.Update)
		C_Timer.After(0, function() Safe("place its tabs", J.PlaceTabs) end)   -- once the tabs have their places
	end)
	for _, method in ipairs({ "SetDisplayMode", "SelectClub", "SelectStream" }) do
		if type(host[method]) == "function" then
			hooksecurefunc(host, method, function()
				if method == "SetDisplayMode" then Safe("close Riket", J.Hide, false) end
				Safe("place its tabs", J.PlaceTabs)
				Safe("merge the guild chat", CO.Update)
			end)
		end
	end
	Safe("merge the guild chat", CO.Attach, host)
	J.PlaceTabs()
end

R.On("ADDON_LOADED", function(name)
	if name == "Blizzard_Communities" then Safe("add its tabs", J.Attach) end
end)

---------------------------------------------------------------------------
-- The guild chat in the guild window, merged. While the window shows the guild's own chat,
-- Riket draws one chat in its place: the guild's lines as the game holds them, and the other
-- nerd guilds' lines in time order, as they come. The window's own box below still writes to /g.
---------------------------------------------------------------------------

local function ClassOf(name)
	for _, e in pairs(M.guilds) do
		for _, m in ipairs(e.list or {}) do
			if m.name == name then return m.class end
		end
	end
end

-- "[Name]: text" for our guild, "[Guild] [Name]: text" for the others, with the chat's own
-- time stamps when the player has them on.
function CO.Text(guild, name, text, class, t)
	local who = "|Hplayer:" .. name .. "|h[" .. (class and R.ClassName(name, class) or name) .. "]|h"
	local stamp = ""
	if CHAT_TIMESTAMP_FORMAT and BetterDate and t then
		local ok, s = pcall(BetterDate, CHAT_TIMESTAMP_FORMAT, math.floor(t))
		if ok and type(s) == "string" then stamp = s end
	end
	local tag = (guild and guild ~= R.MyGuild()) and ("|cffffd100[" .. guild .. "]|r ") or ""
	return stamp .. tag .. who .. ": " .. Chat.SafeText(text)
end

-- One of the game's guild chat messages as a line, or nil (deleted, or a secret in an encounter).
function CO.FromClub(m)
	if type(m) ~= "table" or m.destroyed then return nil end
	local content, author = m.content, m.author
	if R.IsSecret(content) or type(content) ~= "string" or type(author) ~= "table" then return nil end
	local name = R.Name(R.Plain(author.name))
	if not name then return nil end
	local epoch = type(m.messageId) == "table" and R.Plain(m.messageId.epoch)
	return { t = type(epoch) == "number" and epoch / 1e6 or time(), guild = R.MyGuild(), name = name, text = content,
		class = author.classID and R.ClassFile(author.classID) or ClassOf(name) }
end

-- The guild's chat as the game holds it, oldest first (its latest stretch of history).
local function ClubLines(clubId, streamId)
	if not (C_Club and C_Club.GetMessageRanges and C_Club.GetMessagesInRange) then return nil end
	local ranges = C_Club.GetMessageRanges(clubId, streamId)
	if type(ranges) ~= "table" then return nil end
	local out, last = {}, ranges[#ranges]
	if not last then return out end
	for _, m in ipairs(C_Club.GetMessagesInRange(clubId, streamId, last.oldestMessageId, last.newestMessageId) or {}) do
		local line = CO.FromClub(m)
		if line then out[#out + 1] = line end
	end
	return out
end

function CO.Attach(host)
	local chat = host.Chat
	local mf = IsTable(chat) and chat.MessageFrame
	if not IsTable(mf) then return end
	local bar = (IsTable(chat.ScrollBar) and chat.ScrollBar) or (IsTable(mf.ScrollBar) and mf.ScrollBar) or nil
	local box = CreateFrame("Frame", nil, chat)
	box:SetFrameLevel((R.Plain(mf:GetFrameLevel()) or 0) + 20)
	box:SetPoint("TOPLEFT", mf, "TOPLEFT")
	box:SetPoint("BOTTOMRIGHT", bar or mf, "BOTTOMRIGHT")
	box:EnableMouse(true)   -- the hidden chat under it gets no clicks
	local smf = CreateFrame("ScrollingMessageFrame", nil, box)
	smf:SetPoint("TOPLEFT", mf, "TOPLEFT")
	smf:SetPoint("BOTTOMRIGHT", mf, "BOTTOMRIGHT")
	smf:SetFontObject((mf.GetFontObject and mf:GetFontObject()) or ChatFontNormal or GameFontHighlight)
	smf:SetJustifyH("LEFT")
	smf:SetFading(false)
	smf:SetMaxLines(500)
	smf:SetHyperlinksEnabled(true)
	if smf.SetIndentedWordWrap then smf:SetIndentedWordWrap(true) end
	smf:EnableMouseWheel(true)
	smf:SetScript("OnMouseWheel", function(self, delta)
		if delta > 0 then self:ScrollUp() else self:ScrollDown() end
	end)
	smf:SetScript("OnHyperlinkClick", function(self, link, text, button)
		if SetItemRef then pcall(SetItemRef, link, text, button, self) end
	end)
	-- a scroll bar of the same kind where the window's own was
	local barTemplate = (HasTemplate("WowTrimScrollBar") and "WowTrimScrollBar") or (HasTemplate("MinimalScrollBar") and "MinimalScrollBar")
	if bar and barTemplate and ScrollUtil and ScrollUtil.InitScrollingMessageFrameWithScrollBar then
		local ours = CreateFrame("EventFrame", nil, box, barTemplate)
		ours:SetPoint("TOPLEFT", bar, "TOPLEFT")
		ours:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")
		if not pcall(ScrollUtil.InitScrollingMessageFrameWithScrollBar, smf, ours) then ours:Hide() end
		CO.ourBar = ours
	end
	box:Hide()
	CO.box, CO.smf, CO.mf, CO.bar, CO.chat = box, smf, mf, bar, chat
	chat:HookScript("OnShow", function() Safe("merge the guild chat", CO.Update) end)
	chat:HookScript("OnHide", function() Safe("merge the guild chat", CO.Update) end)
end

-- On while the window shows the guild's own chat and Riket runs; the window's chat comes back
-- the moment it isn't.
function CO.Update()
	if not CO.box then return end
	local host = Host()
	local visible = CO.chat.IsVisible and CO.chat:IsVisible()
	local on = R.ready and R.MyGuild() ~= nil and IsTable(host) and host:IsShown() and visible and J.GuildStreamSelected()
	if on then
		if not CO.box:IsShown() then
			CO.box:Show()
			CO.mf:SetAlpha(0)
			if CO.bar then CO.bar:SetAlpha(0) end
			CO.Fill()
		end
	elseif CO.box:IsShown() then
		CO.box:Hide()
		CO.mf:SetAlpha(1)
		if CO.bar then CO.bar:SetAlpha(1) end
	end
end

function CO.Fill()
	local smf = CO.smf
	smf:Clear()
	local clubId, streamId = J.Selection()
	local own = (clubId and streamId) and Safe("read the guild chat", ClubLines, clubId, streamId) or nil
	CO.clubMode = own ~= nil
	local lines = {}
	for i, l in ipairs(own or {}) do
		l.i = i
		lines[#lines + 1] = l
	end
	for _, e in ipairs(R.db.chatLog) do
		if e.o or not CO.clubMode then   -- the other guilds; our own too when the game's history isn't there
			lines[#lines + 1] = { t = e.t, guild = e.g, name = e.a, text = e.x, class = ClassOf(e.a), i = #lines + 1 }
		end
	end
	table.sort(lines, function(a, b)
		if a.t ~= b.t then return a.t < b.t end
		return a.i < b.i
	end)
	local r, g, b = Chat.Color()
	for k = math.max(1, #lines - 499), #lines do
		local l = lines[k]
		smf:AddMessage(CO.Text(l.guild, l.name, l.text, l.class, l.t), r, g, b)
	end
end

-- A line from Riket's chat log as it comes: the other guilds' (our own come from the game's
-- message event below, unless the game's history isn't there).
function CO.Add(e)
	if not (CO.box and CO.box:IsShown()) then return end
	if not e.o and CO.clubMode then return end
	local r, g, b = Chat.Color()
	CO.smf:AddMessage(CO.Text(e.g, e.a, e.x, ClassOf(e.a), e.t), r, g, b)
end

R.On("CLUB_MESSAGE_ADDED", function(clubId, streamId, messageId)
	if not (CO.box and CO.box:IsShown() and CO.clubMode) then return end
	local c, s = J.Selection()
	if clubId ~= c or streamId ~= s then return end
	local ok, m = pcall(C_Club.GetMessageInfo, clubId, streamId, messageId)
	local line = ok and CO.FromClub(m)
	if line then
		local r, g, b = Chat.Color()
		CO.smf:AddMessage(CO.Text(line.guild, line.name, line.text, line.class, line.t), r, g, b)
	end
end)

R.On("CLUB_MESSAGE_HISTORY_RECEIVED", function(clubId, streamId)
	if not (CO.box and CO.box:IsShown()) then return end
	local c, s = J.Selection()
	if clubId == c and streamId == s then Safe("merge the guild chat", CO.Fill) end
end)

---------------------------------------------------------------------------
-- Opening Riket, and keeping it current
---------------------------------------------------------------------------

function UI.Open(i)
	if not R.db then return end
	if not R.MyGuild() then
		R.Print("Riket is for the guilds with \"nerd\" in their name.")
		return
	end
	if not Safe("open Riket", J.Open, i) then
		R.Print("couldn't open Riket in the guild window (J). /riket check tells what it sees.")
	end
end

function UI.Toggle()
	if frame and frame:IsShown() then J.Close() else UI.Open() end
end

R.OnChange(function(what, e)
	if what == "guild" or what == "ready" or what == "discord" then
		Safe("place its tabs", J.PlaceTabs)
		Safe("merge the guild chat", CO.Update)
	end
	if what == "needsDiscord" then UI.AskDiscord() end
	if what == "chat" and e then Safe("merge the guild chat", CO.Add, e) end
	if not frame or not frame:IsShown() then return end
	if what == "members" or what == "profs" or what == "peer" or what == "ready" or what == "guild" or what == "discord" then
		UI.Refresh()
	end
end)

---------------------------------------------------------------------------
-- The Discord name: asked for at login when it isn't set, set in the Discord tab
---------------------------------------------------------------------------

if type(StaticPopupDialogs) == "table" then
	StaticPopupDialogs.NLRIKET_DISCORD = {
		text = TITLE .. "\n\nRiket needs your Discord name before it starts. Set it in the Discord tab of the guild window (J).",
		button1 = "Open the Discord tab",
		button2 = LATER or "Later",
		OnAccept = function() UI.Open(PAGE_DISCORD) end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
end

function UI.SaveDiscord(text)
	local was = R.Discord()
	if not R.SetDiscord(text) then return false end
	if was then R.Print("Discord name changed to " .. R.Discord() .. ".")
	else R.Print("Discord name set to " .. R.Discord() .. ". Riket is starting.") end
	UI.Refresh()
	return true
end

-- At login when the Discord name isn't set: once per session.
function UI.AskDiscord()
	if UI.askedDiscord or not R.MyGuild() then return end
	UI.askedDiscord = true
	if StaticPopup_Show and type(StaticPopupDialogs) == "table" and StaticPopupDialogs.NLRIKET_DISCORD then
		StaticPopup_Show("NLRIKET_DISCORD")
	end
	R.Print("set your Discord name in the Discord tab of the guild window (J) to start Riket.")
end

---------------------------------------------------------------------------
-- Minimap button, the standard round kind: left-click opens, drag slides it round the rim,
-- right-click for a menu. The game's addon list on the minimap gets an entry too.
---------------------------------------------------------------------------

local function MapTip(owner, canDrag)
	local hints = { "Click to open", "Right-click for a menu" }
	if canDrag then hints[#hints + 1] = "Drag to move" end
	GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
	GameTooltip:SetText(TITLE, 1, 1, 1)
	for _, l in ipairs(GuildLines()) do GameTooltip:AddLine(l, 1, 0.82, 0) end
	for _, l in ipairs(hints) do GameTooltip:AddLine(l, 0.1, 1, 0.1) end
	GameTooltip:AddLine(CREDIT, 0.5, 0.5, 0.5)
	GameTooltip:Show()
end
UI.MapTip = MapTip

local function MapMenu(owner)
	Menu(owner, function(root)
		root:CreateTitle(TITLE)
		root:CreateButton("Members", function() UI.Open(1) end)
		root:CreateButton("Professions", function() UI.Open(2) end)
		root:CreateButton("Discord", function() UI.Open(3) end)
		root:CreateButton("Hide the minimap button", function()
			R.db.mapButton = false
			UI.MapButton()
			R.Print("Minimap button hidden. /riket button brings it back.")
		end)
	end)
end

local mb
local function PlaceButton()
	local mm = _G.Minimap
	local a = math.rad(R.db.mapAngle or 200)
	local w = R.Plain(mm:GetWidth()) or 140
	local r = w / 2 + 5
	mb:ClearAllPoints()
	mb:SetPoint("CENTER", mm, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

function UI.MapButton()
	local mm = _G.Minimap
	if type(mm) ~= "table" then return end
	if not mb then
		mb = CreateFrame("Button", "NLRiketMapButton", mm)
		mb:SetSize(31, 31)
		mb:SetFrameStrata("MEDIUM")
		mb:SetFrameLevel(8)
		mb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		mb:RegisterForDrag("LeftButton")
		mb:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
		local bg = mb:CreateTexture(nil, "BACKGROUND")
		bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
		bg:SetSize(24, 24)
		bg:SetPoint("CENTER")
		local icon = mb:CreateTexture(nil, "ARTWORK")
		icon:SetTexture(R.MEDIA .. "round64")
		icon:SetSize(20, 20)
		icon:SetPoint("CENTER")
		local ring = mb:CreateTexture(nil, "OVERLAY")
		ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
		ring:SetSize(50, 50)
		ring:SetPoint("TOPLEFT")
		mb:SetScript("OnClick", function(self, button)
			if button == "RightButton" then MapMenu(self) else UI.Toggle() end
		end)
		mb:SetScript("OnDragStart", function(self)
			self:SetScript("OnUpdate", function()
				local mx, my = mm:GetCenter()
				mx, my = R.Plain(mx), R.Plain(my)
				if not (mx and my) then return end
				local s = R.Plain(mm:GetEffectiveScale()) or 1
				local cx, cy = GetCursorPosition()
				R.db.mapAngle = math.floor(math.deg(math.atan2(cy / s - my, cx / s - mx)) + 0.5) % 360
				PlaceButton()
			end)
		end)
		mb:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
		mb:SetScript("OnEnter", function(self) MapTip(self, true) end)
		mb:SetScript("OnLeave", HideTip)
	end
	mb:SetShown(R.db.mapButton)
	PlaceButton()
end

-- The addon list under the minimap (named in the .toc).
function NLRiket_OnAddonCompartmentClick()
	UI.Toggle()
end
function NLRiket_OnAddonCompartmentEnter(_, owner)
	if IsTable(owner) then MapTip(owner, false) end
end
function NLRiket_OnAddonCompartmentLeave()
	HideTip()
end

R.On("PLAYER_LOGIN", function()
	if R.db then UI.MapButton() end
	local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_Communities")
	if loaded then Safe("add its tabs", J.Attach) end
end)


---------------------------------------------------------------------------
-- /riket
---------------------------------------------------------------------------

-- What Riket sees of the guild window, for when something there doesn't show.
local function Check()
	local host = Host()
	R.Print(("guild window %s, Riket attached %s, open %s"):format(IsTable(host) and "loaded" or "not loaded yet",
		tostring(J.attached == true), tostring(IsTable(host) and host:IsShown())))
	if IsTable(host) then
		local names = {}
		for _, t in ipairs(J.BlizzardTabs()) do
			names[#names + 1] = (J.keys[t] or "?") .. (t:IsShown() and "" or " (hidden)")
		end
		R.Print("its tabs: " .. (#names > 0 and table.concat(names, ", ") or "none found"))
		local lowest = J.LowestTab()
		R.Print(("Riket's tabs under %s, shown %s; size %s x %s, small mode %s, guild chosen %s"):format(
			tostring(lowest and J.keys[lowest]), tostring(J.tabs and J.tabs[1] and J.tabs[1]:IsShown()),
			tostring(R.Plain(host:GetWidth())), tostring(R.Plain(host:GetHeight())), tostring(J.Minimized()), tostring(J.GuildSelected(true))))
		R.Print(("guild chat merged %s (the game's history %s), guild chat chosen %s"):format(
			tostring(CO.box ~= nil and CO.box:IsShown()), tostring(CO.clubMode == true), tostring(J.GuildStreamSelected())))
	end
	R.Print(("guild %s, Discord %s, Riket %s"):format(tostring(R.MyGuild()), tostring(R.Discord()), R.ready and "on" or "off"))
	if J.lastError then R.Print("last error: " .. J.lastError) end
end
UI.Check = Check

SLASH_NLRIKET1, SLASH_NLRIKET2 = "/riket", "/nll"
SlashCmdList.NLRIKET = function(msg)
	local cmd = strtrim(msg or ""):lower()
	if cmd == "" then UI.Toggle()
	elseif cmd == "members" or cmd == "medlemmer" then UI.Open(PAGE_MEMBERS)
	elseif cmd == "professions" or cmd == "prof" or cmd == "yrker" then UI.Open(PAGE_PROFS)
	elseif cmd == "discord" or cmd == "note" then UI.Open(PAGE_DISCORD)
	elseif cmd == "check" then Check()
	elseif cmd == "button" then
		R.db.mapButton = not R.db.mapButton
		UI.MapButton()
	elseif cmd == "debug" then
		R.db.debug = not R.db.debug
		R.Print("debug " .. (R.db.debug and "on" or "off"))
	elseif cmd == "status" then
		R.Print(("guild %s, Discord %s, channel %s, relay for my guild: %s"):format(tostring(R.MyGuild()), tostring(R.Discord()),
			tostring(R.ChannelID()), tostring(R.MyGuild() and R.Relay(R.MyGuild()))))
		for name, p in pairs(R.peers) do
			R.Print(("  %s <%s> %s, heard %s ago"):format(name, p.guild, p.version or "?", R.Ago(p.t)))
		end
	else
		R.Print("/riket  opens Riket in the guild window (J)   ·   /riket members | professions | discord | check | button | status | debug")
		R.Print(GREY .. TITLE .. " v" .. tostring(R.VERSION) .. "   ·   " .. CREDIT .. "|r")
	end
end
