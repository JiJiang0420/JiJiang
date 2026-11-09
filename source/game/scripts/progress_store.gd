extends RefCounted
## Permanent progress only. No in-progress combat state is written here.

const SAVE_PATH: String = "user://progress.json"
const BACKUP_PATH: String = "user://progress.backup.json"
const TEMP_PATH: String = "user://progress.tmp"
const BACKUP_TEMP_PATH: String = "user://progress.backup.tmp"
const RELIC_IDS: Array[String] = ["red_echo", "blue_flow", "gold_linger", "tri_weave"]
const SLOT_IDS: Array[String] = ["red_echo", "blue_flow", "gold_linger"]
const MAX_FILE_BYTES: int = 262144
const MAX_COUNTER: int = 1000000000

var last_error: String = ""
var _write_blocked: bool = false
var _archived_hashes: Dictionary = {}


func default_data() -> Dictionary:
	return {
		"version": 1,
		"essence": 0,
		"unlocked": [],
		"equipped": ["", "", ""],
		"resonance": false,
		"total_runs": 0,
		"wins": 0,
		"settings": {"sound": true},
	}


func load_data() -> Dictionary:
	last_error = ""
	_write_blocked = false
	var primary: Dictionary = _read_valid(SAVE_PATH)
	if not primary.is_empty():
		return primary
	var primary_existed: bool = FileAccess.file_exists(SAVE_PATH)
	if primary_existed and not _preserve_corrupt(SAVE_PATH):
		_write_blocked = true
	var backup: Dictionary = _read_valid(BACKUP_PATH)
	if not backup.is_empty():
		_report("主存档不可读，已载入最近的有效备份；损坏文件会保留。")
		return backup
	var backup_existed: bool = FileAccess.file_exists(BACKUP_PATH)
	if backup_existed and not _preserve_corrupt(BACKUP_PATH):
		_write_blocked = true
	if primary_existed or backup_existed:
		_report("未找到有效存档，使用初始进度；原文件已保留，保存失败时不会扣除残纱。")
	return default_data()


func save_data(data: Dictionary) -> bool:
	last_error = ""
	if _write_blocked:
		return _fail("无法安全保留旧存档，本次保存已取消。")
	var clean: Dictionary = _validate(data)
	if clean.is_empty():
		return _fail("进度数据无效，本次保存已取消。")
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("user://")
	)
	if directory_error != OK:
		return _fail("无法创建存档目录。")

	# Never replace an unreadable file unless a separate recoverable copy exists.
	var existing: Dictionary = _read_valid(SAVE_PATH)
	if existing.is_empty() and FileAccess.file_exists(SAVE_PATH):
		if not _preserve_corrupt(SAVE_PATH):
			_write_blocked = true
			return _fail("无法备份损坏存档，本次保存已取消。")
	if FileAccess.file_exists(BACKUP_PATH) and _read_valid(BACKUP_PATH).is_empty():
		if not _preserve_corrupt(BACKUP_PATH):
			_write_blocked = true
			return _fail("无法保留旧备份，本次保存已取消。")

	var output: FileAccess = FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if output == null:
		return _fail("无法写入存档临时文件。")
	output.store_string(JSON.stringify(clean, "\t", true))
	output.flush()
	var write_error: Error = output.get_error()
	output.close()
	if write_error != OK or _read_valid(TEMP_PATH).is_empty():
		_remove_temp(TEMP_PATH)
		return _fail("存档写入校验失败，原存档未修改。")

	# Commit a backup of the prior valid primary before replacing the primary.
	if not existing.is_empty():
		var copy_error: Error = DirAccess.copy_absolute(
			ProjectSettings.globalize_path(SAVE_PATH),
			ProjectSettings.globalize_path(BACKUP_TEMP_PATH)
		)
		if copy_error != OK or _read_valid(BACKUP_TEMP_PATH).is_empty():
			_remove_temp(TEMP_PATH)
			_remove_temp(BACKUP_TEMP_PATH)
			return _fail("无法建立恢复备份，原存档未修改。")
		var backup_error: Error = DirAccess.rename_absolute(
			ProjectSettings.globalize_path(BACKUP_TEMP_PATH),
			ProjectSettings.globalize_path(BACKUP_PATH)
		)
		if backup_error != OK:
			_remove_temp(TEMP_PATH)
			_remove_temp(BACKUP_TEMP_PATH)
			return _fail("无法提交恢复备份，原存档未修改。")

	var commit_error: Error = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(TEMP_PATH),
		ProjectSettings.globalize_path(SAVE_PATH)
	)
	if commit_error != OK:
		_remove_temp(TEMP_PATH)
		return _fail("无法提交存档，原存档或恢复备份仍保留。")
	return true


func _read_valid(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var input: FileAccess = FileAccess.open(path, FileAccess.READ)
	if input == null:
		return {}
	var size: int = input.get_length()
	if size <= 0 or size > MAX_FILE_BYTES:
		input.close()
		return {}
	var text: String = input.get_as_text()
	input.close()
	var parser: JSON = JSON.new()
	if parser.parse(text) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {}
	return _validate(parser.data)


func _validate(data: Dictionary) -> Dictionary:
	for key: String in ["version", "essence", "total_runs", "wins"]:
		if not data.has(key) or not _valid_integer(data[key]):
			return {}
	if int(data["version"]) != 1:
		return {}
	if int(data["wins"]) > int(data["total_runs"]):
		return {}
	if typeof(data.get("unlocked")) != TYPE_ARRAY:
		return {}
	if typeof(data.get("equipped")) != TYPE_ARRAY:
		return {}
	if typeof(data.get("resonance")) != TYPE_BOOL:
		return {}
	if typeof(data.get("settings")) != TYPE_DICTIONARY:
		return {}
	var settings: Dictionary = data["settings"]
	if typeof(settings.get("sound")) != TYPE_BOOL:
		return {}
	var unlocked: Array = data["unlocked"]
	if unlocked.size() > RELIC_IDS.size():
		return {}
	var seen: Dictionary = {}
	for item: Variant in unlocked:
		if typeof(item) != TYPE_STRING or not RELIC_IDS.has(str(item)) or seen.has(item):
			return {}
		seen[item] = true
	var equipped: Array = data["equipped"]
	if equipped.size() != 3:
		return {}
	for index: int in range(3):
		if typeof(equipped[index]) != TYPE_STRING:
			return {}
		var item: String = equipped[index]
		if item != "" and (item != SLOT_IDS[index] or not seen.has(item)):
			return {}
	if bool(data["resonance"]) and not seen.has("tri_weave"):
		return {}
	# Keep future optional UI settings, but only persist the known top-level schema.
	var clean: Dictionary = default_data()
	for key: String in ["version", "essence", "total_runs", "wins"]:
		clean[key] = int(data[key])
	clean["unlocked"] = unlocked.duplicate()
	clean["equipped"] = equipped.duplicate()
	clean["resonance"] = bool(data["resonance"])
	clean["settings"] = settings.duplicate(true)
	return clean


func _valid_integer(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= 0.0 and number <= float(MAX_COUNTER) and number == floor(number)


func _preserve_corrupt(path: String) -> bool:
	var digest: String = FileAccess.get_sha256(path)
	if digest == "":
		return false
	if _archived_hashes.get(path, "") == digest:
		return true
	var stamp: String = str(int(Time.get_unix_time_from_system()))
	var archive: String = path + ".corrupt-" + stamp
	var suffix: int = 0
	while FileAccess.file_exists(archive):
		suffix += 1
		archive = path + ".corrupt-" + stamp + "-" + str(suffix)
	var error: Error = DirAccess.copy_absolute(
		ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(archive)
	)
	if error != OK or FileAccess.get_sha256(archive) != digest:
		return false
	_archived_hashes[path] = digest
	return true


func _remove_temp(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _report(message: String) -> void:
	last_error = message
	push_warning(message)


func _fail(message: String) -> bool:
	_report(message)
	return false
