extends RefCounted

const COLORS = [Color("e14b79"), Color("9c86f5"), Color("efcc7d")]
const CLOAKS = ["绯月 · 断裂", "星汐 · 流转", "圣棘 · 界定"]
const COOLDOWNS = [1.2, 1.6, 1.8]
const RELICS = {"red_echo":30, "blue_flow":30, "gold_linger":30, "tri_weave":60}
const ENEMY_NAMES = {"chaser":"饿客","charger":"疯仆","armored":"背锅人","boss":"老厨子"}
const BRANCH_IDS = ["short_cut","snap_link","moving_wall"]
const BRANCHES = [
 {"id":"short_cut","title":"绯月分支 · 短切","description":"最长 4 米，18 伤害 / 12 破甲，冷却 0.65 秒。用更短、更频繁的切割换掉长线覆盖；本局覆盖原变律。","cost":60},
 {"id":"snap_link","title":"星汐分支 · 收线","description":"建立 14 伤害，拉力降低；0.25 秒后右键收线再打 24，并结束连接。冷却 2 秒；本局覆盖原变律。","cost":60},
 {"id":"moving_wall","title":"圣棘分支 · 推墙","description":"布置后不会自动伤害；右键让墙向箭头推进 2.5 米，首批命中 24。冷却 2.2 秒；本局覆盖原变律。","cost":60}
]
const BRANCH_SUPPORTS = [
 {"id":"short_rebate","requires":"short_cut","title":"短切 · 击倒接刀","description":"一次短切击倒敌人，返还 0.2 秒冷却。每次施法仅一次，两刀间隔至少 0.45 秒。","cost":60},
 {"id":"snap_gather","requires":"snap_link","title":"收线 · 带上旁人","description":"主动收线额外轻拉每个敌端 2 米内最近一名敌人。跨端去重，不增加伤害或连接端点。","cost":60},
 {"id":"wall_travel","requires":"moving_wall","title":"推墙 · 多推一段","description":"推进距离从 2.5 米延长到 4 米。速度不变，仍在首次有效接触后结束。","cost":60}
]
const UPGRADES = [
 {"id":"wide","title":"宽缎","description":"切割宽度增至 0.95 米。让更多敌人进入同一条断裂轨迹。","cost":60},
 {"id":"crack","title":"长痕","description":"裂痕延长至 9 秒，留出更多切换和碰撞机会。","cost":60},
 {"id":"shatter","title":"破甲余势","description":"首次破甲后，下一装甲目标额外受到 20 结构伤害。每次施法一次。","cost":60},
 {"id":"reach","title":"远结","description":"连线可达 10 米，超过 12 米才断裂。","cost":60},
 {"id":"tide","title":"伴流","description":"连接建立时，轻拉每个敌端附近的一名敌人；不额外造成伤害。","cost":60},
 {"id":"pull","title":"牵束","description":"持续牵引力增强 20%，将敌群收束到更有利的位置。","cost":60},
 {"id":"length","title":"长界","description":"边界长度上限从 6 米增加至 8 米。","cost":60},
 {"id":"linger","title":"缓界","description":"未触发的边界可等待 4.5 秒。","cost":60},
 {"id":"slow","title":"定步","description":"裁定使普通敌人减速 25%，持续 1 秒。","cost":60},
 {"id":"health","title":"补缀","description":"本局生命上限增加 20，并恢复 20 生命。","cost":60},
 {"id":"speed","title":"轻履","description":"移动速度增加 8%，更从容地绕行与绘制。","cost":60},
 {"id":"heal","title":"静息","description":"立即恢复 25 生命。","cost":60}
]

static func segment_distance(p:Vector3,a:Vector3,b:Vector3)->float:
 var v = b-a
 if v.length_squared() < 0.00001:
  return p.distance_to(a)
 var t = clampf((p-a).dot(v)/v.length_squared(),0.0,1.0)
 return p.distance_to(a+v*t)

static func flat(v:Vector3)->Vector3:
 return Vector3(v.x,0,v.z)

static func boundary_normal(a:Vector3,b:Vector3)->Vector3:
 return (b-a).normalized().cross(Vector3.UP).normalized()
