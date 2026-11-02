-- RaidLockView - Localization.lua
-- 界面文案。单目标客户端（泰坦重铸仅有 zhCN），只维护中文。

local _, ns = ...

ns.L = {
	TitlePhase     = "团队副本进度总览[|cff33ff66P%d|r]",
	ColRaid        = "团队副本",
	FilterAll      = "全部服务器角色",
	BtnRefresh     = "刷新",
	BtnConfig      = "配置",
	Phase          = "阶段",
	PhaseIrregular = "不定期",
	Progress       = "进度",
	ResetAt        = "重置时间",
	LastSeen       = "上次登录",
	Level          = "等级",
	Class          = "职业",
	Realm          = "服务器",
	Current        = "当前角色",
	NoCharData     = "暂无角色数据。用账号内各角色登录一次后自动记录。",
	Locked         = "已锁定",
	NotLocked      = "未锁定",
	FreeCount      = "未锁定/总数",
	LockedCount    = "已锁定数",
	Unknown        = "未知团本（自动收录）",

	OptPanel       = "泰坦团本进度",
	OptTitle       = "RaidLockView - 团队副本进度总览",
	OptHint        = "设置插件表格中显示的团本和角色",
	SecDisplay     = "显示设置",
	SecRaids       = "团队副本",
	SecChars       = "角色管理",
	OptPhase       = "当前阶段",
	PhaseVal       = "P%d",
	MarkIncomplete = "标记未全通副本",
	OnlyMaxLevel   = "仅显示满级角色",
	OnlyMaxLevelTip = "只统计等级不低于 %d 的角色。阈值用 /rlv maxlevel N 调整。",
	DeleteChar     = "删除角色",
	DeleteCharTip  = "双击删除「%s」的存档数据",

	MinimapTip     = "|cff33ff66泰坦团本进度|r",
	MinimapTip1    = "左键：打开/关闭面板",
	MinimapTip2    = "右键：打开配置",
	MinimapTip3    = "Shift+拖动：移动图标",

	-- 斜杠命令关键字：不同语言用不同词，别写死在 Core 里
	CmdMaxLevel = "maxlevel",

	MaxLevelIs     = "当前满级阈值：%d（用 /rlv maxlevel N 修改）",
	MaxLevelSet    = "满级阈值已设为 %d。",
	MaxLevelBad    = "无效等级，用法：/rlv maxlevel 80",
}
