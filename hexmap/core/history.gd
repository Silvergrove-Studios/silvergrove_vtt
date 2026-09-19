class_name History
extends RefCounted
## Undo/redo for the editing session. A command is a pair of callables plus
## a label; `commit` runs the redo side and records it. Unlimited depth —
## a session's worth of map edits is small.

signal changed

var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
## While > 0, commits are collected into one group (a whole brush stroke).
var _group_depth := 0
var _group: Array[Dictionary] = []


func commit(label: String, redo: Callable, undo: Callable) -> void:
	redo.call()
	var cmd := {"label": label, "redo": redo, "undo": undo}
	if _group_depth > 0:
		_group.append(cmd)
	else:
		_undo.append(cmd)
		_redo.clear()
		changed.emit()


## Every commit until end_group() becomes one undo step.
func begin_group() -> void:
	_group_depth += 1


func end_group(label: String) -> void:
	_group_depth = maxi(0, _group_depth - 1)
	if _group_depth > 0 or _group.is_empty():
		return
	var cmds := _group.duplicate()
	_group.clear()
	_undo.append({
		"label": label,
		"redo": func() -> void:
			for c in cmds:
				c.redo.call(),
		"undo": func() -> void:
			for i in range(cmds.size() - 1, -1, -1):
				cmds[i].undo.call(),
	})
	_redo.clear()
	changed.emit()


func can_undo() -> bool: return not _undo.is_empty()
func can_redo() -> bool: return not _redo.is_empty()
func undo_label() -> String: return _undo.back().label if can_undo() else ""
func redo_label() -> String: return _redo.back().label if can_redo() else ""


func undo() -> void:
	if _undo.is_empty():
		return
	var c: Dictionary = _undo.pop_back()
	c.undo.call()
	_redo.append(c)
	changed.emit()


func redo() -> void:
	if _redo.is_empty():
		return
	var c: Dictionary = _redo.pop_back()
	c.redo.call()
	_undo.append(c)
	changed.emit()


func clear() -> void:
	_undo.clear()
	_redo.clear()
	_group.clear()
	_group_depth = 0
	changed.emit()
