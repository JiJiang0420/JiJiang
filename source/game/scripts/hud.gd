extends CanvasLayer
## The slice's complete interface. Gameplay-space controls never capture the mouse.

const INK = Color("10121d")
const PANEL = Color("191c2b")
const PAPER = Color("f0e9dc")
const MUTED = Color("a2a7bb")
const GOLD = Color("ddbd83")
const COLORS = [Color("ef7590"), Color("9ba4ff"), Color("e6ca86")]
const NAMES = ["绯月", "星汐", "圣棘"]
const POWERS = ["断裂之权", "流转之权", "界定之权"]
const VERBS = ["切割", "牵引", "推开"]
const AIM_HINTS = [
	"按住左键划过敌人，松开切割轨迹内目标",
	"从敌人拖向敌人或地面，松开建立牵引",
	"左键画线后松开，线内目标沿箭头推开"
]
const RELIC_IDS = ["red_echo", "blue_flow", "gold_linger"]
const RELIC_TITLES = ["回斩", "单向导流", "延界"]
const RELIC_DETAILS = [
	"沿原轨迹延迟回切。\n单段伤害降低，命中两次收益更高。",
	"第一端不移动，第二端向其收束。\n单敌时从地面锚点画向敌人。",
	"首轮裁定后短暂保留，接纳新目标。\n单次伤害降低，同一目标不重复触发。"
]
const SPELL_DETAILS = [
	"按住左键划过敌人，松开切割线内目标。\n切割能破甲；裂痕增强后续真实撞击。",
	"从敌人拖向敌人或地面，松开建立牵引。\n建立时收紧伤害，随后持续拉动端点。",
	"画线后松开，线内敌人立即沿箭头推开。\n冲锋或飞弹触界时，才按箭头方向偏转。"
]

var game
var root_control: Control
var battle: Control
var menu_layer: Control
var pause_layer: Control
var help_layer: Control
var notification: Label
var notice_left: float = 0.0
var health_bar: ProgressBar
var health_text: Label
var clock_text: Label
var phase_text: Label
var coin_text: Label
var threat_text: Label
var structures_text: Label
var action_text: Label
var aim_detail_text: Label
var combat_feedback_text: Label
var dodge_text: Label
var cloak_panels: Array = []
var cooldown_bars: Array = []
var cooldown_labels: Array = []
var name_labels: Array = []
var cached_cloak: int = -1
var current_page: String = ""
var font: Font
var boss_box: VBoxContainer
var boss_bar: ProgressBar


func setup(owner_game) -> void:
	game = owner_game
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	if ResourceLoader.exists("res://assets/fonts/ui.ttf"):
		font = load("res://assets/fonts/ui.ttf")
	else:
		var fallback = SystemFont.new()
		fallback.font_names = PackedStringArray(["Noto Sans CJK SC", "Noto Sans CJK JP"])
		font = fallback
	root_control = Control.new()
	root_control.name = "Interface"
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 17
	theme.set_color("font_color", "Label", PAPER)
	root_control.theme = theme
	add_child(root_control)
	_build_battle()
	menu_layer = _layer("Menu", false)
	pause_layer = _layer("Pause", true)
	help_layer = _layer("Help", true)
	pause_layer.hide()
	help_layer.hide()
	_build_pause()
	_build_help()
	var toast_margin = MarginContainer.new()
	toast_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_margin.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toast_margin.offset_left = -330
	toast_margin.offset_right = 330
	toast_margin.offset_top = 110
	toast_margin.offset_bottom = 160
	root_control.add_child(toast_margin)
	notification = _label("", 18, PAPER)
	notification.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notification.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notification.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	notification.add_theme_constant_override("shadow_outline_size", 5)
	toast_margin.add_child(notification)
	notification.hide()


func _process(delta: float) -> void:
	if notice_left > 0.0:
		notice_left = maxf(0.0, notice_left - delta)
		notification.modulate.a = minf(1.0, notice_left * 2.0)
		if notice_left <= 0.0:
			notification.hide()


func _layer(node_name: String, dim: bool) -> Control:
	var layer_control = Control.new()
	layer_control.name = node_name
	layer_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(layer_control)
	if dim:
		var shade = ColorRect.new()
		shade.color = Color(0.025, 0.03, 0.055, 0.88)
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shade.mouse_filter = Control.MOUSE_FILTER_STOP
		layer_control.add_child(shade)
	return layer_control


func _style(background: Color, border: Color, width: int = 1, radius: int = 10) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	return style


func _label(text: String, size: int = 17, color: Color = PAPER) -> Label:
	var label = Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _paragraph(text: String, size: int = 16, color: Color = MUTED) -> Label:
	var label = _label(text, size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _vbox(separation: int = 12) -> VBoxContainer:
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


func _hbox(separation: int = 12) -> HBoxContainer:
	var box = HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


func _spacer() -> Control:
	var spacer = Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return spacer


func _button(text: String, callback: Callable, accent: Color = GOLD, primary: bool = false) -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 46)
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", INK if primary else PAPER)
	button.add_theme_color_override("font_hover_color", INK if primary else accent)
	button.add_theme_color_override("font_pressed_color", INK if primary else accent)
	button.add_theme_color_override("font_disabled_color", Color("676b7c"))
	button.add_theme_stylebox_override("normal", _style(accent if primary else PANEL, accent if primary else Color("414456")))
	button.add_theme_stylebox_override("hover", _style(accent.lightened(0.12) if primary else Color("282b3e"), accent))
	button.add_theme_stylebox_override("pressed", _style(accent.darkened(0.12) if primary else Color("32364b"), accent))
	button.add_theme_stylebox_override("disabled", _style(Color("191b27"), Color("303341")))
	button.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), accent, 2))
	button.pressed.connect(callback)
	return button


func _panel(accent: Color = Color("414456"), background: Color = PANEL) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(background, accent))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _build_battle() -> void:
	battle = _layer("BattleHUD", false)
	var top = MarginContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 28
	top.offset_right = -28
	top.offset_top = 24
	top.offset_bottom = 102
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	battle.add_child(top)
	var row = _hbox(24)
	top.add_child(row)
	var life_panel = _panel(Color("55505a"), Color(0.055, 0.063, 0.1, 0.88))
	life_panel.custom_minimum_size = Vector2(265, 0)
	row.add_child(life_panel)
	var life_box = _vbox(6)
	life_panel.add_child(life_box)
	var life_row = _hbox()
	life_box.add_child(life_row)
	var life_title = _label("承 宴 者", 15, GOLD)
	life_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	life_row.add_child(life_title)
	health_text = _label("100 / 100", 16)
	life_row.add_child(health_text)
	health_bar = ProgressBar.new()
	health_bar.custom_minimum_size = Vector2(0, 9)
	health_bar.show_percentage = false
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_bar.add_theme_stylebox_override("background", _style(Color("2b2634"), Color.TRANSPARENT, 0, 4))
	health_bar.add_theme_stylebox_override("fill", _style(Color("ce6984"), Color.TRANSPARENT, 0, 4))
	life_box.add_child(health_bar)
	var center = _vbox(1)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(center)
	phase_text = _label("盛 宴 将 启", 15, GOLD)
	phase_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(phase_text)
	clock_text = _label("00:00 / 08:00", 28)
	clock_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(clock_text)
	var right = _vbox(2)
	right.custom_minimum_size = Vector2(265, 0)
	row.add_child(right)
	coin_text = _label("宴屑  0", 20, GOLD)
	coin_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(coin_text)
	threat_text = _label("宴场之敌  0", 14, MUTED)
	threat_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(threat_text)
	var bottom = MarginContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 28
	bottom.offset_right = -28
	bottom.offset_top = -195
	bottom.offset_bottom = -18
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	battle.add_child(bottom)
	var lower = _vbox(5)
	bottom.add_child(lower)
	action_text = _label("切割 · 绯月  /  左键拖绘，松开生效", 18)
	action_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action_text.add_theme_color_override("font_shadow_color", Color.BLACK)
	action_text.add_theme_constant_override("shadow_outline_size", 4)
	lower.add_child(action_text)
	aim_detail_text = _label("就绪  ·  拖绘时显示预计命中目标与长度", 14, MUTED)
	aim_detail_text.name = "AimDetails"
	aim_detail_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	aim_detail_text.add_theme_color_override("font_shadow_color", Color.BLACK)
	aim_detail_text.add_theme_constant_override("shadow_outline_size", 4)
	lower.add_child(aim_detail_text)
	combat_feedback_text = _label("切割破甲 → 牵引聚敌 → 推开撞击", 15, GOLD)
	combat_feedback_text.name = "CombatFeedback"
	combat_feedback_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combat_feedback_text.add_theme_color_override("font_shadow_color", Color.BLACK)
	combat_feedback_text.add_theme_constant_override("shadow_outline_size", 4)
	lower.add_child(combat_feedback_text)
	var cooldown_row = _hbox(10)
	cooldown_row.alignment = BoxContainer.ALIGNMENT_CENTER
	lower.add_child(cooldown_row)
	for index in range(3):
		var card = _panel(Color("444759"), Color(0.055, 0.063, 0.1, 0.94))
		card.custom_minimum_size = Vector2(232, 73)
		cooldown_row.add_child(card)
		cloak_panels.append(card)
		var box = _vbox(5)
		card.add_child(box)
		var title_row = _hbox(12)
		box.add_child(title_row)
		var title = _label("%d  %s · %s" % [index + 1, NAMES[index], VERBS[index]], 18, COLORS[index])
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_row.add_child(title)
		name_labels.append(title)
		var cooldown_label = _label("就绪", 14, MUTED)
		title_row.add_child(cooldown_label)
		cooldown_labels.append(cooldown_label)
		var bar = ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 4)
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.max_value = 1.0
		bar.value = 1.0
		bar.add_theme_stylebox_override("background", _style(Color("333443"), Color.TRANSPARENT, 0, 2))
		bar.add_theme_stylebox_override("fill", _style(COLORS[index], Color.TRANSPARENT, 0, 2))
		box.add_child(bar)
		cooldown_bars.append(bar)
	var hints = _hbox(24)
	lower.add_child(hints)
	var keys = _label("WASD 移动   ·   中键转镜头   ·   1 / 2 / 3 换装   ·   Esc 暂停", 13, MUTED)
	keys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hints.add_child(keys)
	dodge_text = _label("空格 闪避就绪", 13, GOLD)
	hints.add_child(dodge_text)
	structures_text = _label("", 14, MUTED)
	structures_text.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	structures_text.offset_left = -240
	structures_text.offset_right = -30
	structures_text.offset_top = -16
	structures_text.offset_bottom = 64
	structures_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	battle.add_child(structures_text)
	boss_box = _vbox(4)
	boss_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	boss_box.offset_left = -190
	boss_box.offset_right = 190
	boss_box.offset_top = 115
	boss_box.offset_bottom = 160
	battle.add_child(boss_box)
	var boss_title = _label("老 厨 子", 15, GOLD)
	boss_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_box.add_child(boss_title)
	boss_bar = ProgressBar.new()
	boss_bar.custom_minimum_size = Vector2(380, 8)
	boss_bar.show_percentage = false
	boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_bar.max_value = 720
	boss_bar.add_theme_stylebox_override("background", _style(Color("302532"), Color.TRANSPARENT, 0, 3))
	boss_bar.add_theme_stylebox_override("fill", _style(Color("c78092"), Color.TRANSPARENT, 0, 3))
	boss_box.add_child(boss_bar)
	boss_box.hide()
	battle.hide()


func show_base(progress: Dictionary) -> void:
	current_page = "base"
	battle.hide()
	pause_layer.hide()
	help_layer.hide()
	_clear(menu_layer)
	menu_layer.show()
	var shade = ColorRect.new()
	shade.color = Color(0.035, 0.04, 0.07, 0.82)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	menu_layer.add_child(shade)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 42)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	menu_layer.add_child(margin)
	var box = _vbox(18)
	margin.add_child(box)
	var header = _hbox()
	box.add_child(header)
	var wordmark = _vbox(2)
	wordmark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(wordmark)
	wordmark.add_child(_label("W I T C H E S '   F E A S T", 14, GOLD))
	wordmark.add_child(_label("魔女的盛宴", 42))
	wordmark.add_child(_label("三神遗物  /  操作改版 v0.2", 15, MUTED))
	var balance = _vbox(7)
	header.add_child(balance)
	var money = _label("残纱  %d" % int(progress.get("essence", 0)), 25, GOLD)
	money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	balance.add_child(money)
	var record = _label("入宴 %d 次   ·   凯旋 %d 次" % [int(progress.get("total_runs", 0)), int(progress.get("wins", 0))], 14, MUTED)
	balance.add_child(record)
	var content = _hbox(20)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(content)
	var left = _vbox(12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 3.0
	content.add_child(left)
	left.add_child(_paragraph("你只有一个身体，却能披挂三种神权。\n画出切线、建立联系、落下边界，改写这场盛宴。", 18, PAPER))
	var cards = _hbox(12)
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(cards)
	var unlocked: Array = progress.get("unlocked", [])
	var equipped: Array = progress.get("equipped", ["", "", ""])
	for i in range(3):
		var accent: Color = COLORS[i]
		var panel = _panel(accent.darkened(0.57), Color(0.075, 0.085, 0.13, 0.96))
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cards.add_child(panel)
		var card = _vbox(10)
		panel.add_child(card)
		card.add_child(_label("0%d   /   %s" % [i + 1, POWERS[i]], 13, accent))
		card.add_child(_label(NAMES[i], 31, PAPER))
		card.add_child(_paragraph(SPELL_DETAILS[i], 15))
		card.add_child(_spacer())
		card.add_child(_label("变律 · " + RELIC_TITLES[i], 18, accent))
		card.add_child(_paragraph(RELIC_DETAILS[i], 14))
		var relic_id: String = RELIC_IDS[i]
		var owned: bool = unlocked.has(relic_id)
		var active: bool = equipped.size() > i and str(equipped[i]) == relic_id
		var button: Button
		if owned:
			button = _button("已装备 · 点击卸下" if active else "装备变律", func(): game.toggle_relic(relic_id), accent, active)
		else:
			button = _button("解锁  /  30 残纱", func(): game.purchase_relic(relic_id), accent)
			button.disabled = int(progress.get("essence", 0)) < 30
			button.tooltip_text = "通过战斗完成阶段，积累永久残纱。"
		button.name = "Relic_" + relic_id
		card.add_child(button)
	var right = _vbox(12)
	right.custom_minimum_size = Vector2(285, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.0
	content.add_child(right)
	var journey = _panel(GOLD.darkened(0.55), Color(0.075, 0.085, 0.13, 0.96))
	right.add_child(journey)
	var journey_box = _vbox(11)
	journey.add_child(journey_box)
	journey_box.add_child(_label("今夜的盛宴", 22, GOLD))
	journey_box.add_child(_paragraph("三轮敌潮，三次构筑机会。\n击败老厨子，带回修复神衣的残纱。", 15))
	var full = _button("进入盛宴  /  8 分钟", func(): game.start_run(false), GOLD, true)
	full.name = "StartFull"
	journey_box.add_child(full)
	var quick = _button("快速试玩  /  3 分钟", func(): game.start_run(true))
	quick.name = "StartShort"
	journey_box.add_child(quick)
	var training = _button("进入试炼场", func(): game.start_training())
	training.name = "StartTraining"
	journey_box.add_child(training)
	journey_box.add_child(_paragraph("首次体验建议先进入试炼场。\nQ 试用当前斗篷的攻击分支。\n基础三神权能全部开放，无需解锁。", 13, MUTED))
	var weave = _panel(Color("635b7a"), Color(0.075, 0.085, 0.13, 0.96))
	right.add_child(weave)
	var weave_box = _vbox(8)
	weave.add_child(weave_box)
	weave_box.add_child(_label("三神共织 · 断后引流", 18, GOLD))
	weave_box.add_child(_paragraph("连接带裂痕的敌人，首次收紧会额外牵引。", 14))
	var weave_owned: bool = unlocked.has("tri_weave")
	var weave_on: bool = bool(progress.get("resonance", false))
	var weave_button: Button
	if weave_owned:
		weave_button = _button("共织已启用 · 点击停用" if weave_on else "启用共织", func(): game.toggle_relic("tri_weave"), GOLD, weave_on)
	else:
		weave_button = _button("解锁  /  60 残纱", func(): game.purchase_relic("tri_weave"))
		weave_button.disabled = int(progress.get("essence", 0)) < 60
	weave_button.name = "Relic_tri_weave"
	weave_box.add_child(weave_button)
	var footer = _hbox()
	box.add_child(footer)
	var status = _label("阶段完成即保存残纱；本局宴屑与强化在结束时清空。", 13, MUTED)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(status)
	var help_button = _button("操作指南", func(): game.toggle_help())
	help_button.custom_minimum_size = Vector2(130, 40)
	footer.add_child(help_button)


func show_shop(offers: Array, coins: int, stage: int) -> void:
	current_page = "shop"
	battle.show()
	pause_layer.hide()
	_clear(menu_layer)
	menu_layer.show()
	var center = _modal(menu_layer, Vector2(990, 430))
	center.add_child(_label("宴间 · 织造新律", 31, GOLD))
	center.add_child(_paragraph("第 %d 轮敌潮已结束。战斗与时间暂歇，选择带入下一阶段的力量。" % stage, 16))
	center.add_child(_label("宴屑  %d   /   每项 60 · 每店至多两项" % coins, 18, GOLD))
	var cards = _hbox(14)
	center.add_child(cards)
	for entry in offers:
		var offer: Dictionary = entry
		var panel = _panel(Color("565169"))
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.custom_minimum_size = Vector2(0, 215)
		cards.add_child(panel)
		var card = _vbox(13)
		panel.add_child(card)
		card.add_child(_label(str(offer.get("title", "新律")), 23, PAPER))
		card.add_child(_paragraph(str(offer.get("description", "")), 16))
		card.add_child(_spacer())
		var offer_id: String = str(offer.get("id", ""))
		var cost: int = int(offer.get("cost", 60))
		var purchased: bool = bool(offer.get("purchased", false))
		var disabled: bool = bool(offer.get("disabled", false))
		var buy = _button("已购入" if purchased else "织入  /  %d 宴屑" % cost, func(): game.buy_upgrade(offer_id), GOLD, not purchased)
		buy.name = "Buy_" + offer_id
		buy.disabled = coins < cost or purchased or disabled
		card.add_child(buy)
	if offers.is_empty():
		cards.add_child(_paragraph("本次织造已完成，准备迎接下一轮。", 20))
	var continue_button = _button("迎战老厨子" if stage >= 3 else "继续入宴", func(): game.continue_from_shop(), GOLD, true)
	continue_button.name = "ContinueShop"
	center.add_child(continue_button)


func show_result(info: Dictionary) -> void:
	current_page = "result"
	battle.hide()
	pause_layer.hide()
	help_layer.hide()
	_clear(menu_layer)
	menu_layer.show()
	var box = _modal(menu_layer, Vector2(650, 470))
	var won: bool = bool(info.get("won", false))
	box.add_child(_label("盛宴落幕" if won else "灯火暂歇", 38, GOLD if won else COLORS[0]))
	box.add_child(_paragraph(str(info.get("reason", "")), 18, PAPER))
	box.add_child(_paragraph("神衣记得你走过的路。已结算的残纱将保留，下一次盛宴仍等待你的到来。", 16))
	var stats = _hbox(15)
	box.add_child(stats)
	for pair in [["存续时间", _time(float(info.get("time", 0.0)))], ["击退敌人", str(info.get("kills", 0))], ["本局残纱", "+" + str(info.get("earned", 0))]]:
		var panel = _panel(Color("454153"))
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats.add_child(panel)
		var stat = _vbox(8)
		panel.add_child(stat)
		stat.add_child(_label(str(pair[0]), 14, MUTED))
		stat.add_child(_label(str(pair[1]), 29, GOLD))
	box.add_child(_label("永久残纱余额  %d" % int(info.get("essence", 0)), 18, GOLD))
	box.add_child(_button("返回神衣陈列室", func(): game.return_to_base(), GOLD, true))
	box.add_child(_paragraph("本局宴屑与临时强化已清空。", 13))


func _modal(parent: Control, minimum: Vector2) -> VBoxContainer:
	var shade = ColorRect.new()
	shade.color = Color(0.03, 0.035, 0.06, 0.83)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(shade)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(center)
	var panel = _panel(GOLD.darkened(0.55), Color(0.07, 0.078, 0.12, 0.98))
	panel.custom_minimum_size = minimum
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)
	var box = _vbox(18)
	panel.add_child(box)
	return box


func _build_pause() -> void:
	var box = _modal(pause_layer, Vector2(460, 390))
	box.add_child(_label("此刻停驻", 32, GOLD))
	box.add_child(_paragraph("战斗、冷却与法术寿命均已暂停。", 16))
	var resume_button = _button("继续盛宴", func(): game.toggle_pause(), GOLD, true)
	resume_button.name = "Resume"
	box.add_child(resume_button)
	box.add_child(_button("操作指南", func(): game.toggle_help()))
	box.add_child(_paragraph("返回基地将结束本局。已结算残纱保留，本局宴屑与强化清空。", 14))
	var exit_button = _button("结束本局并返回基地", func(): game.return_to_base())
	exit_button.name = "AbandonRun"
	box.add_child(exit_button)


func _build_help() -> void:
	var box = _modal(help_layer, Vector2(780, 560))
	box.add_child(_label("以手绘，改写战场", 31, GOLD))
	box.add_child(_paragraph("WASD 移动  ·  空格闪避  ·  中键拖动旋转镜头\n左键按住拖绘，松开释放  ·  1 / 2 / 3 切换斗篷\n右键优先取消绘制；未绘制时执行当前分支的收线／推墙。", 17, PAPER))
	for i in range(3):
		var panel = _panel(COLORS[i].darkened(0.6))
		box.add_child(panel)
		var row = _hbox(18)
		panel.add_child(row)
		var title = _label("%d  %s" % [i + 1, NAMES[i]], 22, COLORS[i])
		title.custom_minimum_size = Vector2(115, 0)
		row.add_child(title)
		row.add_child(_paragraph(SPELL_DETAILS[i], 16, PAPER))
	box.add_child(_paragraph("连线与边界在换装后继续存在。最多保留一条连线、一条边界；新法术会替换同类旧结构。绘制时镜头暂不旋转。", 15))
	box.add_child(_paragraph("试炼场按 Q：切换当前斗篷的基础攻击与攻击分支。分支的操作变化会显示在战斗下方；正式战斗在商店中选择。", 15, GOLD))
	box.add_child(_paragraph("饿客追身，疯仆冲锋，背锅人披甲。老厨子是这场盛宴的首领。", 14, GOLD))
	box.add_child(_button("明白了", func(): game.toggle_help(), GOLD, true))


func show_pause(visible: bool) -> void:
	pause_layer.visible = visible
	if not visible:
		help_layer.hide()


func show_help(visible: bool = true) -> void:
	help_layer.visible = visible


func hide_panels() -> void:
	current_page = ""
	menu_layer.hide()
	pause_layer.hide()
	help_layer.hide()
	battle.show()


func update_status(data: Dictionary) -> void:
	if not is_instance_valid(health_bar):
		return
	var mode: String = str(data.get("mode", "battle"))
	if mode == "base" or mode == "result":
		battle.hide()
	else:
		battle.show()
	var maximum: float = maxf(1.0, float(data.get("max_hp", 100.0)))
	var health: float = clampf(float(data.get("hp", maximum)), 0.0, maximum)
	health_bar.max_value = maximum
	health_bar.value = health
	health_text.text = "%d / %d" % [ceili(health), int(maximum)]
	clock_text.text = "无时限试炼" if mode == "training" else "%s / %s" % [_time(float(data.get("elapsed", 0.0))), _time(float(data.get("duration", 480.0)))]
	var phase: int = int(data.get("stage", 0)) + 1
	phase_text.text = "试 炼 场" if mode == "training" else ("老 厨 子" if phase >= 4 else "第 %d 轮 · 神 性 涌 动" % maxi(1, phase))
	coin_text.text = "宴屑  %d" % int(data.get("coins", 0))
	threat_text.text = "宴场之敌  %d" % int(data.get("enemies", 0))
	var boss_hp: float = float(data.get("boss_hp", -1.0))
	boss_box.visible = boss_hp >= 0.0
	boss_bar.value = maxf(0, boss_hp)
	var active: int = clampi(int(data.get("cloak", 0)), 0, 2)
	if active != cached_cloak:
		cached_cloak = active
		for i in range(3):
			cloak_panels[i].add_theme_stylebox_override("panel", _style(Color(0.09, 0.10, 0.16, 0.96) if i == active else Color(0.055, 0.063, 0.1, 0.90), COLORS[i] if i == active else Color("444759"), 2 if i == active else 1))
	var cooldowns: Array = data.get("cooldowns", [0.0, 0.0, 0.0])
	var total_cooldowns: Array = data.get("cooldown_totals", [1.2, 1.6, 1.8])
	for i in range(3):
		var remaining: float = float(cooldowns[i]) if cooldowns.size() > i else 0.0
		cooldown_labels[i].text = "%.1f 秒" % remaining if remaining > 0.0 else ("当前" if i == active else "就绪")
		cooldown_bars[i].value = 1.0 - clampf(remaining / float(total_cooldowns[i]), 0.0, 1.0)
	var link: float = float(data.get("link_left", 0.0))
	var boundary: float = float(data.get("boundary_left", 0.0))
	structures_text.text = ("星汐连线   %.1f 秒" % link if link > 0.0 else "星汐连线   —") + "\n" + ("圣棘边界   %.1f 秒" % boundary if boundary > 0.0 else "圣棘边界   —")
	var dodge: float = float(data.get("dodge_cooldown", 0.0))
	dodge_text.text = "闪避  %.1f 秒" % dodge if dodge > 0.0 else "空格  闪避就绪"
	_update_aim(data, active, cooldowns)


func _update_aim(data: Dictionary, active: int, cooldowns: Array) -> void:
	var aim_value: Variant = data.get("aim", {})
	var aim: Dictionary = aim_value if aim_value is Dictionary else {}
	var drawing: bool = bool(aim.get("drawing", false))
	var remaining: float = float(cooldowns[active]) if cooldowns.size() > active else 0.0
	var ready: bool = bool(aim.get("ready", remaining <= 0.0))
	var valid: bool = bool(aim.get("valid", ready))
	var verb: String = str(VERBS[active])
	var title: String = str(aim.get("title", ""))
	# Always expose the action even when a caller supplies a poetic ability title.
	if title.is_empty():
		title = "%s · %s" % [verb, NAMES[active]]
	elif not title.contains(verb):
		title = verb + " · " + title
	var hint: String = str(aim.get("hint", AIM_HINTS[active]))
	if hint.is_empty():
		hint = str(AIM_HINTS[active])
	action_text.text = "%s  /  %s" % [title, hint]
	var reason: String = str(aim.get("reason", ""))
	var segments = PackedStringArray()
	if not ready:
		segments.append("冷却中 %.1f 秒" % remaining if remaining > 0.0 else "暂不可施放")
	elif not valid:
		segments.append("不能施放")
	elif drawing:
		segments.append("松开生效")
	else:
		segments.append("施法就绪")
	if not reason.is_empty():
		segments.append(reason)
	if aim.has("targets"):
		var targets: int = maxi(0, int(aim.get("targets", 0)))
		if targets > 0:
			segments.append("预计命中 %d 个目标" % targets if drawing else "光标选中目标")
		elif drawing and active == 2 and valid:
			segments.append("未覆盖敌人 · 可留下边界等待触碰")
		elif drawing:
			segments.append("预计命中 0 个目标")
		else:
			segments.append("预览目标 0 个")
	var target_name: String = str(aim.get("target_name", ""))
	if not target_name.is_empty():
		segments.append("目标：" + _enemy_name(target_name))
	var length: float = maxf(0.0, float(aim.get("length", 0.0)))
	var limit: float = maxf(0.0, float(aim.get("limit", 0.0)))
	if limit > 0.0 and drawing:
		segments.append("%s %.1f / %.1f 米" % ["连距" if active == 1 else "线长", length, limit])
	segments.append("右键取消" if drawing else "左键按住拖绘")
	var secondary: String = str(aim.get("secondary", ""))
	if not secondary.is_empty() and not drawing:
		segments.clear()
		segments.append("右键%s就绪" % secondary if aim.get("secondary_ready", false) else "右键%s准备中" % secondary)
		if not reason.is_empty() and reason != "右键收线已就绪":
			segments.append(reason)
		segments.append("左键冷却 %.1f 秒" % remaining if remaining > 0.0 else "左键可重新布置")
		valid = true
		ready = true
	aim_detail_text.text = "  ·  ".join(segments)
	aim_detail_text.add_theme_color_override("font_color", COLORS[0] if not valid or not ready else PAPER)
	var feedback: String = str(aim.get("feedback", ""))
	if feedback.is_empty():
		feedback = str(data.get("message", ""))
	combat_feedback_text.text = "战况  /  " + _enemy_name(feedback) if not feedback.is_empty() else "切割破甲 → 牵引聚敌 → 推开撞击"


func _enemy_name(value: String) -> String:
	var names: Dictionary = {"chaser": "饿客", "charger": "疯仆", "armored": "背锅人", "boss": "老厨子", "追逐者": "饿客", "窜行者": "疯仆", "铁壳兽": "背锅人", "守宴者": "老厨子", "宴场守卫": "老厨子"}
	var result: String = value
	for old_name in names:
		result = result.replace(str(old_name), str(names[old_name]))
	return result


func toast(text: String) -> void:
	notification.text = text
	notification.modulate.a = 1.0
	notification.show()
	notice_left = 3.2


func _time(seconds: float) -> String:
	var whole: int = maxi(0, int(seconds))
	return "%02d:%02d" % [whole / 60, whole % 60]
