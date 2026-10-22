extends RefCounted
## Отправка баг-репорта: описание + скриншот + снимок сцены → GitHub Issue (+ файлы в ветке bug-inbox).
class_name BugReport

const REPO := "RomanSanych/mech-sim"
const INBOX_BRANCH := "bug-inbox"


static func show_dialog(host: Node, circuit, get_screenshot: Callable, save_scene_tmp: Callable) -> void:
	var runner := _BugReportRunner.new()
	host.add_child(runner)
	runner.run(circuit, get_screenshot, save_scene_tmp)


class _BugReportRunner extends Node:
	var _circuit
	var _get_screenshot: Callable
	var _save_scene_tmp: Callable
	var _dlg: AcceptDialog
	var _edit: TextEdit
	var _status: Label
	var _ok_btn: Button

	func run(circuit, get_screenshot: Callable, save_scene_tmp: Callable) -> void:
		_circuit = circuit
		_get_screenshot = get_screenshot
		_save_scene_tmp = save_scene_tmp
		_dlg = AcceptDialog.new()
		_dlg.title = "Сообщить об ошибке"
		_dlg.ok_button_text = "Отправить"
		_dlg.dialog_hide_on_ok = false
		_dlg.min_size = Vector2i(520, 360)
		var root := VBoxContainer.new()
		root.add_theme_constant_override("separation", 8)
		var hint := Label.new()
		hint.text = "Опишите проблему. Будут приложены скриншот окна и файл текущей сцены.\nНужен GitHub CLI (`gh auth login`) с доступом к репозиторию."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		root.add_child(hint)
		_edit = TextEdit.new()
		_edit.custom_minimum_size = Vector2(480, 200)
		_edit.placeholder_text = "Что произошло? Какие шаги воспроизвести? Ожидание vs факт…"
		_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
		root.add_child(_edit)
		_status = Label.new()
		_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_status.modulate = Color(0.75, 0.75, 0.8)
		root.add_child(_status)
		_dlg.add_child(root)
		add_child(_dlg)
		_ok_btn = _dlg.get_ok_button()
		_dlg.confirmed.connect(_on_send)
		_dlg.canceled.connect(queue_free)
		_dlg.close_requested.connect(queue_free)
		_dlg.popup_centered()

	func _on_send() -> void:
		var text: String = _edit.text.strip_edges()
		if text.is_empty():
			_status.text = "Введите описание."
			return
		if _ok_btn:
			_ok_btn.disabled = true
		_status.text = "Готовлю скриншот и сцену…"
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img: Image = _get_screenshot.call()
		if img == null or img.is_empty():
			_status.text = "Не удалось сделать скриншот."
			if _ok_btn:
				_ok_btn.disabled = false
			return
		var stamp: String = Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
		var dir: String = "user://bugreports/%s" % stamp
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		var shot_path: String = "%s/screenshot.png" % dir
		var scene_path: String = "%s/scene.mechsim.json" % dir
		var desc_path: String = "%s/description.txt" % dir
		img.save_png(shot_path)
		var serr: String = str(_save_scene_tmp.call(scene_path))
		if serr != "":
			_status.text = "Не удалось сохранить сцену: %s" % serr
			if _ok_btn:
				_ok_btn.disabled = false
			return
		var df := FileAccess.open(desc_path, FileAccess.WRITE)
		if df:
			df.store_string(text)
			df.close()
		_status.text = "Отправка на GitHub…"
		await get_tree().process_frame
		var result: Dictionary = BugReport.submit_pack(text, stamp, shot_path, scene_path)
		if bool(result.get("ok", false)):
			_status.text = "Создано: %s" % str(result.get("url", "issue"))
			if _circuit != null and _circuit.has_method("notify"):
				_circuit.notify("Баг отправлен: %s" % str(result.get("url", "")))
			await get_tree().create_timer(1.2).timeout
			_dlg.hide()
			queue_free()
		else:
			_status.text = "Ошибка: %s\nФайлы локально: %s" % [
				str(result.get("error", "?")),
				ProjectSettings.globalize_path(dir),
			]
			if _ok_btn:
				_ok_btn.disabled = false


static func submit_pack(description: String, stamp: String, shot_path: String, scene_path: String) -> Dictionary:
	var gh: String = _resolve_gh()
	if gh == "":
		return {"ok": false, "error": "gh не найден. Установите GitHub CLI и выполните gh auth login."}
	_ensure_inbox_branch(gh)
	var remote_base: String = "bug-reports/%s" % stamp
	var up1: Dictionary = _upload_file(gh, "%s/screenshot.png" % remote_base, shot_path, "bug report screenshot %s" % stamp)
	if not bool(up1.get("ok", false)):
		return up1
	var up2: Dictionary = _upload_file(gh, "%s/scene.mechsim.json" % remote_base, scene_path, "bug report scene %s" % stamp)
	if not bool(up2.get("ok", false)):
		return up2
	var shot_url: String = "https://github.com/%s/blob/%s/%s/screenshot.png" % [REPO, INBOX_BRANCH, remote_base]
	var scene_url: String = "https://github.com/%s/blob/%s/%s/scene.mechsim.json" % [REPO, INBOX_BRANCH, remote_base]
	var title: String = _title_from_description(description)
	var body: String = "\n".join([
		"## Описание (из MechSim)",
		"",
		description,
		"",
		"## Вложения",
		"",
		"- Скриншот: %s" % shot_url,
		"- Сцена: %s" % scene_url,
		"",
		"## Мета",
		"",
		"- stamp: `%s`" % stamp,
		"- source: in-app «Сообщить об ошибке»",
	])
	var body_file: String = "user://bugreports/%s/issue_body.md" % stamp
	var bf := FileAccess.open(body_file, FileAccess.WRITE)
	if bf == null:
		return {"ok": false, "error": "не записать issue_body.md"}
	bf.store_string(body)
	bf.close()
	var out: Array = []
	var args: PackedStringArray = PackedStringArray([
		"issue", "create",
		"--repo", REPO,
		"--title", title,
		"--body-file", ProjectSettings.globalize_path(body_file),
		"--label", "bug",
	])
	var code: int = OS.execute(gh, args, out, true, false)
	if code != 0:
		out.clear()
		args = PackedStringArray([
			"issue", "create",
			"--repo", REPO,
			"--title", title,
			"--body-file", ProjectSettings.globalize_path(body_file),
		])
		code = OS.execute(gh, args, out, true, false)
	var joined: String = "\n".join(out).strip_edges()
	if code != 0:
		return {"ok": false, "error": joined if joined != "" else ("gh exit %d" % code)}
	var url: String = joined.get_slice("\n", joined.get_slice_count("\n") - 1).strip_edges()
	if not url.begins_with("http"):
		url = "https://github.com/%s/issues" % REPO
	return {"ok": true, "url": url}


static func _title_from_description(text: String) -> String:
	var one: String = text.replace("\n", " ").strip_edges()
	if one.length() > 72:
		one = one.substr(0, 69) + "…"
	if one.is_empty():
		one = "Bug from MechSim"
	return "MechSim: " + one


static func _resolve_gh() -> String:
	var out: Array = []
	var code: int = OS.execute("where", PackedStringArray(["gh"]), out, true, false)
	if code == 0 and out.size() > 0:
		var line: String = str(out[0]).strip_edges()
		if line != "" and FileAccess.file_exists(line):
			return line
	var local_app: String = OS.get_environment("LOCALAPPDATA")
	var candidates: Array[String] = [
		"C:/Program Files/GitHub CLI/gh.exe",
	]
	if local_app != "":
		candidates.append(local_app.path_join("Programs/GitHub CLI/gh.exe"))
	for c in candidates:
		if c != "" and FileAccess.file_exists(c):
			return c
	out.clear()
	code = OS.execute("gh", PackedStringArray(["--version"]), out, true, false)
	if code == 0:
		return "gh"
	return ""


static func _ensure_inbox_branch(gh: String) -> void:
	var out: Array = []
	var code: int = OS.execute(gh, PackedStringArray(["api", "repos/%s/git/ref/heads/%s" % [REPO, INBOX_BRANCH]]), out, true, false)
	if code == 0:
		return
	out.clear()
	code = OS.execute(gh, PackedStringArray(["api", "repos/%s/git/ref/heads/main" % REPO, "--jq", ".object.sha"]), out, true, false)
	if code != 0 or out.is_empty():
		return
	var sha: String = str(out[0]).strip_edges()
	out.clear()
	OS.execute(gh, PackedStringArray([
		"api", "-X", "POST", "repos/%s/git/refs" % REPO,
		"-f", "ref=refs/heads/%s" % INBOX_BRANCH,
		"-f", "sha=%s" % sha,
	]), out, true, false)


static func _upload_file(gh: String, remote_path: String, local_path: String, message: String) -> Dictionary:
	var f := FileAccess.open(local_path, FileAccess.READ)
	if f == null:
		var abs_local: String = ProjectSettings.globalize_path(local_path)
		f = FileAccess.open(abs_local, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "не открыть %s" % local_path}
	var bytes: PackedByteArray = f.get_buffer(f.get_length())
	f.close()
	var b64: String = Marshalls.raw_to_base64(bytes)
	var payload := {
		"message": message,
		"content": b64,
		"branch": INBOX_BRANCH,
	}
	var tmp_json: String = "user://bugreports/_upload_payload.json"
	var jf := FileAccess.open(tmp_json, FileAccess.WRITE)
	if jf == null:
		return {"ok": false, "error": "payload json"}
	jf.store_string(JSON.stringify(payload))
	jf.close()
	var out: Array = []
	var code: int = OS.execute(gh, PackedStringArray([
		"api", "--method", "PUT",
		"repos/%s/contents/%s" % [REPO, remote_path],
		"--input", ProjectSettings.globalize_path(tmp_json),
	]), out, true, false)
	if code != 0:
		return {"ok": false, "error": "upload %s: %s" % [remote_path, "\n".join(out)]}
	return {"ok": true}
