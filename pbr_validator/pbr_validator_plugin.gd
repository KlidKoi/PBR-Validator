@tool
extends EditorPlugin

const dock_scene: PackedScene = preload("res://addons/pbr_validator/pbr_validator_dock.tscn")

var dock_instance: Control = null

var _is_docked: bool = true
var _floating_window: Window = null
var _floating_panel: PanelContainer = null
var _base_control: Control = null


func _enter_tree() -> void:
	_base_control = EditorInterface.get_base_control()
	dock_instance = dock_scene.instantiate()
	dock_instance.set_plugin_reference(self)
	dock_instance.dock_toggled.connect(_on_dock_toggled)
	
	# Initially, add it to the dock
	add_control_to_dock(DOCK_SLOT_RIGHT_UR, dock_instance)
	
	# Set the undock buttons initial icon
	var undock_icon: Texture2D = _base_control.get_theme_icon("MakeFloating", "EditorIcons")
	dock_instance.dock_toggle_button.icon = undock_icon

	# Focus the tab in the dock when plugin is enabled
	var tab_container: TabContainer = dock_instance.get_parent()
	if tab_container is TabContainer:
		for i in range(tab_container.get_tab_count()):
			if tab_container.get_tab_control(i) == dock_instance:
				tab_container.call_deferred("set", "current_tab", i)
				break
	
	# Connect to theme change signal
	_base_control.theme_changed.connect(_on_editor_theme_changed)
	
	print("PBR Validator plugin enabled.")


func _exit_tree() -> void:
	# Disconnect from theme change signal
	if is_instance_valid(_base_control):
		_base_control.theme_changed.disconnect(_on_editor_theme_changed)
	
	_base_control = null
	
	if is_instance_valid(dock_instance):
		dock_instance.cleanup()
		
		# If the window is floating, freeing the window will also free the dock_instance
		if is_instance_valid(_floating_window):
			_floating_window.queue_free()
		# Otherwise, if it's docked, remove and free it directly
		else:
			remove_control_from_docks(dock_instance)
			dock_instance.queue_free()

	dock_instance = null
	_floating_window = null
		
	print("PBR Validator plugin disabled.")


# Handle docking and undocking
func _on_dock_toggled() -> void:
	if not is_instance_valid(dock_instance):
		return
	
	if _is_docked:
		_undock_panel()
	else:
		_redock_panel()
	
	_is_docked = not _is_docked


# Undocks the panel into a floating window
func _undock_panel() -> void:
	remove_control_from_docks(dock_instance)
	
	_floating_window = Window.new()
	_floating_window.title = "PBR Validator"
	_floating_window.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_SCREEN_WITH_KEYBOARD_FOCUS
	_floating_window.size = Vector2i(500, 850)
	_floating_window.min_size = Vector2i(350, 850)
	
	# Create themed panel container to hold the dock instance
	_floating_panel = PanelContainer.new()
	_floating_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_update_panel_theme()
	
	# Create a MarginContainer for padding
	var margin_container: MarginContainer = MarginContainer.new()
	margin_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin_container.add_theme_constant_override("margin_left", 8)
	margin_container.add_theme_constant_override("margin_right", 8)
	margin_container.add_theme_constant_override("margin_top", 8)
	margin_container.add_theme_constant_override("margin_bottom", 8)
	
	_floating_window.add_child(_floating_panel)
	_floating_panel.add_child(margin_container)
	margin_container.add_child(dock_instance)
	
	# When the window is closed, re-dock the panel
	_floating_window.close_requested.connect(_on_dock_toggled)

	# Add to the main editor UI tree for proper theme inheritance
	_base_control.add_child(_floating_window)
	_floating_window.show()
	
	dock_instance.dock_toggle_button.icon = _base_control.get_theme_icon("Pin", "EditorIcons")
	dock_instance.dock_toggle_button.tooltip_text = "Dock Panel"


# Re-dock the panel into the main editor UI
func _redock_panel() -> void:
	if is_instance_valid(_floating_window):
		var margin_container: MarginContainer = _floating_panel.get_child(0)
		margin_container.remove_child(dock_instance)
		_base_control.remove_child(_floating_window)
		_floating_window.queue_free()
		_floating_window = null
		_floating_panel = null
	
	add_control_to_dock(DOCK_SLOT_RIGHT_UR, dock_instance)

	# Re-focus the tab when re-docking into the main editor UI
	var tab_container: TabContainer = dock_instance.get_parent()
	if tab_container is TabContainer:
		for i in range(tab_container.get_tab_count()):
			if tab_container.get_tab_control(i) == dock_instance:
				tab_container.call_deferred("set", "current_tab", i)
				break
				
	dock_instance.dock_toggle_button.icon = _base_control.get_theme_icon("MakeFloating", "EditorIcons")
	dock_instance.dock_toggle_button.tooltip_text = "Undock Panel"


func _on_editor_theme_changed() -> void:
	if is_instance_valid(_floating_panel):
		_update_panel_theme()


# Updates the floating panel's theme to match the editor's current theme.
func _update_panel_theme() -> void:
	if not is_instance_valid(_floating_panel):
		return
		
	# Create a new style for our panel
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	
	# Get the background color from the proper editor panel theme
	var theme_color: Color = _base_control.get_theme_color("base_color", "Editor")
	panel_style.bg_color = theme_color
	
	# Get standard editor theme constants for proper styling
	panel_style.content_margin_left = 4
	panel_style.content_margin_right = 4
	panel_style.content_margin_top = 4
	panel_style.content_margin_bottom = 4
	
	# Disable border
	panel_style.border_width_left = 0
	panel_style.border_width_right = 0
	panel_style.border_width_top = 0
	panel_style.border_width_bottom = 0
	
	_floating_panel.add_theme_stylebox_override("panel", panel_style)

