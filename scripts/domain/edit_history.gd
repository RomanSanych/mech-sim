extends RefCounted
## Снимочный буфер отмены/повтора правок схемы.

const LIMIT := 50

var _undo: Array = [] # Array[Dictionary]
var _redo: Array = [] # Array[Dictionary]


func clear() -> void:
	_undo.clear()
	_redo.clear()


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func push(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	_undo.append(snapshot.duplicate(true))
	while _undo.size() > LIMIT:
		_undo.pop_front()
	_redo.clear()


func undo(current: Dictionary) -> Dictionary:
	## Возвращает снимок для восстановления; current уходит в redo.
	if _undo.is_empty():
		return {}
	var prev: Dictionary = _undo.pop_back()
	if not current.is_empty():
		_redo.append(current.duplicate(true))
		while _redo.size() > LIMIT:
			_redo.pop_front()
	return prev


func redo(current: Dictionary) -> Dictionary:
	if _redo.is_empty():
		return {}
	var nxt: Dictionary = _redo.pop_back()
	if not current.is_empty():
		_undo.append(current.duplicate(true))
		while _undo.size() > LIMIT:
			_undo.pop_front()
	return nxt
