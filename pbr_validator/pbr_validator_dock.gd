@tool
extends Control

# This script handles the UI logic for the PBR Validator dock.

signal dock_toggled

enum ValidationMode { LIT = -1, ALBEDO = 0, ALBEDO_VALIDATION = 1, ROUGHNESS = 2, METALLIC = 3 }
enum AlbedoPreset { STRICT, NON_STRICT, CUSTOM }
enum InRangeMode { VISUALIZE, HIGHLIGHT }

const STRICT_ALBEDO_MIN_SRGB: int = 50
const STRICT_ALBEDO_MAX_SRGB: int = 243
const NON_STRICT_ALBEDO_MIN_SRGB: int = 30
const NON_STRICT_ALBEDO_MAX_SRGB: int = 250

var _plugin_ref: EditorPlugin = null
var manager: Node = null
var _validator_active: bool = false

var _is_updating_ui: bool = false

@onready var dock_toggle_button: Button = %DockToggleButton

@onready var enable_button: Button = %EnableToggleButton

@onready var albedo_options_container: VBoxContainer = %AlbedoOptionsContainer
@onready var roughness_options_container: VBoxContainer = %RoughnessOptionsContainer
@onready var albedo_range_preset_selector: OptionButton = %AlbedoRangePresetSelector
@onready var custom_albedo_range_container: GridContainer = %CustomAlbedoRangeContainer
@onready var albedo_range_min_slider: HSlider = %AlbedoRangeMinSlider
@onready var albedo_range_min_spinbox: SpinBox = %AlbedoRangeMinSpinBox
@onready var albedo_range_max_slider: HSlider = %AlbedoRangeMaxSlider
@onready var albedo_range_max_spinbox: SpinBox = %AlbedoRangeMaxSpinBox
@onready var falloff_slider: HSlider = %FalloffSlider
@onready var falloff_spinbox: SpinBox = %FalloffSpinBox
@onready var hard_edged_toggle: CheckBox = %HardEdgedToggle
@onready var in_range_mode_selector: OptionButton = %InRangeModeSelector
@onready var lit_button: Button = %LitButton
@onready var albedo_button: Button = %AlbedoButton
@onready var roughness_button: Button = %RoughnessButton
@onready var metallic_button: Button = %MetallicButton
@onready var under_color_picker: ColorPickerButton = %UnderColorPicker
@onready var over_color_picker: ColorPickerButton = %OverColorPicker
@onready var in_range_color_picker: ColorPickerButton = %InRangeColorPicker
@onready var reset_albedo_button: Button = %ResetAlbedoButton
@onready var highlight_extremes_toggle: CheckBox = %HighlightExtremesToggle
@onready var extreme_color_picker: ColorPickerButton = %ExtremeColorPicker
@onready var reset_roughness_button: Button = %ResetRoughnessButton


# Helper function to convert sRGB (0-255) to the correct linear color space.
func _srgb_to_linear(srgb_value: float) -> float:
	var srgb_normalized: float = srgb_value / 255.0
	if srgb_normalized <= 0.04045:
		return srgb_normalized / 12.92
	else:
		return pow((srgb_normalized + 0.055) / 1.055, 2.4)


func _ready() -> void:
	dock_toggle_button.pressed.connect(func(): emit_signal(&"dock_toggled"))
	
	enable_button.toggled.connect(_on_enable_button_toggled)
	albedo_range_preset_selector.item_selected.connect(_on_albedo_preset_selected)
	in_range_mode_selector.item_selected.connect(_on_in_range_mode_selected)
	hard_edged_toggle.toggled.connect(_on_hard_edged_toggled)
	reset_albedo_button.pressed.connect(_on_reset_albedo_pressed)
	
	lit_button.toggled.connect(_on_quick_view_button_toggled.bind(ValidationMode.LIT))
	albedo_button.toggled.connect(_on_quick_view_button_toggled.bind(ValidationMode.ALBEDO))
	roughness_button.toggled.connect(_on_quick_view_button_toggled.bind(ValidationMode.ROUGHNESS))
	metallic_button.toggled.connect(_on_quick_view_button_toggled.bind(ValidationMode.METALLIC))
	
	under_color_picker.color_changed.connect(_on_under_color_changed)
	over_color_picker.color_changed.connect(_on_over_color_changed)
	in_range_color_picker.color_changed.connect(_on_in_range_color_changed)
	
	albedo_range_min_slider.value_changed.connect(_on_albedo_range_changed.bind(true))
	albedo_range_min_spinbox.value_changed.connect(_on_albedo_range_changed.bind(true))
	albedo_range_max_slider.value_changed.connect(_on_albedo_range_changed.bind(false))
	albedo_range_max_spinbox.value_changed.connect(_on_albedo_range_changed.bind(false))
	
	falloff_slider.value_changed.connect(_on_falloff_changed)
	falloff_spinbox.value_changed.connect(_on_falloff_changed)
	
	highlight_extremes_toggle.toggled.connect(_on_highlight_extremes_toggled)
	extreme_color_picker.color_changed.connect(_on_extreme_color_changed)
	reset_roughness_button.pressed.connect(_on_reset_roughness_pressed)
	
	albedo_options_container.hide()
	roughness_options_container.hide()
	custom_albedo_range_container.hide()


func set_plugin_reference(plugin: EditorPlugin) -> void:
	_plugin_ref = plugin


func cleanup() -> void:
	if _validator_active and is_instance_valid(manager):
		manager.call("disable_validation_mode")
		manager.queue_free()
		manager = null


# Central function for handling all mode changes ---
func _set_mode(mode_id: ValidationMode) -> void:
	# Step 1: Handle the 'LIT' case, which always disables the validator.
	if mode_id == ValidationMode.LIT:
		if _validator_active:
			_disable_validator()
		return

	# Step 2: If a quick view mode is selected, ensure the main toggle button is reset
	# to its default, un-pressed state. This handles switching from the main
	# "Albedo Validation" mode to a quick view.
	if mode_id != ValidationMode.ALBEDO_VALIDATION:
		enable_button.set_pressed_no_signal(false)
		enable_button.text = "Enable PBR Validator"

	# Step 3: If the validator isn't running at all, activate its core logic.
	# This happens in the background without affecting the main toggle button's UI.
	if not _validator_active:
		_activate_validator_logic()
	
	# If we've reached here, the validator is already on.
	if not is_instance_valid(manager) or _is_updating_ui: return

	_is_updating_ui = true

	# Step 4: Update the backend manager with the new validation mode.
	manager.call("set_validation_mode", mode_id)

	# Step 5: Sync the UI states (quick view buttons, option panels).
	match mode_id:
		ValidationMode.ALBEDO:
			albedo_button.button_pressed = true
		ValidationMode.ROUGHNESS:
			roughness_button.button_pressed = true
		ValidationMode.METALLIC:
			metallic_button.button_pressed = true
		ValidationMode.ALBEDO_VALIDATION:
			# Ensure no quick view button is pressed when in the main validation mode
			if lit_button.button_group:
				var pressed_button = lit_button.button_group.get_pressed_button()
				if pressed_button:
					pressed_button.button_pressed = false
	
	albedo_options_container.visible = (mode_id == ValidationMode.ALBEDO_VALIDATION)
	roughness_options_container.visible = (mode_id == ValidationMode.ROUGHNESS)
	
	_is_updating_ui = false


func _on_enable_button_toggled(button_pressed: bool) -> void:
	if button_pressed:
		# Explicitly enables albedo validation mode.
		_update_main_toggle_button_ui()
		_set_mode(ValidationMode.ALBEDO_VALIDATION)
	else:
		# If the main button is toggled off, disable everything.
		_disable_validator()


# Updates the main toggle button's UI and ensures the validator logic is active.
func _update_main_toggle_button_ui() -> void:
	enable_button.text = "Disable PBR Validator"
	enable_button.set_pressed_no_signal(true)
	_activate_validator_logic()


# Activates the core validator logic without changing the main toggle button UI.
func _activate_validator_logic() -> void:
	if _validator_active: return

	if not _plugin_ref:
		printerr("PBR Validator: Plugin reference not set.")
		return
	if not is_instance_valid(manager):
		var manager_script: Script = load("res://addons/pbr_validator/pbr_validator_manager.gd")
		manager = manager_script.new()
		add_child(manager)
		
		# Initialize the UI controls to match the manager's default state.
		# This ensures that if defaults are changed in the manager script, the
		# UI reflects those changes the first time it's opened.
		_on_reset_albedo_pressed()
		_on_reset_roughness_pressed()
	
	_validator_active = true
	var scene_root: Node = EditorInterface.get_edited_scene_root()
	if scene_root:
		manager.call("enable_validation_mode", scene_root)
	else:
		printerr("PBR Validator: No scene is currently being edited.")
		_validator_active = false


func _disable_validator() -> void:
	if not _validator_active: return
	
	_validator_active = false
	
	# Always reset the main toggle button's UI when disabling.
	enable_button.text = "Enable PBR Validator"
	enable_button.set_pressed_no_signal(false)
	
	if is_instance_valid(manager):
		manager.call("disable_validation_mode")
		manager.queue_free()
		manager = null
	
	# Un-press any active quick view button to return to a neutral state.
	_is_updating_ui = true
	if lit_button.button_group:
		var pressed_button = lit_button.button_group.get_pressed_button()
		if pressed_button:
			pressed_button.button_pressed = false
	_is_updating_ui = false
	albedo_options_container.hide()
	roughness_options_container.hide()


# Called when a quick view button is toggled.
func _on_quick_view_button_toggled(toggled_on: bool, mode: ValidationMode) -> void:
	if toggled_on and not _is_updating_ui:
		_set_mode(mode)
		if mode == ValidationMode.LIT:
			lit_button.button_pressed = false


# Called when the user selects a new albedo preset.
func _on_albedo_preset_selected(index: int) -> void:
	if not is_instance_valid(manager): return
	
	_is_updating_ui = true
	
	match albedo_range_preset_selector.get_item_id(index):
		AlbedoPreset.STRICT: # Strict - Based on common PBR guidelines for non-metals.
			custom_albedo_range_container.hide()
			albedo_range_min_slider.value = STRICT_ALBEDO_MIN_SRGB
			albedo_range_min_spinbox.value = STRICT_ALBEDO_MIN_SRGB
			albedo_range_max_slider.value = STRICT_ALBEDO_MAX_SRGB
			albedo_range_max_spinbox.value = STRICT_ALBEDO_MAX_SRGB
			manager.call("set_albedo_range", _srgb_to_linear(STRICT_ALBEDO_MIN_SRGB), _srgb_to_linear(STRICT_ALBEDO_MAX_SRGB))
		AlbedoPreset.NON_STRICT: # Non-Strict - A more relaxed range for artistic flexibility.
			custom_albedo_range_container.hide()
			albedo_range_min_slider.value = NON_STRICT_ALBEDO_MIN_SRGB
			albedo_range_min_spinbox.value = NON_STRICT_ALBEDO_MIN_SRGB
			albedo_range_max_slider.value = NON_STRICT_ALBEDO_MAX_SRGB
			albedo_range_max_spinbox.value = NON_STRICT_ALBEDO_MAX_SRGB
			manager.call("set_albedo_range", _srgb_to_linear(NON_STRICT_ALBEDO_MIN_SRGB), _srgb_to_linear(NON_STRICT_ALBEDO_MAX_SRGB))
		AlbedoPreset.CUSTOM: # Custom
			custom_albedo_range_container.show()
			_on_albedo_range_changed(albedo_range_min_slider.value, true) # Update manager with current custom values

	_is_updating_ui = false


# Called when the user selects a new in-range mode.
func _on_in_range_mode_selected(index: int) -> void:
	if not is_instance_valid(manager): return
	
	var mode: InRangeMode = in_range_mode_selector.get_item_id(index) as InRangeMode
	manager.call("set_in_range_mode", mode)


# Handler for the Hard-Edged toggle
func _on_hard_edged_toggled(button_pressed: bool) -> void:
	if not is_instance_valid(manager): return
	manager.call("set_hard_edges", button_pressed)
	falloff_slider.editable = not button_pressed
	falloff_spinbox.editable = not button_pressed


# Resets all albedo options to their default values.
func _on_reset_albedo_pressed() -> void:
	_is_updating_ui = true
	
	# Reset preset selector to Non-Strict
	albedo_range_preset_selector.select(AlbedoPreset.NON_STRICT)
	_on_albedo_preset_selected(AlbedoPreset.NON_STRICT)
	
	# Reset range mode
	in_range_mode_selector.select(manager.DEFAULT_IN_RANGE_MODE)
	_on_in_range_mode_selected(manager.DEFAULT_IN_RANGE_MODE)
	
	# Reset hard edges
	hard_edged_toggle.button_pressed = manager.DEFAULT_USE_HARD_EDGES
	_on_hard_edged_toggled(manager.DEFAULT_USE_HARD_EDGES)
	
	# Reset falloff
	falloff_slider.value = manager.DEFAULT_FALLOFF
	_on_falloff_changed(manager.DEFAULT_FALLOFF)
	
	# Reset colors
	under_color_picker.color = manager.DEFAULT_UNDER_COLOR
	_on_under_color_changed(manager.DEFAULT_UNDER_COLOR)
	over_color_picker.color = manager.DEFAULT_OVER_COLOR
	_on_over_color_changed(manager.DEFAULT_OVER_COLOR)
	in_range_color_picker.color = manager.DEFAULT_IN_RANGE_COLOR
	_on_in_range_color_changed(manager.DEFAULT_IN_RANGE_COLOR)
	
	_is_updating_ui = false

	# Manually trigger a preset selection to hide custom controls if necessary
	_on_albedo_preset_selected(albedo_range_preset_selector.selected)


# Resets all roughness options to their default values.
func _on_reset_roughness_pressed() -> void:
	_is_updating_ui = true
	
	# Reset highlight extremes
	highlight_extremes_toggle.button_pressed = manager.DEFAULT_HIGHLIGHT_ROUGHNESS_EXTREMES
	_on_highlight_extremes_toggled(manager.DEFAULT_HIGHLIGHT_ROUGHNESS_EXTREMES)
	
	# Reset extreme color
	extreme_color_picker.color = manager.DEFAULT_ROUGHNESS_EXTREME_COLOR
	_on_extreme_color_changed(manager.DEFAULT_ROUGHNESS_EXTREME_COLOR)
	
	_is_updating_ui = false


# Handlers for Roughness options
func _on_highlight_extremes_toggled(button_pressed: bool) -> void:
	if not is_instance_valid(manager): return
	manager.call("set_highlight_roughness_extremes", button_pressed)


func _on_extreme_color_changed(color: Color) -> void:
	if not is_instance_valid(manager): return
	manager.call("set_roughness_extreme_color", color)


# A handler for albedo range changes.
func _on_albedo_range_changed(value: float, is_min_control: bool) -> void:
	if _is_updating_ui: return

	var min_srgb: float
	var max_srgb: float

	if is_min_control:
		_sync_slider_and_spinbox(value, albedo_range_min_slider, albedo_range_min_spinbox)
		min_srgb = value
		max_srgb = albedo_range_max_slider.value
	else:
		_sync_slider_and_spinbox(value, albedo_range_max_slider, albedo_range_max_spinbox)
		min_srgb = albedo_range_min_slider.value
		max_srgb = value

	if min_srgb >= max_srgb:
		if is_min_control:
			max_srgb = min_srgb + 1
			_sync_slider_and_spinbox(max_srgb, albedo_range_max_slider, albedo_range_max_spinbox)
		else:
			min_srgb = max_srgb - 1
			_sync_slider_and_spinbox(min_srgb, albedo_range_min_slider, albedo_range_min_spinbox)

	if is_instance_valid(manager):
		manager.call("set_albedo_range", _srgb_to_linear(min_srgb), _srgb_to_linear(max_srgb))


# A simplified handler for falloff changes.
func _on_falloff_changed(value: float) -> void:
	if _is_updating_ui: return
	
	_sync_slider_and_spinbox(value, falloff_slider, falloff_spinbox)
	
	if is_instance_valid(manager):
		manager.call("set_falloff", value)


# A helper to keep a slider and a spinbox in sync.
func _sync_slider_and_spinbox(value: float, slider: HSlider, spinbox: SpinBox) -> void:
	_is_updating_ui = true
	slider.value = value
	spinbox.value = value
	_is_updating_ui = false


# Handlers for the ColorPickerButtons
func _on_under_color_changed(color: Color) -> void:
	if not is_instance_valid(manager): return
	manager.call("set_under_color", color)


func _on_over_color_changed(color: Color) -> void:
	if not is_instance_valid(manager): return
	manager.call("set_over_color", color)


func _on_in_range_color_changed(color: Color) -> void:
	if not is_instance_valid(manager): return
	manager.call("set_in_range_color", color)


