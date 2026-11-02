-- RaidLockView - Data.lua
-- 团本静态数据：中文名 → 阶段，以及按副本名反查。

local _, ns = ...

-- 表内顺序 = 同阶段内的显示顺序；phase = 0 表示不定期团本
ns.RAIDS = {
	{ key = "MC",    zh = "熔火之心",         phase = 1 },
	{ key = "VOA",   zh = "阿尔卡冯的宝库",   phase = 1 },
	{ key = "SSC",   zh = "毒蛇神殿",         phase = 2, aliases = { "盘牙湖泊：毒蛇神殿" } },
	{ key = "TK",    zh = "风暴要塞",         phase = 2 },
	{ key = "OS",    zh = "黑曜石圣殿",       phase = 3 },
	{ key = "NAXX",  zh = "纳克萨玛斯",       phase = 3 },
	{ key = "EoE",   zh = "永恒之眼",         phase = 3 },
	{ key = "TOC",   zh = "十字军的试炼",     phase = 4 },
	{ key = "ZG",    zh = "祖尔格拉布",       phase = 4 },
	{ key = "SWP",   zh = "太阳之井高地",     phase = 5, aliases = { "太阳之井" } },
	{ key = "ZA",    zh = "祖阿曼",           phase = 5 },
	{ key = "ULD",   zh = "奥杜尔",           phase = 6 },
	{ key = "GRUUL", zh = "格鲁尔的巢穴",     phase = 7 },
	{ key = "KARA",  zh = "卡拉赞",           phase = 7 },
	{ key = "MAG",   zh = "玛瑟里顿的巢穴",   phase = 7 },
	{ key = "BWL",   zh = "黑翼之巢",         phase = 8 },
	{ key = "AQ40",  zh = "安其拉",           phase = 9 },
	{ key = "AQ20",  zh = "安其拉废墟",       phase = 9 },
	{ key = "ICC",   zh = "冰冠堡垒",         phase = 10 },
	{ key = "RS",    zh = "红玉圣殿",         phase = 10 },
	{ key = "HYJ",   zh = "海加尔山",         phase = 11, aliases = { "海加尔山之战" } },
	{ key = "BT",    zh = "黑暗神殿",         phase = 11 },
	{ key = "ONY",   zh = "奥妮克希亚的巢穴", phase = 0 },
}

-- 副本名（含别名）→ 条目：匹配 GetSavedInstanceInfo 返回的名字
ns.RAID_LOOKUP = {}
for _, r in ipairs(ns.RAIDS) do
	ns.RAID_LOOKUP[r.zh] = r
	if r.aliases then
		for _, alias in ipairs(r.aliases) do ns.RAID_LOOKUP[alias] = r end
	end
end

-- 阶段上限：滑块范围与阶段钳制都用它，加新阶段不必改代码
ns.MAX_PHASE = 1
for _, r in ipairs(ns.RAIDS) do
	if (r.phase or 0) > ns.MAX_PHASE then ns.MAX_PHASE = r.phase end
end

-- 自动收录的未知团本没有 zh 字段，label 由 Core 写入
function ns.RaidLabel(r)
	return r.label or r.zh or r.key
end
