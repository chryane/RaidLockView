-- RaidLockView - UI.lua
-- 界面：共用工具、表格组件、主面板外壳、小地图按钮。面板尺寸算死，刷新只动数据不动几何；
-- 行槽只留可视行 + 1，滚动换数据不建控件。

local _, ns = ...
local L = ns.L

-- 共用工具

local W = {}
ns.UI = W

local GRAY = 0.8
W.ROW_HOVER = { 0.60, 0.52, 0.28, 0.22 }

function W.RGB(classFile)
	local c = RAID_CLASS_COLORS[classFile] or NORMAL_FONT_COLOR
	return c.r, c.g, c.b
end

function W.Fill(tex, c)
	tex:SetColorTexture(c[1], c[2], c[3], c[4])
end

function W.FormatTime(ts, fmt)
	if not ts then return "-" end
	return date(fmt or "%Y-%m-%d %H:%M", ts)
end

-- 按 UTF-8 首字节切字，避免把中文 / 罗马数字切成半个
local function Utf8Chars(s)
	local out, i, n = {}, 1, #s
	while i <= n do
		local b = string.byte(s, i)
		local len = (b >= 0xF0 and 4) or (b >= 0xE0 and 3) or (b >= 0xC0 and 2) or 1
		out[#out + 1] = string.sub(s, i, i + len - 1)
		i = i + len
	end
	return out
end

-- 超宽只截主体：后缀带颜色码，被切开会染色到后面
function W.FitText(fs, main, suffix, maxW)
	fs:SetText(main .. suffix)
	if fs:GetStringWidth() <= maxW then return end
	local chars = Utf8Chars(main)
	for n = #chars - 1, 0, -1 do
		local head = (n > 0) and table.concat(chars, "", 1, n) or ""
		fs:SetText(head .. "..." .. suffix)
		if fs:GetStringWidth() <= maxW then return end
	end
end

function W.TT(text)
	GameTooltip:AddLine(text, GRAY, GRAY, GRAY)
end

function W.TTStat(label, value)
	GameTooltip:AddLine(label .. ": " .. value, GRAY, GRAY, GRAY)
end

-- 内容没超出可视高就把滚动条藏掉（ScrollUtil 只管拇指位置，显隐得自己来）
function W.SyncScrollBar(scroll)
	scroll:UpdateScrollChildRect()
	if (scroll:GetVerticalScrollRange() or 0) > 0 then
		scroll.bar:Show()
	else
		scroll.bar:Hide()
		scroll:SetVerticalScroll(0)
	end
end

-- 表格组件

local T = {}

local NAME_W   = 150
local CHAR_W   = 110
local ROW_H    = 22
local HEADER_H = 42    -- 两行：角色名 + 服务器名（中文字体行高偏大，34 装不下）
local VISIBLE  = 10
local PER_PAGE = 5
local WIDTH    = NAME_W + PER_PAGE * CHAR_W

local CHECK_TEX   = "Interface\\RaidFrame\\ReadyCheck-Ready"
local PROG_SIZE   = 10   -- GameFontHighlightSmall 的简体中文族是 15px，必须显式压下来
local CLASS_ALPHA = 0.12

local C_ROW_ODD   = { 0.20, 0.22, 0.28, 0.28 }
local C_ROW_EVEN  = { 0.08, 0.09, 0.12, 0.10 }
local C_LINE      = { 0.28, 0.28, 0.34, 0.55 }
local C_LINE_GOLD = { 0.72, 0.60, 0.30, 0.55 }
local C_LOCK_BG   = { 0.15, 0.45, 0.18, 0.14 }
local C_LOCK_PART = { 0.55, 0.44, 0.10, 0.16 }   -- 未全通：金勾配金底

local function HLine(parent, layer, color)
	local t = parent:CreateTexture(nil, layer)
	W.Fill(t, color)
	t:SetHeight(1)
	return t
end

-- ★ 最右一条落在 590 而非表格右缘 700，别当它是外框线删掉
local function ColumnLines(parent, height, layer)
	local lines = {}
	for i = 0, PER_PAGE - 1 do
		local t = parent:CreateTexture(nil, layer)
		W.Fill(t, C_LINE)
		t:SetSize(1, height)
		t:SetPoint("TOPLEFT", parent, "TOPLEFT", NAME_W + i * CHAR_W, 0)
		lines[#lines + 1] = t
	end
	return lines
end

-- 按需建的整块底色（表头格与单元格共用）
local function Bg(frame)
	local t = frame.bg
	if not t then
		t = frame:CreateTexture(nil, "BACKGROUND")
		t:SetAllPoints(frame)
		frame.bg = t
	end
	return t
end

local function ParseProgress(p)
	if not p then return nil end
	local killed, total = string.match(p, "^(%d+)/(%d+)$")
	if not killed then return nil end
	return tonumber(killed), tonumber(total)
end

-- 行底色：斑马纹 + 悬停提亮（换底色，不加纹理，单元格区域也能透出来）
local function PaintRow(row)
	local c = row.hover and W.ROW_HOVER or row.baseColor
	if c then W.Fill(row.bg, c) end
end

-- ★ 全表只允许一行亮：进入即抢走高亮（行是池里复用的，OnLeave 未必配平）
local function SetHoverRow(f, row)
	if not f or f.hoverRow == row then return end
	local prev = f.hoverRow
	if prev then prev.hover = nil; PaintRow(prev) end
	f.hoverRow = row
	if row then row.hover = true; PaintRow(row) end
end

function T.ClearHover(f)
	if f.hoverRow then SetHoverRow(f, nil) end
	GameTooltip:Hide()
end

local function HeaderCellOnEnter(self)
	local cd = self.charData
	if not cd then return end
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
	local suffix = self.isCurrent and (" (" .. L.Current .. ")") or ""
	GameTooltip:AddLine((cd.name or "?") .. suffix, 1, 1, 1)
	W.TTStat(L.Realm, ns:RealmLabel(cd))
	W.TTStat(L.Class, cd.className or cd.class or "-")
	W.TTStat(L.Level, cd.level or 0)
	W.TTStat(L.LastSeen, W.FormatTime(cd.lastSeen))
	local cc = self.charCounts and self.charCounts[cd.key]
	if cc and cc.total > 0 then
		W.TTStat(L.FreeCount, cc.free .. "/" .. cc.total)
		W.TTStat(L.LockedCount, cc.locked)
	end
	GameTooltip:Show()
end

local function HideTooltip() GameTooltip:Hide() end

local function NewHeaderCell(parent, colIndex)
	local cell = CreateFrame("Frame", nil, parent)
	cell:SetSize(CHAR_W, HEADER_H)
	cell:SetPoint("TOPLEFT", NAME_W + (colIndex - 1) * CHAR_W, 0)

	local name = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	name:SetPoint("TOP", 0, -5)
	cell.nameText = name

	-- 钉在格子下缘而不是跟着名字往下排：中文字体行高偏大，跟着排会顶出表头
	local realm = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	realm:SetPoint("BOTTOM", cell, "BOTTOM", 0, 5)
	cell.realmText = realm

	cell:SetScript("OnEnter", HeaderCellOnEnter)
	cell:SetScript("OnLeave", HideTooltip)
	return cell
end

-- 名字 / 服名 / 是否当前角色都没变就不碰文字（FitText 每次都要造临时串）
local function SetHeaderCell(cell, charData, isCurrent, charCounts)
	local label = ns:RealmLabel(charData)
	local same = cell.charKey == charData.key and cell.isCurrent == isCurrent
		and cell.realmLabel == label

	cell:Show()
	cell.charData, cell.isCurrent, cell.charCounts = charData, isCurrent, charCounts
	cell.charKey, cell.realmLabel = charData.key, label
	if same then return end

	if isCurrent then
		local r, g, b = W.RGB(charData.class)
		local t = Bg(cell)
		t:SetColorTexture(r, g, b, CLASS_ALPHA)
		t:Show()
	elseif cell.bg then
		cell.bg:Hide()
	end

	W.FitText(cell.nameText, charData.name or "?", "", CHAR_W - 10)
	cell.nameText:SetTextColor(W.RGB(charData.class))
	W.FitText(cell.realmText, label, "", CHAR_W - 10)
	local gray = isCurrent and 0.84 or 0.66
	cell.realmText:SetTextColor(gray, gray, gray)
end

-- 单元格：底色 / 锁定勾 / 进度数字都按需建（建过就复用，稳态零新建）
-- ★ 字段控制在 8 个：再多一个，Lua 哈希槽就从 8 扩到 16

local function CellCheck(cell)
	local t = cell.check
	if not t then
		t = cell:CreateTexture(nil, "ARTWORK")
		t:SetSize(18, 18)
		t:SetPoint("CENTER")
		t:SetTexture(CHECK_TEX)
		cell.check = t
	end
	return t
end

local function CellProg(cell)
	local fs = cell.prog
	if not fs then
		fs = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("BOTTOMLEFT", CellCheck(cell), "BOTTOMRIGHT", 5, 0)
		local path, _, flags = fs:GetFont()   -- 只换字号，字体文件与描边照抄
		if path then fs:SetFont(path, PROG_SIZE, flags) end
		fs:SetShadowColor(0, 0, 0, 1)
		fs:SetShadowOffset(1, -1)
		fs:SetTextColor(1, 0.82, 0)
		cell.prog = fs
	end
	return fs
end

local function CellOnEnter(self)
	local row = self:GetParent()
	SetHoverRow(row.owner, row)

	local cd, raid = self.charData, self.raid
	if not cd or not raid then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(cd.name .. " - " .. ns.RaidLabel(raid), 1, 1, 1)
	-- 锁定信息现查：格子不存 lockout，上百个格子各自存字段就是几十 KB 哈希槽
	local lo = cd.lockouts and cd.lockouts[raid.key]
	if self.locked then
		if lo and lo.id then
			W.TTStat(L.Locked, lo.id)
		else
			W.TT(L.Locked)
		end
		if lo and lo.progress then W.TTStat(L.Progress, lo.progress) end
		if lo and lo.reset then W.TTStat(L.ResetAt, W.FormatTime(lo.reset)) end
	else
		W.TT(L.NotLocked)   -- 没进度也要弹，否则整列像没反应
	end
	GameTooltip:Show()
end

local function NewCell(row, colIndex)
	local cell = CreateFrame("Frame", nil, row)
	cell:SetSize(CHAR_W, ROW_H)
	cell:SetPoint("LEFT", NAME_W + (colIndex - 1) * CHAR_W, 0)
	cell:EnableMouse(true)   -- 空列整格 Hide，隐藏帧不接输入 ⇒ 不弹提示框
	cell:SetScript("OnEnter", CellOnEnter)
	cell:SetScript("OnLeave", HideTooltip)
	return cell
end

local function SetCell(cell, charData, raid, myKey, now, mark)
	cell:Show()
	cell.charData = charData
	cell.raid = raid
	cell.locked = ns:IsLocked(charData, raid.key, now)

	-- 全通 = 已杀 >= 总数；进度解析不出来（旧存档）按全通，别突然给个金勾
	local lo = charData.lockouts and charData.lockouts[raid.key]
	local killed, total = ParseProgress(lo and lo.progress)
	local full = (not killed) or (not total) or (total <= 0) or (killed >= total)
	local gold = mark and cell.locked and not full

	if cell.locked then
		local ck = CellCheck(cell)
		ck:SetShown(true)
		ck:SetDesaturated(gold)   -- 绿勾直接乘金色会变黄绿
		if gold then
			ck:SetVertexColor(1, 0.82, 0)
		else
			ck:SetVertexColor(1, 1, 1)
		end
	elseif cell.check then
		cell.check:Hide()
	end

	if gold then
		local fs = CellProg(cell)
		if cell.progKilled ~= killed or cell.progTotal ~= total then   -- 数字没变不拼串
			cell.progKilled, cell.progTotal = killed, total
			fs:SetText(killed .. "/" .. total)
		end
		fs:Show()
	elseif cell.prog then
		cell.prog:Hide()
	end

	-- 当前角色列优先职业色，其余锁定格铺一层淡底（全通淡绿 / 未全通淡金）
	if charData.key == myKey then
		local r, g, b = W.RGB(charData.class)
		local t = Bg(cell)
		t:SetColorTexture(r, g, b, CLASS_ALPHA)
		t:Show()
	elseif cell.locked then
		local t = Bg(cell)
		W.Fill(t, gold and C_LOCK_PART or C_LOCK_BG)
		t:Show()
	elseif cell.bg then
		cell.bg:Hide()
	end
end

local function ClearCell(cell)
	cell.charData, cell.raid, cell.locked = nil, nil, nil
	if cell.prog then cell.prog:Hide() end
	cell:Hide()
end

local function NameHitOnEnter(self)
	local r = self:GetParent()
	SetHoverRow(r.owner, r)

	local raid = r.raid
	if not raid then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(ns.RaidLabel(raid), 1, 1, 1)
	if raid.phase and raid.phase > 0 then
		W.TTStat(L.Phase, "P" .. raid.phase)
	elseif raid.phase == 0 then
		W.TTStat(L.Phase, L.PhaseIrregular)
	else
		W.TT(L.Unknown)
	end
	local c = r.counts
	if c and c.total > 0 then
		W.TTStat(L.FreeCount, c.free .. "/" .. c.total)
		W.TTStat(L.LockedCount, c.locked)
	end
	GameTooltip:Show()
end

local function RowOnEnter(self)
	SetHoverRow(self.owner, self)
end

local function RowOnLeave(self)
	-- 有些路径下行 OnLeave 会先于下一格的 OnEnter 触发（鼠标其实还在本行内）⇒ 别熄灯
	if self:IsMouseOver() then return end
	if self.owner.hoverRow == self then SetHoverRow(self.owner, nil) end
end

local function NewRow(parent, owner)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(WIDTH, ROW_H)
	row:EnableMouse(true)   -- 团本名列区域（无 cell 覆盖）靠它收 hover
	row.owner = owner

	local bg = row:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(row)
	row.bg = bg

	local hline = HLine(row, "BORDER", C_LINE)
	hline:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT")
	hline:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT")

	local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("LEFT", 10, 0)
	label:SetJustifyH("LEFT")
	row.label = label

	-- 鼠标层只铺团本名列：提示框只在这里弹，右侧空列落在行本体上（行不弹）
	local hit = CreateFrame("Frame", nil, row)
	hit:SetSize(NAME_W, ROW_H)
	hit:SetPoint("LEFT", 0, 0)
	hit:EnableMouse(true)
	hit:SetScript("OnEnter", NameHitOnEnter)
	hit:SetScript("OnLeave", HideTooltip)
	row.nameHit = hit

	row:SetScript("OnEnter", RowOnEnter)
	row:SetScript("OnLeave", RowOnLeave)
	row.cells = {}
	return row
end

-- counts：raid.key -> { total, locked, free }，只给行提示框用
local function SetRow(row, raid, rowIndex, chars, ctx)
	-- 行是池里复用的：上一轮的悬停必须清掉，否则重画后还亮着
	if row.owner.hoverRow == row then row.owner.hoverRow = nil end
	row.hover = nil
	row.raid = raid
	row.baseColor = (rowIndex % 2 == 1) and C_ROW_ODD or C_ROW_EVEN
	PaintRow(row)

	local label = ns.RaidLabel(raid)
	if row.labelText ~= label then
		row.labelText = label
		row.label:SetText(label)
	end
	row.counts = ctx.counts and ctx.counts[raid.key]

	for colIndex = 1, PER_PAGE do
		local cell, charData = row.cells[colIndex], ctx.chars[colIndex]
		if charData then
			if not cell then
				cell = NewCell(row, colIndex)
				row.cells[colIndex] = cell
			end
			SetCell(cell, charData, raid, ctx.myKey, ctx.now, ctx.mark)
		elseif cell then
			ClearCell(cell)
		end
	end
end

-- 行槽只留"可视行 + 1"个，滚动时换数据换位置：一屏只看 10 行，全建必有十余行常在视口外
local ROW_SLOTS = VISIBLE + 1

local function FillRows(f, v)
	local raids, total = v.raids, #v.raids
	local first = f.firstRow or 1
	local slots = math.min(total, ROW_SLOTS)
	local pool = f.rowPool
	SetHoverRow(f, nil)   -- 行要换内容了，旧高亮不能留在别的槽上

	for i = 1, slots do
		local rowIndex = first + i - 1
		local row = pool[i]
		if not row then
			row = NewRow(f.content, f)
			pool[i] = row
		end
		if rowIndex > total then
			row:Hide()
		else
			if row.slot ~= rowIndex then
				row.slot = rowIndex
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", 0, -(rowIndex - 1) * ROW_H)
			end
			SetRow(row, raids[rowIndex], rowIndex, v.chars, v)
			row:Show()
		end
	end
	for i = slots + 1, #pool do pool[i]:Hide() end
end

local function OnScroll(self)
	local f = self.owner
	local v = f and f.view
	if not v then return end
	local first = math.floor((self:GetVerticalScroll() or 0) / ROW_H) + 1
	if first == f.firstRow then return end
	f.firstRow = first
	FillRows(f, v)
end

-- 两张拼接缓冲是模块级的：面板每次打开都要拼一遍，新造表等于每次都留一堆等回收的垃圾
local sigParts, fpParts = {}, {}

-- 轻量签名：界面开关 + 集合 + 锁定数据版本。命中就不用逐格拼完整指纹（那要造几百段临时串）
-- 5 分钟桶兜底：万一哪里漏了版本号，到期状态最迟 5 分钟也会重算一次
local function QuickSig(raids, chars, myKey, now, mark)
	local p = sigParts
	p[1] = myKey or ""
	p[2] = ns.realmFilter or ""
	p[3] = ns.charPage or 1
	p[4] = ns:GetCurrentPhase()
	p[5] = mark and "1" or "0"
	p[6] = ns.lockVer or 0
	p[7] = math.floor(now / 300)
	p[8] = #raids
	p[9] = #chars
	local n = 9
	for i = 1, #raids do n = n + 1; p[n] = raids[i].key end
	for i = 1, #chars do
		local c = chars[i]
		n = n + 1; p[n] = c.key
		n = n + 1; p[n] = ns:RealmLabel(c)
	end
	return table.concat(p, "|", 1, n)
end

-- 完整指纹：连每格锁定状态一起比（只看当前页角色之外也要算，切页不能拿旧值）
local function Fingerprint(raids, chars, myKey, now, mark)
	local p = fpParts
	p[1] = myKey or ""
	p[2] = ns.realmFilter or ""
	p[3] = ns.charPage or 1
	p[4] = ns:GetCurrentPhase()
	p[5] = mark and "1" or "0"
	local n = 5
	for i = 1, #raids do n = n + 1; p[n] = raids[i].key end
	for i = 1, #chars do
		local c = chars[i]
		n = n + 1; p[n] = c.key
		n = n + 1; p[n] = ns:RealmLabel(c)
		for j = 1, #raids do
			local key = raids[j].key
			if ns:IsLocked(c, key, now) then
				local lo = c.lockouts[key]
				n = n + 1; p[n] = "1" .. ((lo and lo.progress) or "")
			else
				n = n + 1; p[n] = "0"
			end
		end
	end
	return table.concat(p, "|", 1, n)
end

local function BuildCounts(raids, chars, now)
	local counts, charCounts = {}, {}
	for _, raid in ipairs(raids) do
		counts[raid.key] = { total = #chars, locked = 0 }
	end
	for _, c in ipairs(chars) do
		local cc = { total = #raids, locked = 0 }
		charCounts[c.key] = cc
		for _, raid in ipairs(raids) do
			if ns:IsLocked(c, raid.key, now) then
				local rc = counts[raid.key]
				rc.locked = rc.locked + 1
				cc.locked = cc.locked + 1
			end
		end
	end
	for _, v in pairs(counts) do v.free = v.total - v.locked end
	for _, v in pairs(charCounts) do v.free = v.total - v.locked end
	return counts, charCounts
end

function T.Attach(f)
	f.header = CreateFrame("Frame", nil, f)

	local colTitle = f.header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	colTitle:SetPoint("LEFT", 10, 0)
	colTitle:SetTextColor(0.92, 0.86, 0.66)
	colTitle:SetText(L.ColRaid)

	f.headerLine = HLine(f.header, "ARTWORK", C_LINE_GOLD)
	f.headerLine:SetPoint("BOTTOMLEFT",  f.header, "BOTTOMLEFT")
	f.headerLine:SetPoint("BOTTOMRIGHT", f.header, "BOTTOMRIGHT")

	-- 外框先建，z 序垫在滚动区下面
	f.tableBox = CreateFrame("Frame", nil, f, "BackdropTemplate")
	f.tableBox:SetBackdrop({
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 13,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})

	f.scroll = CreateFrame("ScrollFrame", nil, f)
	f.scroll.owner = f
	f.content = CreateFrame("Frame", nil, f.scroll)
	f.content:SetPoint("TOPLEFT")
	f.scroll:SetScrollChild(f.content)

	local sb = CreateFrame("EventFrame", nil, f.scroll, "MinimalScrollBar")
	sb:Hide()
	ScrollUtil.InitScrollFrameWithScrollBar(f.scroll, sb)
	f.scroll.bar = sb

	-- ★ ScrollUtil 会 SetScript("OnVerticalScroll") 覆盖既有脚本（真机行为）⇒ 只能它之后再包一层：
	--   先把它原样转给它（拇指要跟手），再接"换首行"。挂在前面会被冲掉，滚动时永远只看前 11 条
	local nativeScroll = f.scroll:GetScript("OnVerticalScroll")
	f.scroll:SetScript("OnVerticalScroll", function(self, offset)
		if nativeScroll then nativeScroll(self, offset) end
		OnScroll(self)
	end)

	f.emptyText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.emptyText:SetPoint("CENTER", f.scroll, "CENTER")
	f.emptyText:SetText(L.NoCharData)
	f.emptyText:Hide()

	f.rowPool = {}
end

-- ctx = { raids, chars, allChars, myKey, now, mark }；返回 false 表示数据没变、整表跳过
function T.Render(f, ctx)
	local quick = QuickSig(ctx.raids, ctx.allChars, ctx.myKey, ctx.now, ctx.mark)
	if quick == f.quickSig then return false end
	local fp = Fingerprint(ctx.raids, ctx.allChars, ctx.myKey, ctx.now, ctx.mark)
	f.quickSig = quick
	if fp == f.lastFingerprint then return false end
	f.lastFingerprint = fp

	local counts, charCounts = BuildCounts(ctx.raids, ctx.allChars, ctx.now)

	-- 只有表体内容高随团本数变（面板几何已定死）
	local contentH = math.max(#ctx.raids * ROW_H, 1)
	f.content:SetSize(WIDTH, contentH)

	-- ★ 先装好渲染上下文再复位滚动：SetVerticalScroll 会同步触发 OnScroll
	local v = f.view or {}
	f.view = v
	v.raids, v.chars, v.myKey = ctx.raids, ctx.chars, ctx.myKey
	v.counts, v.now, v.mark = counts, ctx.now, ctx.mark
	f.firstRow = 1
	f.scroll:SetVerticalScroll(0)

	-- 表头角色列：格子建一次，之后只填数据
	local cells = f.headerCells
	if not cells then
		cells = {}
		for i = 1, PER_PAGE do cells[i] = NewHeaderCell(f.header, i) end
		f.headerCells = cells
	end
	for colIndex = 1, PER_PAGE do
		local cell, charData = cells[colIndex], ctx.chars[colIndex]
		if charData then
			SetHeaderCell(cell, charData, charData.key == ctx.myKey, charCounts)
		else
			cell:Hide()
			cell.charData, cell.charKey = nil, nil   -- 下次"上场"要重新填文字
		end
	end

	-- 表头列线后建 ⇒ 压在格子职业色底之上
	if not f.headerLines then
		local hrow = CreateFrame("Frame", nil, f.header)
		hrow:SetPoint("TOPLEFT", 0, 0)
		hrow:SetSize(WIDTH, HEADER_H)
		ColumnLines(hrow, HEADER_H, "ARTWORK")
		f.headerLines = hrow
	end

	FillRows(f, v)

	-- 表体列线贯穿全部行、随 content 滚动；层级抬到行之上（行是池里复用的，创建先后不保证）
	local vlineBox = f.bodyLines
	if not vlineBox then
		vlineBox = CreateFrame("Frame", nil, f.content)
		vlineBox:SetPoint("TOPLEFT", 0, 0)
		vlineBox:SetFrameLevel(f.content:GetFrameLevel() + 10)
		f.bodyLines = vlineBox
		f.bodyLineTexs = ColumnLines(vlineBox, contentH, "OVERLAY")
	end
	vlineBox:SetSize(WIDTH, contentH)
	for i = 1, #f.bodyLineTexs do f.bodyLineTexs[i]:SetHeight(contentH) end

	f.emptyText:SetShown(#ctx.chars == 0)
	return true
end

-- 主面板

local TOP_PAD    = 40    -- 面板顶 → 筛选行（标题横幅高 64、上浮 12）
local FILTER_H   = 38
local BOTTOM_H   = 46
local SIDE_L     = 24
local SIDE_R     = 22    -- 滚动条右缘 → 面板右缘
local HEADER_GAP = 4
local DD_TEXT_W  = 160
local DD_OUT     = 17    -- 下拉端部贴图有透明余量 ⇒ 可见框比 frame 内缩，右锚点须外扩
local SB_W       = 8
local SB_GAP     = 6
local TABLE_PAD  = 6
local TABLE_L    = SIDE_L - TABLE_PAD   -- 表格外框左缘（底部按钮左缘要对齐这里）

local FRAME_W = SIDE_L + WIDTH + TABLE_PAD + SB_GAP + SB_W + SIDE_R
local FRAME_H = TOP_PAD + FILTER_H + HEADER_H + HEADER_GAP + ROW_H * VISIBLE + BOTTOM_H

-- 标题横幅（256×64）：整张拉伸会把两端装饰头拉变形 ⇒ 三片拼接，端头 1:1、只有中段横向拉伸
local BANNER_TEX   = "Interface\\DialogFrame\\UI-DialogBox-Header"
local BANNER_H     = 64
local BANNER_MIN_W = 320
local BANNER_MAX_W = 460
local BANNER_CAP_U = 0.34
local BANNER_MID_U = 0.48
local TITLE_INSET  = 100
local TITLE_CY     = 13

local function SetBannerWidth(banner, w)
	banner:SetSize(w, BANNER_H)
	banner.mid:SetSize(w - 2 * banner.capW + 1, BANNER_H)   -- 多给 1px，避免接缝露空线
end

local function LayoutTitle(f, text)
	local title = f.title
	if title:GetText() == text then return end   -- 阶段没变不必重量字符串宽度
	title:SetText(text)
	local w = (title:GetStringWidth() or 0) + 2 * TITLE_INSET
	SetBannerWidth(f.banner, math.max(BANNER_MIN_W, math.min(BANNER_MAX_W, w)))
end

local function ApplyLayout(f)
	f:SetSize(FRAME_W, FRAME_H)

	-- 筛选行右缘 = 表格外框右缘（宽度只作定位基准，下拉自己往外扩 DD_OUT）
	f.filterRow:SetSize(1, FILTER_H)
	f.filterRow:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(SB_W + SB_GAP + SIDE_R), -TOP_PAD)

	f.refreshBtn:SetPoint("BOTTOMLEFT", TABLE_L, 14)
	f.configBtn:SetPoint("LEFT", f.refreshBtn, "RIGHT", 8, 0)
	f.nextBtn:SetPoint("BOTTOMRIGHT", -22, 14)
	f.pageText:SetPoint("RIGHT", f.nextBtn, "LEFT", -8, 0)
	f.prevBtn:SetPoint("RIGHT", f.pageText, "LEFT", -8, 0)

	f.header:SetPoint("TOPLEFT", SIDE_L, -(TOP_PAD + FILTER_H))
	f.header:SetSize(WIDTH, HEADER_H)
	f.scroll:SetPoint("TOPLEFT",     f.header, "BOTTOMLEFT",  0, -HEADER_GAP)
	f.scroll:SetPoint("BOTTOMRIGHT", f,        "BOTTOMRIGHT", -(TABLE_PAD + SB_GAP + SB_W + SIDE_R), BOTTOM_H)

	f.tableBox:SetPoint("TOPLEFT",     f.header, "TOPLEFT",     -TABLE_PAD, TABLE_PAD)
	f.tableBox:SetPoint("BOTTOMRIGHT", f.scroll, "BOTTOMRIGHT",  TABLE_PAD, -TABLE_PAD)

	f.scroll.bar:SetPoint("TOPLEFT",    f.tableBox, "TOPRIGHT",    SB_GAP, 0)
	f.scroll.bar:SetPoint("BOTTOMLEFT", f.tableBox, "BOTTOMRIGHT", SB_GAP, 0)
end

-- 服务器筛选
function ns:SetRealmFilter(realmKey)
	self.realmFilter = realmKey
	self.charPage = 1
	self:RefreshUI()
end

local function InitRealmDropDown(_, level)
	-- 每条设 minWidth，弹出列表才与控件同宽
	local minW = DD_TEXT_W + 25
	local info = UIDropDownMenu_CreateInfo()
	info.text = L.FilterAll
	info.minWidth = minW
	info.checked = (ns.realmFilter == nil)
	info.func = function() ns:SetRealmFilter(nil) end
	UIDropDownMenu_AddButton(info, level)

	for _, o in ipairs(ns:GetRealmOptions()) do
		local key = o.key
		info = UIDropDownMenu_CreateInfo()
		info.text = o.label
		info.minWidth = minW
		info.checked = (ns.realmFilter == key)
		info.func = function() ns:SetRealmFilter(key) end
		UIDropDownMenu_AddButton(info, level)
	end
end

local function OnDragStart(self) self:StartMoving() end
local function OnDragStop(self) self:StopMovingOrSizing() end
local function OnClickRefresh()
	RequestRaidInfo()
	ns:RefreshUI()
end
local function OnClickConfig(self)
	self:GetParent():Hide()
	ns:OpenOptions()
end
local function OnClickPrev()
	ns.charPage = math.max((ns.charPage or 1) - 1, 1)
	ns:RefreshUI()
end
local function OnClickNext()
	ns.charPage = (ns.charPage or 1) + 1
	ns:RefreshUI()
end

local function CreateBaseFrame()
	local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", OnDragStart)
	f:SetScript("OnDragStop", OnDragStop)
	f:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	f:SetPoint("CENTER")

	local banner = CreateFrame("Frame", nil, f)
	banner:SetPoint("TOP", 0, 12)
	banner.capW = math.floor(BANNER_MIN_W * BANNER_CAP_U)

	local function BannerTex(u0, u1)
		local t = banner:CreateTexture(nil, "ARTWORK")
		t:SetTexture(BANNER_TEX)
		t:SetTexCoord(u0, u1, 0, 1)
		return t
	end
	banner.left  = BannerTex(0, BANNER_CAP_U)
	banner.mid   = BannerTex(BANNER_MID_U, 1 - BANNER_MID_U)
	banner.right = BannerTex(1 - BANNER_CAP_U, 1)
	banner.left:SetPoint("TOPLEFT")
	banner.left:SetSize(banner.capW, BANNER_H)
	banner.right:SetPoint("TOPRIGHT")
	banner.right:SetSize(banner.capW, BANNER_H)
	banner.mid:SetPoint("TOPLEFT", banner.left, "TOPRIGHT")
	SetBannerWidth(banner, BANNER_MIN_W)
	f.banner = banner

	-- 标题挂在横幅上：子帧画在父帧所有图层之上，挂 f 上会被横幅盖住
	local title = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("CENTER", banner, "CENTER", 0, TITLE_CY)
	local path, size, flags = title:GetFont()
	title:SetFont(path, (size or 16) - 2, flags)
	f.title = title

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	f.filterRow = CreateFrame("Frame", nil, f)

	local dd = CreateFrame("Frame", nil, f.filterRow, "UIDropDownMenuTemplate")
	UIDropDownMenu_SetWidth(dd, DD_TEXT_W)
	UIDropDownMenu_Initialize(dd, InitRealmDropDown)
	UIDropDownMenu_SetText(dd, L.FilterAll)
	f.realmDropDown = dd

	-- 弹出列表默认会盖住控件：改成紧贴控件下缘、右缘对齐可见右缘
	dd.point, dd.relativePoint, dd.relativeTo = "TOPRIGHT", "BOTTOMRIGHT", dd
	dd.xOffset, dd.yOffset = -DD_OUT, 4
	dd:SetPoint("RIGHT", f.filterRow, "RIGHT", DD_OUT, 0)

	local refresh = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	refresh:SetSize(90, 22)
	refresh:SetText(L.BtnRefresh)
	refresh:SetScript("OnClick", OnClickRefresh)

	local config = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	config:SetSize(90, 22)
	config:SetText(L.BtnConfig)
	config:SetScript("OnClick", OnClickConfig)
	f.refreshBtn, f.configBtn = refresh, config

	local prev = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	prev:SetSize(26, 22)
	prev:SetText("<")
	prev:SetScript("OnClick", OnClickPrev)
	local nextBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	nextBtn:SetSize(26, 22)
	nextBtn:SetText(">")
	nextBtn:SetScript("OnClick", OnClickNext)
	local pageText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pageText:SetTextColor(0.8, 0.8, 0.8)
	f.prevBtn, f.nextBtn, f.pageText = prev, nextBtn, pageText

	T.Attach(f)
	ApplyLayout(f)
	f:Hide()   -- CreateFrame 默认显示；任何创建路径都从隐藏开始
	return f
end

function ns:RefreshUI()
	local f = self.mainFrame
	if not f or not f:IsShown() then return end

	-- 筛选的服务器若已无满级角色（角色被删 / 降级），回落"全部"
	local filter, filterLabel = self.realmFilter, L.FilterAll
	if filter then
		filterLabel = nil
		for _, o in ipairs(self:GetRealmOptions()) do
			if o.key == filter then filterLabel = o.label; break end
		end
		if not filterLabel then
			self.realmFilter = nil
			filter, filterLabel = nil, L.FilterAll
		end
	end

	local raids = self:GetSortedRaids()
	local allChars = self:GetVisibleChars(filter)
	local myKey, now = self:GetCharKey(), time()
	local mark = self:MarkIncomplete()

	-- 角色列分页（筛选后重新钳制页码）
	local maxPage = math.max(math.ceil(#allChars / PER_PAGE), 1)
	self.charPage = math.min(math.max(self.charPage or 1, 1), maxPage)
	local chars = self.pageBuf
	if not chars then chars = {}; self.pageBuf = chars end
	for i = #chars, 1, -1 do chars[i] = nil end
	local from = (self.charPage - 1) * PER_PAGE + 1
	for i = from, math.min(from + PER_PAGE - 1, #allChars) do
		chars[#chars + 1] = allChars[i]
	end

	local ctx = f.ctx
	if not ctx then ctx = {}; f.ctx = ctx end
	ctx.raids, ctx.chars, ctx.allChars = raids, chars, allChars
	ctx.myKey, ctx.now, ctx.mark = myKey, now, mark
	if not T.Render(f, ctx) then return end

	UIDropDownMenu_SetText(f.realmDropDown, filterLabel)
	f.pageText:SetText(string.format("%d/%d", self.charPage, maxPage))
	if self.charPage <= 1 then f.prevBtn:Disable() else f.prevBtn:Enable() end
	if self.charPage >= maxPage then f.nextBtn:Disable() else f.nextBtn:Enable() end

	LayoutTitle(f, string.format(L.TitlePhase, self:GetCurrentPhase()))
	W.SyncScrollBar(f.scroll)
end

-- 每次打开都回顶部：翻到哪是上一次的事，接着看反倒是错的
local function TopScroll(f)
	f.firstRow = 1
	f.scroll:SetVerticalScroll(0)
	if f.view then FillRows(f, f.view) end
end

-- 打开时补扫只是兜底：击杀 / 进本 / 重置都会自己发 UPDATE_INSTANCE_INFO，短时间内重复打开不必再请求
local SCAN_GAP = 10

local function OnFrameShow()
	local now = time()
	if not ns.lastScanAt or now - ns.lastScanAt >= SCAN_GAP then
		ns.lastScanAt = now
		RequestRaidInfo()
	end
	ns:RefreshUI()
	TopScroll(ns.mainFrame)
end

local function OnFrameHide(self)
	T.ClearHover(self)   -- 面板藏起来后 OnLeave 不会再补
end

function ns:BuildMainFrame()
	if self.mainFrame then return self.mainFrame end
	local f = CreateBaseFrame()
	f:SetScript("OnShow", OnFrameShow)
	f:SetScript("OnHide", OnFrameHide)
	self.mainFrame = f
	return f
end

-- 小地图按钮

function ns:InitMinimap()
	if self.minimapButton then return end

	-- ★ 必须具名：收纳插件（MBB 等）遍历 Minimap 子控件的 GetName() 认按钮，匿名 frame 收不进去
	local b = CreateFrame("Button", "RaidLockViewMinimapButton", Minimap)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:SetSize(31, 31)
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetSize(54, 54)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT")

	local background = b:CreateTexture(nil, "BACKGROUND")
	background:SetSize(20, 20)
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetPoint("TOPLEFT", 7, -5)

	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetSize(19, 19)
	icon:SetPoint("CENTER", 1, -1)
	icon:SetTexture("Interface\\AddOns\\RaidLockView\\media\\icon")

	local function UpdatePosition(angle)
		b:ClearAllPoints()
		b:SetPoint("CENTER", Minimap, "CENTER",
			math.cos(math.rad(angle)) * 78, math.sin(math.rad(angle)) * 78)
	end
	UpdatePosition(self.db.minimap.angle or 218)

	local function Open(button)
		if button == "RightButton" then
			ns:OpenOptions()
		else
			ns:Toggle()
		end
	end

	-- 只在拖动期间挂帧函数；鼠标已松开（可能拖到按钮外而收不到 OnMouseUp）就自清
	local function DragUpdate(frame)
		if not IsMouseButtonDown("LeftButton") then
			frame:SetScript("OnUpdate", nil)
			return
		end
		local mx, my = Minimap:GetCenter()
		local px, py = GetCursorPosition()
		local scale = Minimap:GetEffectiveScale()
		local angle = math.deg(math.atan2(py / scale - my, px / scale - mx))
		ns.db.minimap.angle = angle
		UpdatePosition(angle)
	end

	-- ★ AnyDown：OnMouseDown 只在 clickMask 含 Down 时触发（默认只发 Up）；开关放 OnClick 是因为
	--   收纳插件转发/模拟点击走的就是 OnClick，两处都判会一次点击开关两次
	b:RegisterForClicks("AnyDown")
	b:SetScript("OnMouseDown", function(frame)
		-- 被收纳后父级不是 Minimap，位置交给收纳插件，别把自己锚回地图
		if IsShiftKeyDown() and frame:GetParent() == Minimap then
			frame:SetScript("OnUpdate", DragUpdate)
		end
	end)
	b:SetScript("OnMouseUp", function(frame) frame:SetScript("OnUpdate", nil) end)
	b:SetScript("OnHide", function(frame) frame:SetScript("OnUpdate", nil) end)
	b:SetScript("OnClick", function(_, button)
		if IsShiftKeyDown() then return end
		Open(button)
	end)
	b:SetScript("OnEnter", function(frame)
		GameTooltip:SetOwner(frame, "ANCHOR_BOTTOMLEFT")
		GameTooltip:AddLine(L.MinimapTip)
		GameTooltip:AddLine(L.MinimapTip1, 1, 1, 1)
		GameTooltip:AddLine(L.MinimapTip2, 1, 1, 1)
		GameTooltip:AddLine(L.MinimapTip3, 1, 1, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)

	self.minimapButton = b
end
