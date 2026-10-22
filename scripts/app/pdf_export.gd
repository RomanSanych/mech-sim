extends RefCounted
## Минимальный PDF с одной страницей-изображением (JPEG), без внешних плагинов.


static func save_image_pdf(image: Image, path: String, title: String = "MechSim") -> Error:
	if image == null or image.is_empty():
		return ERR_INVALID_DATA
	var img: Image = image.duplicate()
	# JPEG нужен RGB8; blit_rect требует одинаковый формат — сначала выравниваем RGBA8.
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var flat := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	flat.fill(Color.WHITE)
	flat.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
	flat.convert(Image.FORMAT_RGB8)
	img = flat
	var jpeg: PackedByteArray = img.save_jpg_to_buffer(0.92)
	if jpeg.is_empty():
		return ERR_INVALID_DATA
	var w: int = img.get_width()
	var h: int = img.get_height()
	var page_w := float(w)
	var page_h := float(h)
	var content := "q\n%.2f 0 0 %.2f 0 0 cm\n/Im0 Do\nQ\n" % [page_w, page_h]
	var content_bytes := content.to_utf8_buffer()

	var parts: Array = []
	var offsets: Array = [-1] # 1-based object ids
	var cursor := 0

	var header := ("%PDF-1.4\n%%MechSim\n").to_utf8_buffer()
	parts.append(header)
	cursor += header.size()

	var obj1 := _obj(1, "<< /Type /Catalog /Pages 2 0 R >>")
	offsets.append(cursor)
	parts.append(obj1)
	cursor += obj1.size()

	var obj2 := _obj(2, "<< /Type /Pages /Kids [3 0 R] /Count 1 >>")
	offsets.append(cursor)
	parts.append(obj2)
	cursor += obj2.size()

	var page_dict := "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %.2f %.2f] /Contents 4 0 R /Resources << /XObject << /Im0 5 0 R >> >> >>" % [page_w, page_h]
	var obj3 := _obj(3, page_dict)
	offsets.append(cursor)
	parts.append(obj3)
	cursor += obj3.size()

	var obj4_head := ("4 0 obj\n<< /Length %d >>\nstream\n" % content_bytes.size()).to_utf8_buffer()
	var obj4_tail := "\nendstream\nendobj\n".to_utf8_buffer()
	offsets.append(cursor)
	parts.append(obj4_head)
	parts.append(content_bytes)
	parts.append(obj4_tail)
	cursor += obj4_head.size() + content_bytes.size() + obj4_tail.size()

	var img_dict := "<< /Type /XObject /Subtype /Image /Width %d /Height %d /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length %d >>" % [w, h, jpeg.size()]
	var obj5_head := ("5 0 obj\n%s\nstream\n" % img_dict).to_utf8_buffer()
	var obj5_tail := "\nendstream\nendobj\n".to_utf8_buffer()
	offsets.append(cursor)
	parts.append(obj5_head)
	parts.append(jpeg)
	parts.append(obj5_tail)
	cursor += obj5_head.size() + jpeg.size() + obj5_tail.size()

	var info := _obj(6, "<< /Title (%s) /Creator (MechSim) /Producer (MechSim) >>" % _pdf_escape(title))
	offsets.append(cursor)
	parts.append(info)
	cursor += info.size()

	var xref_pos := cursor
	var xref := "xref\n0 7\n0000000000 65535 f \n".to_utf8_buffer()
	parts.append(xref)
	for i in range(1, 7):
		var line := "%010d 00000 n \n" % int(offsets[i])
		parts.append(line.to_utf8_buffer())
	var trailer := ("trailer\n<< /Size 7 /Root 1 0 R /Info 6 0 R >>\nstartxref\n%d\n%%%%EOF\n" % xref_pos).to_utf8_buffer()
	parts.append(trailer)

	var out := PackedByteArray()
	for p in parts:
		out.append_array(p)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(out)
	f.close()
	return OK


static func _obj(id: int, body: String) -> PackedByteArray:
	return ("%d 0 obj\n%s\nendobj\n" % [id, body]).to_utf8_buffer()


static func _pdf_escape(text: String) -> String:
	return text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
