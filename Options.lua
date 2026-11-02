-- RaidLockView - Options.lua
-- 设置面板：显示设置 / 团队副本（盒高=内容）/ 角色管理（盒高=内容，封顶 200 才滚）。

local ADDON, ns = ...
local UI = ns.UI
local L = ns.L

local LABEL_X     = 10     -- 内容行缩进
local ROW_GAP     = 80     -- 标签文字与控件之间的间隙
local CHECK_INSET = 3      -- 勾选框美术内缩，补回来"看得见的框"才对齐
local STEP        = 28
local SEC_GAP     = 12
local SEC_H       = 20
local BOX_PAD     = 8
local CHAR_BOX_H  = 200
local ROW_H       = 30     -- 勾选框本身 30×29，行高不足会互相压住点击区
local RAID_COLS   = 2
local COL_GAP     = 12
local GROUP_H     = 30
local GROUP_GAP   = 2
local CHAR_INDENT = 16
local SLIDER_W    = 200
local DEL_SIZE    = 20
local DEL_RIGHT   = 23
local DEL_SPACE   = DEL_SIZE + DEL_RIGHT + 4

-- 顶部标题区（照 SettingsListTemplate.Header）
local TITLE_Y      = -8
local TITLE_LINE_DY = 38
local TITLE_GAP    = 14
local SCROLL_TOP   = TITLE_Y - TITLE_LINE_DY - TITLE_GAP
local SCROLL_RIGHT = -14

local TEXT_WHITE = { 1, 1, 1 }
local TEXT_GOLD  = { 1, 0.82, 0 }
local TEXT_DIM   = { 0.45, 0.45, 0.45 }

local Options = {}
ns.Options = Options

local function Tint(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

-- 控件

local function CreateLabel(parent, text)
	local f = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f:SetJustifyH("LEFT")
	f:SetText(text)
	Tint(f, TEXT_WHITE)
	return f
end

local function CreateSectionHeader(parent, text)
	local f = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f:SetText(text)
	Tint(f, TEXT_GOLD)
	return f
end

-- TooltipBackdropTemplate 的细亮边，底色全透明只要那一圈
local function CreateBox(parent)
	local box = CreateFrame("Frame", nil, parent, "TooltipBackdropTemplate")
	box:SetBackdropColor(0, 0, 0, 0)
	box:SetBackdropBorderColor(0.62, 0.62, 0.62, 1)
	box.NineSlice:SetFrameLevel(box:GetFrameLevel())   -- 默认层级会盖住勾选框
	box:SetSize(480, CHAR_BOX_H)
	return box
end

-- 文字由调用方用 cb.label 填（FitText 截断）
local function MakeCheckbox(parent, onToggle)
	local cb = CreateFrame("CheckButton", nil, parent, "MinimalCheckboxTemplate")
	cb:SetSize(30, 29)
	cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	cb.label:SetJustifyH("LEFT")
	cb.label:SetPoint("LEFT", cb, "RIGHT", 8, 0)
	Tint(cb.label, TEXT_WHITE)
	cb:SetScript("OnClick", function(self)
		if onToggle then onToggle(self:GetChecked()) end
	end)
	return cb
end

-- 纯红大叉（团队标记"移除"同款）；CancelButton-Up 带暗红圆底，别用
local DELETE_TEX = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"

local function MakeDeleteButton(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(DEL_SIZE, DEL_SIZE)
	b:SetNormalTexture(DELETE_TEX)
	b:SetPushedTexture(DELETE_TEX)
	b:SetHighlightTexture(DELETE_TEX, "ADD")
	-- ★ Set*Texture 建出的贴图是原图 32×32 居中、不随按钮缩放 ⇒ 必须自己铺满
	for _, t in ipairs({ b:GetNormalTexture(), b:GetPushedTexture(), b:GetHighlightTexture() }) do
		t:ClearAllPoints()
		t:SetAllPoints(b)
	end
	return b
end

-- MinimalSliderTemplate：Middle 段即"已填充"，看着就是进度条
local function CreatePhaseSlider(parent)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(15 + SLIDER_W + 15 + 8 + 30, 25)

	local slider = CreateFrame("Slider", nil, holder, "MinimalSliderTemplate")
	slider:SetSize(SLIDER_W, 19)
	slider:SetPoint("LEFT", holder, "LEFT", 15, 0)
	slider:SetMinMaxValues(1, ns.MAX_PHASE)
	slider:SetValueStep(1)
	slider:SetObeyStepOnDrag(true)

	local function StepButton(atlas, w, h, dir)
		local b = CreateFrame("Button", nil, holder)
		b:SetSize(w, h)
		b.tex = b:CreateTexture(nil, "BACKGROUND")
		b.tex:SetAtlas(atlas, true)
		b.tex:SetPoint("CENTER")
		if dir < 0 then
			b:SetPoint("RIGHT", slider, "LEFT", -4, 0)
		else
			b:SetPoint("LEFT", slider, "RIGHT", 4, 0)
		end
		return b
	end
	local back = StepButton("Minimal_SliderBar_Button_Left", 11, 19, -1)
	local fwd  = StepButton("Minimal_SliderBar_Button_Right", 9, 18, 1)

	local valueText = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	valueText:SetPoint("LEFT", fwd, "RIGHT", 10, 0)
	Tint(valueText, TEXT_WHITE)

	local syncing, shown = false, nil
	local function ShowPhase(n)
		if shown == n then return end   -- 没变就不重排（每次开面板都会 sync）
		shown = n
		valueText:SetText(string.format(L.PhaseVal, n))
	end
	local function Clamp(n)
		n = math.floor((tonumber(n) or 1) + 0.5)
		if n < 1 then return 1 elseif n > ns.MAX_PHASE then return ns.MAX_PHASE end
		return n
	end
	-- 落档才重建：拖动中每经过一档都会发 OnValueChanged，在那里重建就是净增（控件不回收）
	local function Commit(n)
		n = Clamp(n)
		ShowPhase(n)
		if n == ns:GetCurrentPhase() then return end
		ns:SetCurrentPhase(n)
		Options:RefreshLists()   -- 阶段已进 raidSig，团本勾选按需重建一次
		ns:RefreshUI()
	end

	slider:SetScript("OnValueChanged", function(_, v)
		if not syncing then ShowPhase(Clamp(v)) end
	end)
	slider:SetScript("OnMouseUp", function(s) Commit(s:GetValue()) end)
	back:SetScript("OnClick", function() Commit(ns:GetCurrentPhase() - 1) end)
	fwd:SetScript("OnClick", function() Commit(ns:GetCurrentPhase() + 1) end)

	return {
		holder = holder,
		slider = slider,
		sync = function()
			local n = ns:GetCurrentPhase()
			syncing = true
			slider:SetValue(n)
			syncing = false
			ShowPhase(n)
		end,
	}
end

-- 本客户端没有可用的 SCROLL_FRAME_SCROLL_BAR_TEMPLATE，滚动条自建
local function MakeScroll(parent, barDX, barDY)
	local s = CreateFrame("ScrollFrame", nil, parent)
	local b = CreateFrame("EventFrame", nil, s, "MinimalScrollBar")
	b:SetPoint("TOPLEFT", s, "TOPRIGHT", barDX, -4)
	b:SetPoint("BOTTOMLEFT", s, "BOTTOMRIGHT", barDX, barDY)
	ScrollUtil.InitScrollFrameWithScrollBar(s, b)
	s.bar = b
	return s
end

local function CreateInnerScroll(box)
	local s = MakeScroll(box, 2, 6)
	s:SetPoint("TOPLEFT", box, "TOPLEFT", BOX_PAD, -BOX_PAD)
	s:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -BOX_PAD - 20, BOX_PAD)
	s.bar:Hide()

	local inner = CreateFrame("Frame", nil, s)
	s:SetScrollChild(inner)
	return s, inner
end

local function ClearChildren(inner)
	for _, child in ipairs({ inner:GetChildren() }) do
		child:Hide()   -- 必须先藏：SetParent(nil) 只是挂回 UIParent，帧照样显示、也不回收
		child:SetParent(nil)
	end
end

-- 盖在滚动区上的鼠标框会吃掉滚轮，统一往 scroll 转一手
local function WheelTo(scroll)
	return function(_, delta)
		local handler = scroll:GetScript("OnMouseWheel")
		if handler then handler(scroll, delta) end
	end
end

local function CreateTitle(parent, scroll)
	local title = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
	title:SetJustifyH("LEFT")
	title:SetText(L.OptTitle)

	local line = parent:CreateTexture(nil, "ARTWORK")
	line:SetAtlas("Options_HorizontalDivider", true)

	-- FontString 收不到鼠标事件，提示挂在一块透明小框上
	local hover = CreateFrame("Frame", nil, parent)
	hover:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
	hover:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
	hover:SetHeight(48)
	hover:EnableMouse(true)
	hover:SetScript("OnEnter", function(f)
		GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L.OptPanel, 1, 1, 1, true)
		GameTooltip:AddLine(L.OptHint, 0.9, 0.9, 0.9, true)
		GameTooltip:Show()
	end)
	hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
	hover:SetScript("OnMouseWheel", WheelTo(scroll))
	return title, line
end

-- 面板

function Options:Build()
	local panel = CreateFrame("Frame")
	panel.name = ADDON
	panel:Hide()   -- CreateFrame 默认显示，先藏好等设置界面挂载
	self.panel = panel

	panel:SetScript("OnShow", function()
		if not self.content then self:BuildContent() end
		-- 填满 canvas 可视区：外层不产生第二根滚动条，滚动交给内嵌 scroll
		panel:ClearAllPoints()
		panel:SetAllPoints(panel:GetParent())
		if self.scroll:GetWidth() > 0 then self.content:SetWidth(self.scroll:GetWidth()) end
		-- ★ 不能 force：控件不回收，每次开设置页重建一遍就是净增几百 KB
		--   首次 raidSig/charSig 为 nil 自然会建，之后只有成员真变才建
		self:Reload()
		-- 回顶部：上次翻到哪是上次的事
		self.scroll:SetVerticalScroll(0)
		self.charScroll:SetVerticalScroll(0)
		UI.SyncScrollBar(self.charScroll)
	end)
end

function Options:BuildContent()
	local panel = self.panel

	local scroll = MakeScroll(panel, -1, 7)
	scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, SCROLL_TOP)
	scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", SCROLL_RIGHT, 4)
	self.scroll = scroll

	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(520, 600)
	scroll:SetScrollChild(content)
	self.content = content

	scroll:SetScript("OnSizeChanged", function(_, w)
		if w > 0 then content:SetWidth(w) end
	end)

	self.title, self.titleLine = CreateTitle(panel, scroll)
	self:BuildDisplay(content)
	self:BuildRaids(content)
	self:BuildChars(content)
end

function Options:BuildDisplay(parent)
	self.displayHeader = CreateSectionHeader(parent, L.SecDisplay)

	self.phaseLabel = CreateLabel(parent, L.OptPhase)
	self.phaseSlider = CreatePhaseSlider(parent)

	self.markLabel = CreateLabel(parent, L.MarkIncomplete)
	self.markCheck = MakeCheckbox(parent, function(checked)
		ns.db.markIncomplete = checked
		ns:RefreshUI()
	end)
	-- 勾选框在滚动区里会吃掉滚轮 ⇒ 转给列表
	self.markCheck:EnableMouseWheel(true)
	self.markCheck:SetScript("OnMouseWheel", WheelTo(self.scroll))

	-- 满级过滤固定开启（不可取消）
	self.maxLabel = CreateLabel(parent, L.OnlyMaxLevel)
	Tint(self.maxLabel, TEXT_DIM)
	self.maxCheck = MakeCheckbox(parent)
	self.maxCheck:SetChecked(true)
	self.maxCheck:SetEnabled(false)

	-- 提示挂整行；勾选框已禁用，被盖住也不吃点击
	self.maxHover = CreateFrame("Frame", nil, parent)
	self.maxHover:SetPoint("LEFT", self.maxLabel, "LEFT", 0, 0)
	self.maxHover:SetPoint("RIGHT", self.maxCheck, "RIGHT", 4, 0)
	self.maxHover:SetHeight(STEP)
	self.maxHover:SetFrameLevel(self.maxCheck:GetFrameLevel() + 1)
	self.maxHover:EnableMouse(true)
	self.maxHover:SetScript("OnEnter", function(f)
		GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L.OnlyMaxLevel, 1, 1, 1, true)
		GameTooltip:AddLine(string.format(L.OnlyMaxLevelTip, ns:GetMaxLevel()), 0.9, 0.9, 0.9, true)
		GameTooltip:Show()
	end)
	self.maxHover:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- 控件左缘统一成一条竖线：列位 = 最长标签实测宽 + 间隙
	local labelW = math.max(self.phaseLabel:GetStringWidth() or 0,
		self.markLabel:GetStringWidth() or 0,
		self.maxLabel:GetStringWidth() or 0)
	self.ctrlX = LABEL_X + labelW + ROW_GAP
end

function Options:BuildRaids(parent)
	self.raidHeader = CreateSectionHeader(parent, L.SecRaids)
	self.raidBox = CreateBox(parent)
	-- 不滚：盒高由 Layout 按内容定，内容帧直接铺在盒里
	self.raidInner = CreateFrame("Frame", nil, self.raidBox)
	self.raidInner:SetPoint("TOPLEFT", BOX_PAD, -BOX_PAD)
	self.raidContentH = 0
end

function Options:BuildChars(parent)
	self.charHeader = CreateSectionHeader(parent, L.SecChars)
	self.charBox = CreateBox(parent)
	self.charScroll, self.charInner = CreateInnerScroll(self.charBox)
	self.charContentH = 0
end

-- 列表（成员变了才重建，否则只同步勾选）

function Options:BuildRaidRows()
	local innerW = self.raidInner:GetWidth()
	local cellW = math.floor((innerW - COL_GAP) / RAID_COLS)
	local raids = ns:GetConfigRaids()

	-- 池化：控件不回收，按 key 复用；切阶段只改文字与位置（否则每档净增 23 个勾选框）
	self.raidPool = self.raidPool or {}
	local pool, shown = self.raidPool, {}
	self.raidRows = {}
	for i, r in ipairs(raids) do
		local key = r.key
		local cb = pool[key]
		if not cb then
			cb = MakeCheckbox(self.raidInner, function(checked)
				ns.db.showRaids[key] = checked
				-- 勾上的团本存档里可能是空的（未关注时不采），当场问一次补上
				if checked then RequestRaidInfo() end
				ns:RefreshUI()
			end)
			pool[key] = cb
		end
		shown[key] = true
		cb:Show()
		local suffix = (r.phase and r.phase > 0)
			and ("  |cff888888P" .. r.phase .. "|r")
			or ("  |cff888888" .. L.PhaseIrregular .. "|r")
		UI.FitText(cb.label, ns.RaidLabel(r), suffix, cellW - 44)
		local col, row = (i - 1) % RAID_COLS, math.floor((i - 1) / RAID_COLS)
		cb:ClearAllPoints()
		cb:SetPoint("TOPLEFT", self.raidInner, "TOPLEFT",
			-CHECK_INSET + col * (cellW + COL_GAP), -row * ROW_H)
		self.raidRows[#self.raidRows + 1] = { key = key, cb = cb }
	end
	-- 阶段回退后多出来的行收起来（留着下次复用）
	for key, cb in pairs(pool) do
		if not shown[key] then cb:Hide() end
	end

	local h = math.ceil(#raids / RAID_COLS) * ROW_H
	self.raidInner:SetHeight(math.max(h, 1))
	self.raidContentH = math.max(h, ROW_H)
end

function Options:BuildCharRows()
	ClearChildren(self.charInner)
	self.realmRows = {}

	-- GetSortedChars 已把当前服排前、当前角色排第一，按首次出现定组序即可
	local groups, index, lvl = {}, {}, ns:GetMaxLevel()
	for _, c in ipairs(ns:GetSortedChars()) do
		if (c.level or 0) >= lvl then
			local k = ns:RealmKey(c)
			local g = index[k]
			if not g then
				g = { key = k, label = ns:RealmLabel(c), chars = {} }
				index[k] = g
				groups[#groups + 1] = g
			end
			g.chars[#g.chars + 1] = c
		end
	end

	local innerW = self.charInner:GetWidth()
	local forward = WheelTo(self.charScroll)
	local y = 0
	for _, g in ipairs(groups) do
		local groupKey = g.key
		local realmCB = MakeCheckbox(self.charInner, function(checked)
			ns.db.showRealms[groupKey] = checked
			Options:SyncChecks()
			ns:RefreshUI()
		end)
		Tint(realmCB.label, TEXT_GOLD)
		UI.FitText(realmCB.label, g.label, "", innerW - 44)
		realmCB:SetPoint("TOPLEFT", self.charInner, "TOPLEFT", -CHECK_INSET, -y)
		y = y + GROUP_H

		local rows = {}
		for _, c in ipairs(g.chars) do
			-- Tint 取 [1][2][3]，而 RAID_CLASS_COLORS 是 r/g/b 键 ⇒ 先掰成三元组
			local classColor = RAID_CLASS_COLORS[c.class]
			local rgb = classColor and { classColor.r, classColor.g, classColor.b }
			local suffix = string.format("  |cff888888Lv.%d · %s %s|r",
				c.level or 0, L.LastSeen, UI.FormatTime(c.lastSeen, "%Y-%m-%d"))
			local key = c.key
			local cb = MakeCheckbox(self.charInner, function(checked)
				ns.db.showChars[key] = checked
				ns:RefreshUI()
			end)
			if rgb then Tint(cb.label, rgb) end
			UI.FitText(cb.label, c.name or "?", suffix, innerW - 44 - CHAR_INDENT - DEL_SPACE)
			cb:SetPoint("TOPLEFT", self.charInner, "TOPLEFT", -CHECK_INSET + CHAR_INDENT, -y)

			-- 行底高亮：盖满整行、压在下层（勾选框要高一层才点得到）
			local hit = CreateFrame("Frame", nil, self.charInner)
			hit:SetPoint("TOPLEFT", self.charInner, "TOPLEFT", -CHECK_INSET + CHAR_INDENT, -y)
			hit:SetPoint("TOPRIGHT", self.charInner, "TOPRIGHT", 0, -y)
			hit:SetHeight(ROW_H)
			hit:SetFrameLevel(self.charInner:GetFrameLevel())
			hit.bg = hit:CreateTexture(nil, "BACKGROUND")
			hit.bg:SetAllPoints(hit)
			UI.Fill(hit.bg, UI.ROW_HOVER)
			hit.bg:Hide()
			hit:EnableMouse(true)
			hit:EnableMouseWheel(true)   -- 不开这个也吃滚轮，只是收不到事件

			-- 当前角色不给删（删了下次登录又被收录）
			local xBtn
			if key ~= ns:GetCharKey() then
				xBtn = MakeDeleteButton(self.charInner)
				xBtn:SetPoint("RIGHT", hit, "RIGHT", -DEL_RIGHT, 0)
				xBtn:SetFrameLevel(hit:GetFrameLevel() + 1)
				xBtn:Hide()   -- 只在悬停时露出来
			end

			local function RowOn()
				hit.bg:Show()
				if xBtn then xBtn:Show() end
			end
			-- 从勾选框 / 删除按钮挪进挪出都还算"在本行"
			local function RowOff()
				if hit:IsMouseOver() or cb:IsMouseOver() or (xBtn and xBtn:IsMouseOver()) then return end
				hit.bg:Hide()
				if xBtn then xBtn:Hide() end
				GameTooltip:Hide()
			end

			hit:SetScript("OnEnter", RowOn)
			hit:SetScript("OnLeave", RowOff)
			cb:SetScript("OnEnter", RowOn)   -- 勾选框高一层，收不到 hit 的事件
			cb:SetScript("OnLeave", RowOff)
			hit:SetScript("OnMouseWheel", forward)
			cb:EnableMouseWheel(true)
			cb:SetScript("OnMouseWheel", forward)
			if xBtn then
				xBtn:EnableMouseWheel(true)
				xBtn:SetScript("OnMouseWheel", forward)
				xBtn:SetScript("OnEnter", function(self)
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:AddLine(L.DeleteChar, 1, 1, 1, true)
					GameTooltip:AddLine(string.format(L.DeleteCharTip, c.name or "?"), 0.9, 0.9, 0.9, true)
					GameTooltip:Show()
				end)
				xBtn:SetScript("OnLeave", function()
					GameTooltip:Hide()
					RowOff()
				end)
				xBtn:SetScript("OnDoubleClick", function()
					GameTooltip:Hide()
					-- 只删数据、不留墓碑（勾选一起清，留 false 会让它重新收录后被静默藏掉）
					ns.db.chars[key] = nil
					ns.db.showChars[key] = nil
					ns.sortedCharsDirty = true   -- GetSortedChars 有缓存
					Options:RefreshLists()       -- charSig 变了自己会重建
					ns:RefreshUI()
				end)
			end

			rows[#rows + 1] = { key = key, cb = cb, color = rgb, hit = hit, x = xBtn }
			y = y + ROW_H
		end

		self.realmRows[#self.realmRows + 1] = { key = groupKey, cb = realmCB, rows = rows }
		y = y + GROUP_GAP
	end
	self.charInner:SetHeight(math.max(y, 1))
	self.charContentH = math.max(y, ROW_H)
end

function Options:SyncChecks()
	self.markCheck:SetChecked(ns:MarkIncomplete())
	for _, row in ipairs(self.raidRows) do
		row.cb:SetChecked(ns.db.showRaids[row.key] ~= false)
	end
	for _, g in ipairs(self.realmRows) do
		local on = ns.db.showRealms[g.key] ~= false
		g.cb:SetChecked(on)
		for _, row in ipairs(g.rows) do
			row.cb:SetChecked(ns.db.showChars[row.key] ~= false)
			row.cb:SetEnabled(on)   -- 整服关掉时其下角色不可单独操作
			Tint(row.cb.label, on and (row.color or TEXT_WHITE) or TEXT_DIM)
		end
	end
end

function Options:RefreshLists(force)
	-- 盒宽先算好（建行要用它算列宽）；盒高得等行建完，末尾再排一次
	self:FitWidths()

	-- 只在成员变化时重建，避免每次点勾选都把滚动条弹回顶部
	local raidParts = self.raidSigBuf
	if not raidParts then raidParts = {}; self.raidSigBuf = raidParts end
	for i = #raidParts, 1, -1 do raidParts[i] = nil end
	raidParts[1] = ns:GetCurrentPhase()
	local raids = ns:GetConfigRaids()
	for i = 1, #raids do raidParts[i + 1] = raids[i].key end
	local raidSig = table.concat(raidParts, "|")

	local lvl = ns:GetMaxLevel()
	local charParts = self.charSigBuf
	if not charParts then charParts = {}; self.charSigBuf = charParts end
	for i = #charParts, 1, -1 do charParts[i] = nil end
	local n = 0
	for _, c in ipairs(ns:GetSortedChars()) do
		if (c.level or 0) >= lvl then
			n = n + 1
			charParts[n] = c.key
		end
	end
	local charSig = table.concat(charParts, "|", 1, n)

	if force or raidSig ~= self.raidSig then
		self.raidSig = raidSig
		self:BuildRaidRows()
	end
	if force or charSig ~= self.charSig then
		self.charSig = charSig
		self:BuildCharRows()
	end
	self:SyncChecks()
	self:Layout()
	UI.SyncScrollBar(self.charScroll)
end

-- 盒宽只跟面板宽有关：列表行按它算列宽，所以建行前先来一次
function Options:FitWidths()
	local w = self.content:GetWidth()
	if w < 100 then w = 520 end
	self.boxW = w - 8
	self.raidInner:SetWidth(self.boxW - BOX_PAD * 2)          -- 团本盒没有滚动条，不留右侧 20px
	self.charInner:SetWidth(self.boxW - BOX_PAD * 2 - 20)
end

-- 需先跑 FitWidths（RefreshLists 在建行前已算，boxW 在这里用）
function Options:Layout()
	local content = self.content

	-- 团本盒：高度随内容（不滚）；角色盒：高度随内容，上限 CHAR_BOX_H
	local raidBoxH = self.raidContentH + BOX_PAD * 2
	local charBoxH = math.min(self.charContentH + BOX_PAD * 2, CHAR_BOX_H)

	-- 控件都在 BuildContent 里建好，列表建一次就够（Layout 每次开面板都会跑）
	local cleared = self.layoutList
	if not cleared then
		cleared = {
			self.title, self.titleLine,
			self.displayHeader, self.phaseLabel, self.phaseSlider.holder,
			self.markLabel, self.markCheck,
			self.maxLabel, self.maxCheck,
			self.raidHeader, self.raidBox, self.charHeader, self.charBox,
		}
		self.layoutList = cleared
	end
	for i = 1, #cleared do cleared[i]:ClearAllPoints() end

	local y = 0
	local rowMid = STEP / 2

	-- 标题 + 横线锚在面板上（不参与滚动）
	self.title:SetPoint("TOPLEFT", LABEL_X, TITLE_Y)
	local lineY = TITLE_Y - TITLE_LINE_DY
	self.titleLine:SetPoint("TOPLEFT", 0, lineY)
	self.titleLine:SetPoint("TOPRIGHT", 0, lineY)

	-- ① 显示设置：标签 + 间隙 + 控件，控件共一条竖线
	self.displayHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 4, y)
	y = y - SEC_H

	self.phaseLabel:SetPoint("LEFT", content, "TOPLEFT", LABEL_X, y - rowMid)
	self.phaseSlider.holder:SetPoint("LEFT", content, "TOPLEFT", self.ctrlX, y - rowMid)
	y = y - STEP

	self.markLabel:SetPoint("LEFT", content, "TOPLEFT", LABEL_X, y - rowMid)
	-- 勾选框美术内缩 CHECK_INSET，减掉才是看得见的列位
	self.markCheck:SetPoint("LEFT", content, "TOPLEFT", self.ctrlX - CHECK_INSET, y - rowMid)
	y = y - STEP

	self.maxLabel:SetPoint("LEFT", content, "TOPLEFT", LABEL_X, y - rowMid)
	self.maxCheck:SetPoint("LEFT", content, "TOPLEFT", self.ctrlX - CHECK_INSET, y - rowMid)
	y = y - STEP

	y = y - SEC_GAP
	self.raidHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 4, y)
	y = y - SEC_H
	self.raidBox:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
	self.raidBox:SetSize(self.boxW, raidBoxH)
	y = y - raidBoxH

	y = y - SEC_GAP
	self.charHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 4, y)
	y = y - SEC_H
	self.charBox:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
	self.charBox:SetSize(self.boxW, charBoxH)
	y = y - charBoxH - 10

	content:SetHeight(-y + 12)
end

function Options:Reload(force)
	self.phaseSlider.sync()
	self:RefreshLists(force)
end

Options:Build()

-- 侧栏里的名字固定用 ADDON（缺省语言下的插件名），不随客户端语言变
local category = Settings.RegisterCanvasLayoutCategory(Options.panel, ADDON)
Settings.RegisterAddOnCategory(category)
ns.optionsCategory = category
