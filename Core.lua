-- RaidLockView - Core.lua
-- 数据层：存档、角色记录、锁定扫描、显示数据、事件与斜杠命令。

local ADDON, ns = ...
local L = ns.L

local eventFrame = CreateFrame("Frame")

-- 存档

function ns:InitDB()
	local db = RaidLockViewDB or {}
	RaidLockViewDB = db
	db.chars        = db.chars or {}
	db.showRaids    = db.showRaids or {}
	db.showChars    = db.showChars or {}
	db.showRealms   = db.showRealms or {}
	db.extraRaids   = db.extraRaids or {}
	db.seenRaids    = db.seenRaids or {}
	db.currentPhase = db.currentPhase or 6
	db.maxLevel     = db.maxLevel or 80
	db.minimap      = db.minimap or { angle = 218 }
	if db.markIncomplete == nil then db.markIncomplete = true end
	for _, r in ipairs(ns.RAIDS) do
		if db.showRaids[r.key] == nil then db.showRaids[r.key] = true end
	end
	ns.db = db
	ns:MigrateExtraRaids()
end

-- 旧存档里被误收录成未知团本的条目（如"太阳之井"）能按别名认回来时，把记录并到规范 key
function ns:MigrateExtraRaids()
	for name in pairs(self.db.extraRaids) do
		local raid = ns.RAID_LOOKUP[name]
		if raid and raid.key ~= name then
			for _, c in pairs(self.db.chars) do
				if c.lockouts and c.lockouts[name] then
					c.lockouts[raid.key] = c.lockouts[raid.key] or c.lockouts[name]
					c.lockouts[name] = nil
				end
			end
			if self.db.seenRaids[name] then
				self.db.seenRaids[raid.key] = true
				self.db.seenRaids[name] = nil
			end
			if self.db.showRaids[name] ~= nil then
				if self.db.showRaids[raid.key] == nil then
					self.db.showRaids[raid.key] = self.db.showRaids[name]
				end
				self.db.showRaids[name] = nil
			end
			self.db.extraRaids[name] = nil
		end
	end
end

function ns:GetCurrentPhase()
	return self.db.currentPhase
end

function ns:SetCurrentPhase(n)
	self.db.currentPhase = math.max(1, math.min(ns.MAX_PHASE, tonumber(n) or self:GetCurrentPhase()))
end

function ns:MarkIncomplete()
	return self.db.markIncomplete ~= false
end

-- 角色

function ns:GetRealmId()
	local id = GetRealmID()
	if id and id > 0 then return id end
end

-- 角色名 / 服务器 ID 一次登录内不变，拼一次缓存（否则每次开面板都造新串）
function ns:GetCharKey()
	local k = self.charKey
	if not k then
		k = UnitName("player") .. "-" .. (self:GetRealmId() or GetRealmName())
		self.charKey = k
	end
	return k
end

-- 分组 / 勾选用的服务器键：有 ID 用 ID，老存档只有服务器名
function ns:RealmKey(c)
	return c.realmID or ("realm:" .. (c.realm or "?"))
end

-- 界面一律显示服务器名（存档里是 ID）；当前服实时取名，别服只有最后登录时的旧名
function ns:RealmLabel(c)
	if not c then return "-" end
	local id = self:GetRealmId()
	if id and c.realmID == id then return GetRealmName() end
	return c.realm or "-"
end

-- 认领当前角色：同 ID → 同名同服 → 同名且唯一一条没盖过 ID 的老条目；同名多服缺 ID 时放弃
local function FindCharKey(chars, name, realm, realmID)
	local legacy, legacyCount, byRealm
	for k, c in pairs(chars) do
		if c.name == name then
			if realmID and c.realmID == realmID then return k end
			-- 走到这里说明"两边都有 ID 但不同"，那就不能按名字认
			if c.realm == realm and (not c.realmID or not realmID) and not byRealm then
				byRealm = k
			end
			if not c.realmID then
				legacyCount = (legacyCount or 0) + 1
				legacy = legacy or k
			end
		end
	end
	if byRealm then return byRealm end
	if legacyCount == 1 then return legacy end
	return nil
end

function ns:UpdateCurrentChar()
	local name, realm = UnitName("player"), GetRealmName()
	local realmID = self:GetRealmId()
	local key = name .. "-" .. (realmID or realm)

	local chars = self.db.chars
	local oldKey = FindCharKey(chars, name, realm, realmID)
	local c = chars[key]
	-- 只有角色集合变了才要重排；lastSeen 变了不影响顺序（服内它本来就第一）
	local resort = (c == nil) or (oldKey ~= nil and oldKey ~= key)

	if oldKey and oldKey ~= key then
		if not c then
			c = chars[oldKey]
			chars[key] = c
			if self.db.showChars[oldKey] ~= nil then
				if self.db.showChars[key] == nil then
					self.db.showChars[key] = self.db.showChars[oldKey]
				end
				self.db.showChars[oldKey] = nil
			end
		end
		chars[oldKey] = nil
	end
	if resort then self.sortedCharsDirty = true end

	c = c or {}
	chars[key] = c
	local classLocale, classFile = UnitClass("player")
	c.name      = name
	c.realm     = realm
	c.realmID   = realmID or c.realmID
	c.key       = key
	c.class     = classFile
	c.className = classLocale
	c.level     = UnitLevel("player")
	c.lastSeen  = time()
	if self.db.showChars[key] == nil then self.db.showChars[key] = true end
end

-- 阈值不采信 GetMaxPlayerLevel：定制客户端返回的是引擎上限（80 级角色会被判未满级）
function ns:GetMaxLevel()
	local lvl = tonumber(self.db.maxLevel)
	if not lvl or lvl < 1 or lvl > 100 then lvl = 80 end
	return lvl
end

-- 团本锁定扫描

-- 不关注的团本连查询都不发；表里没有的未知副本按"关注"处理，以便自动收录
function ns:IsFollowedRaid()
	local name, instType = GetInstanceInfo()
	if instType ~= "raid" or not name then return false end
	local raid = ns.RAID_LOOKUP[name]
	return self.db.showRaids[raid and raid.key or name] ~= false
end

-- GetSavedInstanceInfo: 1 name, 2 lockoutID, 3 reset, 4 difficulty, 5 locked, 6 extended,
-- 7 instanceIDMostSig, 8 isRaid, 9 maxPlayers, 10 difficultyName, 11 numEncounters, 12 encounterProgress
function ns:ScanLockouts()
	if not self.db then return end
	self.lastScanAt = time()   -- 界面按它判断"刚扫过就别再请求"
	self:UpdateCurrentChar()

	local c = self.db.chars[self:GetCharKey()]

	-- 首次 UPDATE_INSTANCE_INFO 可能早于数据就绪，count=0 不等于"没锁定"，不能清已有记录
	local count = GetNumSavedInstances()
	if count == 0 then
		if not self.raidInfoReady and c.lockouts and next(c.lockouts) then return end
	else
		self.raidInfoReady = true
	end

	-- ★ 就地更新：面板每次打开都会扫一遍，整表重建等于每次丢掉几十个表（GC 压力都记在插件账上）
	local lockouts = c.lockouts
	if not lockouts then
		lockouts = {}
		c.lockouts = lockouts
	end
	local now = time()
	local stamp = (self.scanStamp or 0) + 1
	self.scanStamp = stamp
	local changed = false

	for i = 1, count do
		local name, lockoutID, reset, _, _, _, _, isRaid, _, _,
		      numEncounters, encounterProgress = GetSavedInstanceInfo(i)

		if name and isRaid then
			local raid = ns.RAID_LOOKUP[name]
			local raidKey = raid and raid.key or name

			-- 不关注的团本不采、不写存档；未知团本 showRaids 为 nil ⇒ 仍自动收录
			if self.db.showRaids[raidKey] ~= false then
				if not raid then
					self.db.extraRaids[name] = true
					if self.db.showRaids[raidKey] == nil then
						self.db.showRaids[raidKey] = true
					end
				end
				self.db.seenRaids[raidKey] = true

				-- reset 可能是绝对时间戳，也可能是剩余秒数
				local resetAt
				if reset and reset > 0 then
					resetAt = (reset > now) and reset or (now + reset)
				end
				local total = (numEncounters and numEncounters > 0) and numEncounters or nil
				local killed = total and (encounterProgress or 0) or nil

				local prev = lockouts[raidKey]
				if prev then
					prev.stamp = stamp
					-- 剩余秒数型 reset 每次 now+reset 都差几十秒 ⇒ 1 分钟内算同一时刻
					local resetMoved = (prev.reset ~= resetAt) and
						(not prev.reset or not resetAt or math.abs(prev.reset - resetAt) > 60)
					if prev.id ~= lockoutID or prev.progressTotal ~= total
						or prev.progressKilled ~= killed or resetMoved then
						prev.id, prev.reset = lockoutID, resetAt
						prev.progressTotal, prev.progressKilled = total, killed
						prev.progress = total and (killed .. "/" .. total) or nil
						changed = true
					end
				else
					lockouts[raidKey] = {
						id             = lockoutID,
						reset          = resetAt,
						progressTotal  = total,
						progressKilled = killed,
						progress       = total and (killed .. "/" .. total) or nil,
						stamp          = stamp,
					}
					changed = true
				end
			end
		end
	end

	-- 本次没再出现的（已到期 / 取消）删掉
	for key, lo in pairs(lockouts) do
		if lo.stamp ~= stamp then
			lockouts[key] = nil
			changed = true
		end
	end

	-- 只有数据真变了才换版本号：界面靠它判断要不要重画（省掉每次开面板的全量指纹）
	if changed then self.lockVer = (self.lockVer or 0) + 1 end
	ns:RefreshUI()
end

-- now 可选：批量统计时外面读一次时钟传进来
function ns:IsLocked(c, raidKey, now)
	local lo = c.lockouts and c.lockouts[raidKey]
	return lo ~= nil and (not lo.reset or lo.reset > (now or time()))
end

-- 显示数据（两个面板共用）

-- 主界面阶段倒序、设置页正序；phase 0（不定期）一律垫底
local function PhaseOrder(desc)
	local list, idx = {}, {}
	for i, r in ipairs(ns.RAIDS) do
		list[i], idx[r] = r, i
	end
	local zeroKey = desc and -1 or 99   -- 不定期在倒序里浮顶、正序里沉底
	table.sort(list, function(a, b)
		local pa = a.phase or 0
		local pb = b.phase or 0
		pa = pa > 0 and pa or zeroKey
		pb = pb > 0 and pb or zeroKey
		if pa ~= pb then
			if desc then return pa > pb end
			return pa < pb
		end
		return idx[a] < idx[b]
	end)
	return list
end
local RAID_ORDER_MAIN = PhaseOrder(true)
local RAID_ORDER_CONF = PhaseOrder(false)

-- shownOnly 只给主界面用：设置页按勾选滤会让条目消失、再也勾不回来。
-- out 由调用方给（各调用方各备一张，避免互相踩）
local function CollectRaids(self, order, shownOnly, out)
	for i = #out, 1, -1 do out[i] = nil end
	local limit, db = self:GetCurrentPhase(), self.db
	for _, r in ipairs(order) do
		local phase = r.phase or 0
		-- 不能用 and/or：phase>0 超限时 and 结果为 false，会被 seenRaids 顶回 true
		local show
		if phase > 0 then
			show = phase <= limit
		else
			show = db.seenRaids[r.key]
		end
		if show and (not shownOnly or db.showRaids[r.key] ~= false) then
			out[#out + 1] = r
		end
	end

	-- 自动收录的未知团本按名排序垫底
	local names = self.extraNames or {}
	self.extraNames = names
	for i = #names, 1, -1 do names[i] = nil end
	for name in pairs(db.extraRaids) do names[#names + 1] = name end
	table.sort(names)

	local entries = self.extraEntries or {}
	self.extraEntries = entries
	for _, name in ipairs(names) do
		if not shownOnly or db.showRaids[name] ~= false then
			local e = entries[name]
			if not e then e = { key = name, label = name }; entries[name] = e end
			out[#out + 1] = e
		end
	end
	return out
end

function ns:GetSortedRaids()
	local buf = self.raidsBuf
	if not buf then buf = {}; self.raidsBuf = buf end
	return CollectRaids(self, RAID_ORDER_MAIN, true, buf)
end

function ns:GetConfigRaids()
	local buf = self.cfgRaidsBuf
	if not buf then buf = {}; self.cfgRaidsBuf = buf end
	return CollectRaids(self, RAID_ORDER_CONF, false, buf)
end

-- 当前服最前、其余按该服最近登录倒序；服内当前角色第一，其余按最近登录。
-- ★ 返回的表只读；任何增删 db.chars 处都要手动置 sortedCharsDirty
function ns:GetSortedChars()
	local cached = self.sortedChars
	if cached and not self.sortedCharsDirty then return cached end

	local out, realmSeen, realmOf = {}, {}, {}
	for key, c in pairs(self.db.chars) do
		c.key = key
		out[#out + 1] = c
		local rk = self:RealmKey(c)   -- 会拼字符串，排序比较里每比一次都算就白造临时串
		realmOf[key] = rk
		local t = c.lastSeen or 0
		if not realmSeen[rk] or t > realmSeen[rk] then realmSeen[rk] = t end
	end

	local myRealm, myKey = self:GetRealmId(), self:GetCharKey()
	table.sort(out, function(a, b)
		local ak, bk = realmOf[a.key], realmOf[b.key]
		if ak ~= bk then
			local ar = (myRealm and a.realmID == myRealm) and 0 or 1
			local br = (myRealm and b.realmID == myRealm) and 0 or 1
			if ar ~= br then return ar < br end
			local as, bs = realmSeen[ak] or 0, realmSeen[bk] or 0
			if as ~= bs then return as > bs end
			return tostring(ak) < tostring(bk)
		end
		if a.key == myKey or b.key == myKey then return a.key == myKey end
		if a.lastSeen ~= b.lastSeen then return (a.lastSeen or 0) > (b.lastSeen or 0) end
		return a.key < b.key
	end)
	self.sortedChars, self.sortedCharsDirty = out, nil
	return out
end

-- 勾选显示的满级角色（服务器勾选 > 角色勾选）
function ns:GetVisibleChars(realmKey)
	local out = self.charsBuf
	if not out then out = {}; self.charsBuf = out end
	for i = #out, 1, -1 do out[i] = nil end
	local db, lvl = self.db, self:GetMaxLevel()
	for _, c in ipairs(self:GetSortedChars()) do
		if db.showChars[c.key] == nil then db.showChars[c.key] = true end
		local rk = self:RealmKey(c)
		if db.showChars[c.key]
			and db.showRealms[rk] ~= false
			and (c.level or 0) >= lvl
			and (not realmKey or rk == realmKey) then
			out[#out + 1] = c
		end
	end
	return out
end

function ns:GetRealmOptions()
	local out = self.realmOptBuf
	if not out then out = {}; self.realmOptBuf = out end
	for i = #out, 1, -1 do out[i] = nil end
	local cache = self.realmOptEntry
	if not cache then cache = {}; self.realmOptEntry = cache end
	local seen = self.realmOptSeen
	if not seen then seen = {}; self.realmOptSeen = seen end
	for k in pairs(seen) do seen[k] = nil end
	local lvl = self:GetMaxLevel()
	for _, c in ipairs(self:GetSortedChars()) do
		local k = self:RealmKey(c)
		if not seen[k] and self.db.showRealms[k] ~= false and (c.level or 0) >= lvl then
			seen[k] = true
			local e = cache[k]
			if not e then e = {}; cache[k] = e end
			e.key, e.label = k, self:RealmLabel(c)
			out[#out + 1] = e
		end
	end
	return out
end

-- 面板 / 设置页

function ns:Toggle()
	local f = self.mainFrame
	if f then
		if f:IsShown() then f:Hide() else f:Show() end
		return
	end
	-- ★ 必须延到下一帧：在鼠标按下的同一次调用里建一大批 frame，本客户端会丢掉这次点击
	if self.opening then return end
	self.opening = true
	C_Timer.After(0, function()
		self.opening = false
		self:BuildMainFrame():Show()   -- OnShow 里统一 RequestRaidInfo + RefreshUI
	end)
end

function ns:OpenOptions()
	Settings.OpenToCategory(self.optionsCategory:GetID())
end

-- 事件

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UPDATE_INSTANCE_INFO")
eventFrame:RegisterEvent("ENCOUNTER_END")

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local arg1 = ...
	if event == "ADDON_LOADED" and arg1 == ADDON then
		ns:InitDB()
		ns:UpdateCurrentChar()
		ns:InitMinimap()
	elseif event == "PLAYER_ENTERING_WORLD" then
		if ns.db then
			ns:UpdateCurrentChar()
			RequestRaidInfo()
		end
	elseif event == "UPDATE_INSTANCE_INFO" then
		ns:ScanLockouts()
	elseif event == "ENCOUNTER_END" then
		-- 灭团也触发（success=0），只认击杀；回包后走 UPDATE_INSTANCE_INFO 重扫
		local success = select(5, ...)
		if (success == 1 or success == true) and ns:IsFollowedRaid() then
			RequestRaidInfo()
		end
	end
end)

-- 斜杠命令

SLASH_RAIDLOCKVIEW1 = "/raidlockview"
SLASH_RAIDLOCKVIEW2 = "/rlv"

SlashCmdList["RAIDLOCKVIEW"] = function(msg)
	msg = (msg or ""):lower():gsub("%s", "")
	if msg == L.CmdMaxLevel then
		print(string.format(L.MaxLevelIs, ns:GetMaxLevel()))
		return
	end
	local n = tonumber(msg:match("^" .. L.CmdMaxLevel .. "(%d+)$"))
	if not n then
		ns:Toggle()
		return
	end
	if n >= 1 and n <= 100 then
		ns.db.maxLevel = n
		print(string.format(L.MaxLevelSet, n))
		ns:RefreshUI()
	else
		print(L.MaxLevelBad)
	end
end
