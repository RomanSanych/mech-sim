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
	var _win: Window
	var _edit: TextEdit
	var _status: Label
	var _send_btn: Button
	var _cancel_btn: Button

	func run(circuit, get_screenshot: Callable, save_scene_tmp: Callable) -> void:
		_circuit = circuit
		_get_screenshot = get_screenshot
		_save_scene_tmp = save_scene_tmp
		_win = Window.new()
		_win.title = "Сообщить об ошибке"
		_win.unresizable = true
		_win.transient = true
		_win.exclusive = true
		_win.always_on_top = true
		_win.min_size = Vector2i(440, 260)
		_win.size = Vector2i(460, 280)
		_apply_window_theme(_win)
		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		margin.add_theme_constant_override("margin_left", 14)
		margin.add_theme_constant_override("margin_right", 14)
		margin.add_theme_constant_override("margin_top", 12)
		margin.add_theme_constant_override("margin_bottom", 12)
		_win.add_child(margin)
		var root := VBoxContainer.new()
		root.add_theme_constant_override("separation", 8)
		margin.add_child(root)
		var hint := Label.new()
		hint.text = "Кратко опишите проблему. К отчёту приложатся скриншот и файл сцены. Нужен gh auth login."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_color_override("font_color", UiTheme.muted())
		hint.add_theme_font_size_override("font_size", 12)
		root.add_child(hint)
		_edit = TextEdit.new()
		_edit.custom_minimum_size = Vector2(0, 110)
		_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_edit.placeholder_text = "Что случилось? Шаги воспроизведения…"
		_style_text_edit(_edit)
		root.add_child(_edit)
		_status = Label.new()
		_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_status.add_theme_color_override("font_color", UiTheme.muted())
		_status.add_theme_font_size_override("font_size", 11)
		_status.custom_minimum_size = Vector2(0, 28)
		root.add_child(_status)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_END
		row.add_theme_constant_override("separation", 8)
		root.add_child(row)
		_cancel_btn = Button.new()
		_cancel_btn.text = "Отмена"
		_cancel_btn.custom_minimum_size = Vector2(96, 30)
		_style_dlg_button(_cancel_btn, UiTheme.neutral_btn())
		_cancel_btn.pressed.connect(_on_cancel)
		row.add_child(_cancel_btn)
		_send_btn = Button.new()
		_send_btn.text = "Отправить"
		_send_btn.custom_minimum_size = Vector2(110, 30)
		_style_dlg_button(_send_btn, UiTheme.accent())
		_send_btn.pressed.connect(_on_send)
		row.add_child(_send_btn)
		add_child(_win)
		_win.close_requested.connect(_on_cancel)
		_win.popup_centered_clamped(Vector2i(460, 280), 0.1)
		_edit.grab_focus()

	func _on_cancel() -> void:
		if is_instance_valid(_win):
			_win.hide()
		queue_free()

	func _on_send() -> void:
		var text: String = _edit.text.strip_edges()
		if text.is_empty():
			_status.text = "Введите описание."
			return
		_send_btn.disabled = true
		_cancel_btn.disabled = true
		_status.text = "Готовлю скриншот и сцену…"
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img: Image = _get_screenshot.call()
		if img == null or img.is_empty():
			_status.text = "Не удалось сделать скриншот."
			_send_btn.disabled = false
			_cancel_btn.disabled = false
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
			_send_btn.disabled = false
			_cancel_btn.disabled = false
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
			await get_tree().create_timer(1.0).timeout
			_on_cancel()
		else:
			_status.text = "Ошибка: %s · файлы: %s" % [
				str(result.get("error", "?")),
				ProjectSettings.globalize_path(dir),
			]
			_send_btn.disabled = false
			_cancel_btn.disabled = false

	func _apply_window_theme(win: Window) -> void:
		var panel := StyleBoxFlat.new()
		panel.bg_color = UiTheme.panel_bg()
		panel.border_color = UiTheme.menu_border()
		panel.set_border_width_all(1)
		panel.set_corner_radius_all(8)
		panel.content_margin_left = 0
		panel.content_margin_right = 0
		panel.content_margin_top = 0
		panel.content_margin_bottom = 0
		win.add_theme_stylebox_override("embedded_border", panel)
		win.add_theme_color_override("title_color", UiTheme.text())
		win.add_theme_font_size_override("title_font_size", 14)

	func _style_text_edit(edit: TextEdit) -> void:
		var normal := StyleBoxFlat.new()
		normal.bg_color = UiTheme.menu_field_bg()
		normal.border_color = UiTheme.menu_border()
		normal.set_border_width_all(1)
		normal.set_corner_radius_all(6)
		normal.set_content_margin_all(8)
		edit.add_theme_stylebox_override("normal", normal)
		edit.add_theme_stylebox_override("focus", normal)
		edit.add_theme_color_override("font_color", UiTheme.text())
		edit.add_theme_color_override("font_placeholder_color", UiTheme.muted())
		edit.add_theme_font_size_override("font_size", 13)

	func _style_dlg_button(button: Button, color: Color) -> void:
		var normal := StyleBoxFlat.new()
		normal.bg_color = color
		normal.set_corner_radius_all(6)
		normal.set_content_margin_all(8)
		var hover := normal.duplicate()
		hover.bg_color = color.lightened(0.12)
		var pressed := normal.duplicate()
		pressed.bg_color = color.darkened(0.08)
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("pressed", pressed)
		var fg := Color(0.97, 0.98, 0.99)
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
			button.add_theme_color_override(key, fg if key != "font_disabled_color" else Color(0.55, 0.58, 0.62))
		button.add_theme_font_size_override("font_size", 13)

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
