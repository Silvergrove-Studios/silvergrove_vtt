class_name NativeMenuMirror
extends RefCounted
## Mirrors a MenuBar's PopupMenus into the operating system's global menu bar
## (macOS), while the in-window MenuBar stays where it is. Every native item
## just fires the PopupMenu's `id_pressed`, so there is one set of menu logic.
## Check marks, disabled state and labels are re-synced from the PopupMenu
## each time a native menu opens.

var _menus: Array[RID] = []
var _synced: Array = []   # [rid, popup] pairs


static func supported() -> bool:
	return NativeMenu.has_feature(NativeMenu.FEATURE_GLOBAL_MENU)


func mirror(bar: MenuBar) -> void:
	if not supported():
		return
	var main := NativeMenu.get_system_menu(NativeMenu.MAIN_MENU_ID)
	for child in bar.get_children():
		if child is PopupMenu:
			var rid := _build(child)
			NativeMenu.add_submenu_item(main, child.name, rid)


func free_menus() -> void:
	for rid in _menus:
		NativeMenu.free_menu(rid)
	_menus.clear()
	_synced.clear()


func _build(popup: PopupMenu) -> RID:
	var rid := NativeMenu.create_menu()
	_menus.append(rid)
	for i in popup.item_count:
		if popup.is_item_separator(i):
			NativeMenu.add_separator(rid)
			continue
		var sub := popup.get_item_submenu_node(i)
		if sub != null:
			NativeMenu.add_submenu_item(rid, popup.get_item_text(i), _build(sub))
			continue
		var id := popup.get_item_id(i)
		var fire := func(tag: Variant) -> void: popup.id_pressed.emit(int(tag))
		var accel := _native_accel(popup.get_item_accelerator(i))
		if popup.is_item_checkable(i):
			NativeMenu.add_check_item(rid, popup.get_item_text(i), fire, Callable(), id, accel)
		else:
			NativeMenu.add_item(rid, popup.get_item_text(i), fire, Callable(), id, accel)
	_synced.append([rid, popup])
	if NativeMenu.has_feature(NativeMenu.FEATURE_OPEN_CLOSE_CALLBACK):
		NativeMenu.set_popup_open_callback(rid, func() -> void: _sync(rid, popup))
	_sync(rid, popup)
	return rid


## Godot's CMD_OR_CTRL placeholder must be resolved before the OS sees it.
static func _native_accel(k: Key) -> Key:
	if k == KEY_NONE:
		return KEY_NONE
	if k & KEY_MASK_CMD_OR_CTRL:
		k = (k & ~KEY_MASK_CMD_OR_CTRL) | (KEY_MASK_META if OS.get_name() == "macOS" else KEY_MASK_CTRL)
	return k


## Indices line up 1:1 because every item, separators included, was mirrored.
func _sync(rid: RID, popup: PopupMenu) -> void:
	for i in popup.item_count:
		if i >= NativeMenu.get_item_count(rid):
			break
		if popup.is_item_separator(i) or popup.get_item_submenu_node(i) != null:
			continue
		NativeMenu.set_item_text(rid, i, popup.get_item_text(i))
		NativeMenu.set_item_disabled(rid, i, popup.is_item_disabled(i))
		if popup.is_item_checkable(i):
			NativeMenu.set_item_checked(rid, i, popup.is_item_checked(i))


## Call after the in-window menus change state (undo labels, view toggles).
func sync_all() -> void:
	for pair in _synced:
		_sync(pair[0], pair[1])
