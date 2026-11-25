-- UI: Riket's pages (Guild chat, Members, Professions), the Discord name, its minimap button
-- and /riket. Riket lives in the guild window (J) as a tab of its own on the window's side;
-- only where that window can't hold it does it get a window of its own.
-- Built from Blizzard's own templates so it looks like the rest of the game: the portrait
-- window, an inset, tabs along the bottom, panel buttons, a check button, an input box, the
-- dropdown and the scroll box. Each template is looked up before use; a client that lacks one
-- gets a plain stand-in instead of an error.

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
-- The window
---------------------------------------------------------------------------

local frame, content, lock, setup
local tabs, pages = {}, {}
local J = {}   -- the guild window (J), filled in further down
local WIDTH, HEIGHT = 740, 500
local TAB_TEMPLATE
local TAB_LABELS = { "Guild chat", "Members", "Professions" }

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
	if #parts == 0 then parts[1] = GREY .. "Not in a guild of the network|r" end
	if R.ready and not R.ChannelID() then parts[#parts + 1] = "|cffff8040No shared channel: only your own guild|r" end
	frame.status:SetText(table.concat(parts, "     "))
end

-- The Blizzard portrait window, or a plain stand-in with the same parts.
local function Shell()
	local f
	if HasTemplate("ButtonFrameTemplate") then
		f = CreateFrame("Frame", "NLRiketFrame", UIParent, "ButtonFrameTemplate")
		if f.SetTitle then f:SetTitle(TITLE)
		elseif IsTable(f.TitleContainer) and IsTable(f.TitleContainer.TitleText) then f.TitleContainer.TitleText:SetText(TITLE) end
		local path = R.MEDIA .. "portrait128"
		local shown = f.SetPortraitToAsset and pcall(f.SetPortraitToAsset, f, path)
		if not shown then
			local p = IsTable(f.PortraitContainer) and f.PortraitContainer.portrait or f.portrait
			if IsTable(p) then p:SetTexture(path) end
		end
		if IsTable(f.CloseButton) then f.CloseButton:SetScript("OnClick", function() f:Hide() end) end
		f.native = true
	else
		f = CreateFrame("Frame", "NLRiketFrame", UIParent, HasTemplate("BackdropTemplate") and "BackdropTemplate" or nil)
		if f.SetBackdrop and BACKDROP_DIALOG_32_32 then f:SetBackdrop(BACKDROP_DIALOG_32_32) end
		local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
		bg:SetPoint("TOPLEFT", 4, -4)
		bg:SetPoint("BOTTOMRIGHT", -4, 4)
		bg:SetColorTexture(0.07, 0.07, 0.08, 0.96)
		local title = Text(f, "GameFontNormal", "CENTER")
		title:SetPoint("TOP", 0, -8)
		title:SetText(TITLE)
		local portrait = f:CreateTexture(nil, "OVERLAY")
		portrait:SetTexture(R.MEDIA .. "portrait128")
		portrait:SetSize(58, 58)
		portrait:SetPoint("TOPLEFT", -4, 6)
		local close
		if HasTemplate("UIPanelCloseButton") then
			close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
		else
			close = CreateFrame("Button", nil, f)
			close:SetSize(28, 28)
			close:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
			close:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
			close:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
		end
		close:SetPoint("TOPRIGHT", 0, 0)
		close:SetScript("OnClick", function() f:Hide() end)
	end
	if not IsTable(f.Inset) then
		local inset = CreateFrame("Frame", nil, f)
		local t = inset:CreateTexture(nil, "BACKGROUND")
		t:SetAllPoints()
		t:SetColorTexture(0, 0, 0, 0.45)
		f.Inset = inset
	end
	f.Inset:ClearAllPoints()
	f.Inset:SetPoint("TOPLEFT", 4, -60)
	f.Inset:SetPoint("BOTTOMRIGHT", -6, 26)
	return f
end

local function MarkTab(i)
	if TAB_TEMPLATE and PanelTemplates_SetTab then
		pcall(PanelTemplates_SetTab, frame, i)
	else
		for k, b in ipairs(tabs) do b:SetEnabled(k ~= i) end
	end
end

local function Select(i)
	if not pages[i] then i = 1 end
	R.db.tab = i
	MarkTab(i)
	for k, p in ipairs(pages) do p:SetShown(k == i) end
	if i == 2 then M.Ask() M.ReadOwn() end
	if pages[i].Refresh then pages[i]:Refresh() end
end

---------------------------------------------------------------------------
-- Page 1: Guild chat
---------------------------------------------------------------------------

local function ChatLine(e)
	return GREY .. date("%H:%M", e.t) .. "|r " .. Chat.Format(e.g, e.a, e.x)
end

local function BuildChat(page)
	local smf = CreateFrame("ScrollingMessageFrame", nil, page)
	smf:SetPoint("TOPLEFT", 6, -4)
	smf:SetPoint("BOTTOMRIGHT", -22, 4)
	smf:SetFontObject(ChatFontNormal or GameFontHighlight)
	smf:SetJustifyH("LEFT")
	smf:SetFading(false)
	smf:SetMaxLines(Chat.LOG_MAX)
	smf:SetHyperlinksEnabled(true)
	if smf.SetIndentedWordWrap then smf:SetIndentedWordWrap(true) end
	smf:EnableMouseWheel(true)
	smf:SetScript("OnMouseWheel", function(self, delta)
		if delta > 0 then self:ScrollUp() else self:ScrollDown() end
	end)
	smf:SetScript("OnHyperlinkClick", function(self, link, text, button)
		if SetItemRef then pcall(SetItemRef, link, text, button, self) end
	end)
	page.smf = smf
	if HasTemplate("MinimalScrollBar") and ScrollUtil and ScrollUtil.InitScrollingMessageFrameWithScrollBar then
		local bar = CreateFrame("EventFrame", nil, page, "MinimalScrollBar")
		bar:SetPoint("TOPLEFT", smf, "TOPRIGHT", 8, 0)
		bar:SetPoint("BOTTOMLEFT", smf, "BOTTOMRIGHT", 8, 0)
		if not pcall(ScrollUtil.InitScrollingMessageFrameWithScrollBar, smf, bar) then bar:Hide() end
	end

	-- the input box sits in the window's bottom bar, left of the credit
	local input = Input(page)
	input:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 4)
	input:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -175, 4)
	local ph = Text(input, "GameFontDisable")
	ph:SetPoint("LEFT", input.pad + 2, 0)
	ph:SetText("Write to your guild chat and press Enter")
	local function Placeholder() ph:SetShown(input:GetText() == "" and not input:HasFocus()) end
	input:HookScript("OnEditFocusGained", Placeholder)
	input:HookScript("OnEditFocusLost", Placeholder)
	input:HookScript("OnTextChanged", Placeholder)
	input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	input:SetScript("OnEnterPressed", function(self)
		local t = self:GetText()
		if t ~= "" then Chat.Say(t) end
		self:SetText("")
		self:ClearFocus()
	end)
	page.input = input

	-- the check button sits top right, under the title bar
	local show = Check(page, "Show in my chat window", R.db.toChatFrame, function(on) R.db.toChatFrame = on end,
		"Show the other guilds' guild chat in your normal chat window too. It is always kept here.")
	show:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -150, -29)
	page.show = show

	function page:Fill()
		smf:Clear()
		local r, g, b = Chat.Color()
		for _, e in ipairs(R.db.chatLog) do smf:AddMessage(ChatLine(e), r, g, b) end
	end
	function page:Add(e)
		local r, g, b = Chat.Color()
		smf:AddMessage(ChatLine(e), r, g, b)
	end
	page.Refresh = page.Fill
end

---------------------------------------------------------------------------
-- Page 2: Members
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
-- Page 3: Professions
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
-- Building, opening, refreshing
---------------------------------------------------------------------------

-- Asks for the Discord name inside the window, over the inset, until it is set.
local function BuildSetup()
	setup = CreateFrame("Frame", nil, frame)
	setup:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", 3, -3)
	setup:SetPoint("BOTTOMRIGHT", frame.Inset, "BOTTOMRIGHT", -3, 3)
	setup:SetFrameLevel((R.Plain(frame:GetFrameLevel()) or 0) + 20)
	setup:EnableMouse(true)
	local shade = setup:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints()
	shade:SetColorTexture(0, 0, 0, 0.6)
	local big = setup:CreateTexture(nil, "ARTWORK")
	big:SetTexture(R.MEDIA .. "emblem128")
	big:SetSize(96, 96)
	big:SetPoint("TOP", 0, -24)
	local head = Text(setup, "GameFontNormalLarge", "CENTER")
	head:SetPoint("TOP", big, "BOTTOM", 0, -8)
	head:SetText("Welcome to Riket")
	local msg = Text(setup, "GameFontHighlight", "CENTER")
	msg:SetPoint("TOP", head, "BOTTOM", 0, -8)
	msg:SetWidth(480)
	msg:SetWordWrap(true)
	msg:SetText("Write your Discord name to start. Riket stays off until it is set, and everyone in the nerd guilds sees it next to your character.")
	local input = Input(setup)
	input:SetSize(220, 20)
	input:SetPoint("TOP", msg, "BOTTOM", -50, -18)
	local save = Button(setup, SAVE or "Save", 90)
	save:SetPoint("LEFT", input, "RIGHT", 10, 0)
	local err = Text(setup, "GameFontRedSmall", "CENTER")
	err:SetPoint("TOP", input, "BOTTOM", 50, -8)
	local function Save()
		if UI.SaveDiscord(input:GetText()) then
			err:SetText("")
			input:ClearFocus()
		else
			err:SetText("At least two letters, please.")
		end
	end
	input:SetScript("OnEnterPressed", Save)
	input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	save:SetScript("OnClick", Save)
	setup.input, setup.save, setup.err = input, save, err
	UI.setup = setup
end

-- Builds the pages into panel (the guild window's Riket tab), or into a window of their own.
local function Build(panel)
	if panel then
		frame = panel
	else
		frame = Shell()
		frame:SetSize(WIDTH, HEIGHT)
		frame:SetFrameStrata("HIGH")
		frame:SetToplevel(true)
		frame:SetClampedToScreen(true)
		frame:SetMovable(true)
		frame:EnableMouse(true)
		local pos = R.db.window
		frame:ClearAllPoints()
		if pos.point then frame:SetPoint(pos.point, UIParent, pos.point, pos.x or 0, pos.y or 0)
		else frame:SetPoint("CENTER", 0, 40) end
		tinsert(UISpecialFrames, "NLRiketFrame")

		-- drag by the title bar
		local drag = CreateFrame("Frame", nil, frame)
		drag:SetPoint("TOPLEFT", 58, 0)
		drag:SetPoint("TOPRIGHT", -28, 0)
		drag:SetHeight(24)
		drag:EnableMouse(true)
		drag:RegisterForDrag("LeftButton")
		drag:SetScript("OnDragStart", function() frame:StartMoving() end)
		drag:SetScript("OnDragStop", function()
			frame:StopMovingOrSizing()
			local point, _, _, x, y = frame:GetPoint(1)
			pos.point, pos.x, pos.y = point, x, y
		end)
	end
	local width = panel and R.Plain(panel:GetWidth()) or WIDTH
	if not width or width < WIDTH then width = WIDTH end
	local listWidth = width - 34   -- inside the inset, less the scroll bar

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
	frame.credit:SetText("v" .. tostring(R.VERSION) .. "   ·   " .. CREDIT)

	content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", 4, -4)
	content:SetPoint("BOTTOMRIGHT", frame.Inset, "BOTTOMRIGHT", -4, 4)
	for i, build in ipairs({ BuildChat, BuildMembers, BuildProfessions }) do
		local page = CreateFrame("Frame", nil, content)
		page:SetAllPoints()
		page:Hide()
		build(page, listWidth)
		pages[i] = page
	end
	UI.pages, UI.frame = pages, frame

	-- tabs along the bottom edge, like the character window
	TAB_TEMPLATE = (HasTemplate("PanelTabButtonTemplate") and "PanelTabButtonTemplate")
		or (HasTemplate("CharacterFrameTabButtonTemplate") and "CharacterFrameTabButtonTemplate") or nil
	for i, label in ipairs(TAB_LABELS) do
		local b
		if TAB_TEMPLATE then
			b = CreateFrame("Button", "NLRiketFrameTab" .. i, frame, TAB_TEMPLATE)
		else
			b = Button(frame, label, 110)
		end
		b:SetID(i)
		b:SetText(label)
		if TAB_TEMPLATE and PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, b, 15, nil, 65) end
		if i == 1 then b:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 11, 2)
		else b:SetPoint("TOPLEFT", tabs[i - 1], "TOPRIGHT", TAB_TEMPLATE and 3 or 4, 0) end
		b:SetScript("OnClick", function()
			Sound("IG_CHARACTER_INFO_TAB")
			Select(i)
		end)
		tabs[i] = b
	end
	frame.Tabs = tabs
	if TAB_TEMPLATE and PanelTemplates_SetNumTabs then pcall(PanelTemplates_SetNumTabs, frame, #tabs) end
	UI.tabs = tabs

	-- not in a guild of the network: a curtain over the inset
	lock = CreateFrame("Frame", nil, frame)
	lock:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", 3, -3)
	lock:SetPoint("BOTTOMRIGHT", frame.Inset, "BOTTOMRIGHT", -3, 3)
	lock:SetFrameLevel((R.Plain(frame:GetFrameLevel()) or 0) + 20)
	lock:EnableMouse(true)
	local shade = lock:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints()
	shade:SetColorTexture(0, 0, 0, 0.6)
	local big = lock:CreateTexture(nil, "ARTWORK")
	big:SetTexture(R.MEDIA .. "emblem128")
	big:SetSize(128, 128)
	big:SetPoint("CENTER", 0, 40)
	local msg = Text(lock, "GameFontHighlight", "CENTER")
	msg:SetPoint("TOP", big, "BOTTOM", 0, -14)
	msg:SetWidth(520)
	msg:SetWordWrap(true)
	msg:SetText("Riket is for the guilds with \"nerd\" in their name: Nerdelandslaget, Nerdelandslaget II and their friends.")
	UI.lock = lock
	BuildSetup()

	frame:SetScript("OnShow", function()
		if not frame.inJ then Sound("IG_CHARACTER_INFO_OPEN") end
		UI.Refresh()
		if (R.db.tab or 1) == 1 then pages[1]:Fill() end
	end)
	frame:SetScript("OnHide", function() if not frame.inJ then Sound("IG_CHARACTER_INFO_CLOSE") end end)
	Select(R.db.tab or 1)
end

function UI.Refresh()
	if not frame or not frame:IsShown() then return end
	local inNetwork = R.MyGuild() ~= nil
	local needsName = inNetwork and not R.Discord()
	lock:SetShown(not inNetwork)
	setup:SetShown(needsName)
	content:SetShown(inNetwork and not needsName)
	Status()
	local i = R.db.tab or 1
	if i ~= 1 and pages[i].Refresh then pages[i]:Refresh() end   -- (the chat page adds its lines as they come)
end

-- Opens Riket: in the guild window when it can hold it, else in a window of its own.
function UI.Open(tab)
	if not R.db then return end
	if (not frame or frame.inJ) and R.MyGuild() and J.Open(tab) then return end
	if frame and frame.inJ then
		R.Print("Riket is a tab in the guild window (J). Make the window full size to see it.")
		return
	end
	if not frame then Build() end
	frame:Show()
	if tab then Select(tab) end
end

function UI.Toggle()
	if frame and frame:IsShown() then
		if frame.inJ then J.Close() else frame:Hide() end
	else
		UI.Open()
	end
end

R.OnChange(function(what, e)
	if what == "guild" or what == "ready" or what == "discord" then J.PlaceTab() end
	if what == "needsDiscord" then UI.AskDiscord() end
	if what == "ready" then C_Timer.After(6, function() UI.OfferNote(false) end) end
	if not frame or not frame:IsShown() then return end
	if what == "chat" then
		if (R.db.tab or 1) == 1 and e then pages[1]:Add(e) end
	elseif what == "members" or what == "profs" or what == "peer" or what == "ready" or what == "guild" or what == "discord" then
		UI.Refresh()
	end
end)

---------------------------------------------------------------------------
-- The guild window (J): a Riket tab under the window's own tabs on its right side. Clicking it
-- lays Riket's pages over the window's content; any of the window's own tabs, or closing the
-- window, takes them away again. Nothing of Blizzard's is changed: Riket only draws on top and
-- listens.
---------------------------------------------------------------------------

J.TABS = { "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab" }
UI.J = J

local function Host() return _G.CommunitiesFrame end

-- Big enough, and not in its small chat-only mode.
function J.Usable()
	local host = Host()
	if not J.attached or not IsTable(host) then return false end
	if host.GetDisplayMode and COMMUNITIES_FRAME_DISPLAY_MODES and COMMUNITIES_FRAME_DISPLAY_MODES.MINIMIZED ~= nil then
		local ok, mode = pcall(host.GetDisplayMode, host)
		if ok and mode == COMMUNITIES_FRAME_DISPLAY_MODES.MINIMIZED then return false end
	end
	local w, h = R.Plain(host:GetWidth()) or 0, R.Plain(host:GetHeight()) or 0
	return w >= 700 and h >= 380
end

-- Is the guild (not another community) what the window shows?
function J.GuildSelected()
	local host = Host()
	if not (host.GetSelectedClubId and C_Club and C_Club.GetClubInfo and Enum and Enum.ClubType) then return true end
	local ok, id = pcall(host.GetSelectedClubId, host)
	if not ok or not id then return true end
	local ok2, info = pcall(C_Club.GetClubInfo, id)
	if not ok2 or type(info) ~= "table" or info.clubType == nil then return true end
	return info.clubType == Enum.ClubType.Guild
end

-- The gap between the window's own side tabs, so ours lines up with them.
local function TabGap(host)
	local a, b = host.ChatTab, host.RosterTab
	if IsTable(a) and IsTable(b) and a.GetBottom and b.GetTop then
		local ab, bt = R.Plain(a:GetBottom()), R.Plain(b:GetTop())
		if type(ab) == "number" and type(bt) == "number" and ab > bt and ab - bt < 60 then return ab - bt end
	end
	return 20
end

function J.PlaceTab()
	local host, tab = Host(), J.tab
	if not tab or not IsTable(host) then return end
	local last
	for _, key in ipairs(J.TABS) do
		local t = host[key]
		if IsTable(t) and t.IsShown and t:IsShown() then last = t end
	end
	tab:ClearAllPoints()
	if last then tab:SetPoint("TOP", last, "BOTTOM", 0, -TabGap(host))
	else tab:SetPoint("TOPLEFT", host, "TOPRIGHT", 0, -40) end
	tab:SetShown(R.db ~= nil and R.MyGuild() ~= nil and (not frame or frame.inJ) and J.Usable() and J.GuildSelected())
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

function J.Attach()
	local host = Host()
	if J.attached or not IsTable(host) or not R.db then return end
	J.attached = true

	-- the side tab, drawn like the window's own (the spellbook's tab art)
	local tab = CreateFrame("CheckButton", "NLRiketGuildTab", host)
	tab:SetSize(32, 32)
	local bg = tab:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
	bg:SetSize(64, 64)
	bg:SetPoint("TOPLEFT", -3, 11)
	tab:SetNormalTexture(R.MEDIA .. "round64")
	tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	tab:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
	local checked = tab:GetCheckedTexture()
	if IsTable(checked) then checked:SetBlendMode("ADD") end
	tab:SetScript("OnClick", function()
		Sound("IG_CHARACTER_INFO_TAB")
		if frame and frame.inJ and frame:IsShown() then J.Hide(true) else J.Show() end
	end)
	tab:SetScript("OnEnter", function(self) Tip(self, TITLE, GuildLines(), nil, "ANCHOR_RIGHT") end)
	tab:SetScript("OnLeave", HideTip)
	tab:Hide()
	J.tab = tab

	-- the window's own tabs, closing it, or a new mode take Riket away
	for _, key in ipairs(J.TABS) do
		local t = host[key]
		if IsTable(t) and t.HookScript then t:HookScript("OnClick", function() J.Hide(false) end) end
	end
	host:HookScript("OnHide", function() J.Hide(true) end)
	host:HookScript("OnShow", function() J.PlaceTab() end)
	if host.SetDisplayMode then hooksecurefunc(host, "SetDisplayMode", function() J.Hide(false) J.PlaceTab() end) end
	if host.SelectClub then hooksecurefunc(host, "SelectClub", function() J.PlaceTab() end) end
	J.PlaceTab()
end

function J.Show(tabIndex)
	local host = Host()
	if not J.Usable() or (frame and not frame.inJ) then return false end
	if not frame then Build(J.Panel()) end
	if frame:IsShown() then
		if tabIndex then Select(tabIndex) end
		return true
	end
	J.restore = {}
	for _, key in ipairs(J.TABS) do
		local t = host[key]
		if IsTable(t) and t.GetChecked and t:GetChecked() then
			J.restore[#J.restore + 1] = t
			t:SetChecked(false)
		end
	end
	frame:Show()
	if J.tab then J.tab:SetChecked(true) end
	if tabIndex then Select(tabIndex) end
	return true
end

-- restore: put back the window's own tab marks (we closed Riket ourselves).
function J.Hide(restore)
	if J.tab then J.tab:SetChecked(false) end
	if not frame or not frame.inJ or not frame:IsShown() then return end
	frame:Hide()
	if restore and J.restore then
		for _, t in ipairs(J.restore) do t:SetChecked(true) end
	end
	J.restore = nil
end

-- Opens the guild window (loading it the first time) and shows the Riket tab in it.
function J.Open(tabIndex)
	local host = Host()
	if not (IsTable(host) and host:IsShown()) and ToggleGuildFrame and IsInGuild and IsInGuild() then
		pcall(ToggleGuildFrame)
		host = Host()
	end
	if IsTable(host) and not J.attached then J.Attach() end
	if not (IsTable(host) and host:IsShown()) then return false end
	J.PlaceTab()
	return J.Show(tabIndex)
end

function J.Close()
	local host = Host()
	if IsTable(host) and host:IsShown() and ToggleGuildFrame then pcall(ToggleGuildFrame) end
	J.Hide(true)
end

R.On("ADDON_LOADED", function(name)
	if name == "Blizzard_Communities" then J.Attach() end
end)

---------------------------------------------------------------------------
-- The Discord name: asked for once, and offered for the guild note
---------------------------------------------------------------------------

local function PopupEditBox(self)
	return (self.GetEditBox and self:GetEditBox()) or self.editBox or self.EditBox
end

if type(StaticPopupDialogs) == "table" then
	StaticPopupDialogs.NLRIKET_DISCORD = {
		text = TITLE .. "\n\nWrite your Discord name. Riket stays off until it is set, and everyone in the nerd guilds sees it next to your character.",
		button1 = SAVE or "Save",
		button2 = LATER or "Later",
		hasEditBox = true,
		maxLetters = 32,
		editBoxWidth = 220,
		OnShow = function(self)
			local eb = PopupEditBox(self)
			if IsTable(eb) then eb:SetText(R.Discord() or "") eb:SetFocus() end
		end,
		OnAccept = function(self)
			local eb = PopupEditBox(self)
			if not (IsTable(eb) and UI.SaveDiscord(eb:GetText())) then
				R.Print("Your Discord name needs at least two letters.")
				return true   -- keeps the box open
			end
		end,
		EditBoxOnEnterPressed = function(eb)
			if UI.SaveDiscord(eb:GetText()) then eb:GetParent():Hide()
			else R.Print("Your Discord name needs at least two letters.") end
		end,
		EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
	StaticPopupDialogs.NLRIKET_NOTE = {
		text = TITLE .. "\n\nPut your Discord name in your guild note too, so it shows in the guild roster?\n\nNow: %s\nNew: %s",
		button1 = YES or "Yes",
		button2 = NO or "No",
		OnAccept = function()
			if M.WriteNote(R.Discord()) then R.Print("Your guild note is now your Discord name.")
			else R.Print("The game didn't take the guild note.") end
		end,
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
	UI.OfferNote(true)
	UI.Refresh()
	return true
end

-- The popup asking for the Discord name: at login when it isn't set (once per session), and
-- with /riket discord to change it.
function UI.AskDiscord(force)
	if not force and (UI.askedDiscord or not R.MyGuild()) then return end
	UI.askedDiscord = true
	if StaticPopup_Show and type(StaticPopupDialogs) == "table" and StaticPopupDialogs.NLRIKET_DISCORD then
		StaticPopup_Show("NLRIKET_DISCORD")
	else
		UI.Open()
	end
end

-- Offers to write the Discord name as this character's guild note, where the guild lets
-- members edit notes and the note doesn't hold it yet. Once per character, or when asked.
function UI.OfferNote(force, tries)
	local d = R.Discord()
	if not d or not R.MyGuild() then return end
	if not force and R.char.noteAsked then return end
	if not M.CanEditNote() then return end
	local note = M.MyNote()
	if note == nil then   -- the roster isn't in yet
		tries = (tries or 0) + 1
		if tries <= 3 then
			M.Ask()
			C_Timer.After(5, function() UI.OfferNote(force, tries) end)
		end
		return
	end
	R.char.noteAsked = true
	d = R.Cut(d, 31)
	if note:lower():find(d:lower(), 1, true) then return end
	if StaticPopup_Show then
		StaticPopup_Show("NLRIKET_NOTE", note ~= "" and (note:gsub("|", "||")) or "(empty)", d)
	end
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
		root:CreateButton("Guild chat", function() UI.Open(1) end)
		root:CreateButton("Members", function() UI.Open(2) end)
		root:CreateButton("Professions", function() UI.Open(3) end)
		root:CreateButton("Change Discord name", function() UI.AskDiscord(true) end)
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
	if loaded then J.Attach() end
end)

---------------------------------------------------------------------------
-- /riket
---------------------------------------------------------------------------

SLASH_NLRIKET1, SLASH_NLRIKET2 = "/riket", "/nll"
SlashCmdList.NLRIKET = function(msg)
	local cmd = strtrim(msg or ""):lower()
	if cmd == "" then UI.Toggle()
	elseif cmd == "chat" then UI.Open(1)
	elseif cmd == "members" or cmd == "medlemmer" then UI.Open(2)
	elseif cmd == "professions" or cmd == "prof" or cmd == "yrker" then UI.Open(3)
	elseif cmd == "discord" then UI.AskDiscord(true)
	elseif cmd == "note" then UI.OfferNote(true)
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
		R.Print("/riket  opens Riket in the guild window (J)   ·   /riket chat | members | professions | discord | note | button | status | debug")
		R.Print(GREY .. TITLE .. " v" .. tostring(R.VERSION) .. "   ·   " .. CREDIT .. "|r")
	end
end
