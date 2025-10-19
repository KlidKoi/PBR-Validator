@tool
extends Node

# This script manages the core logic of enabling/disabling the PBR validator.

# --- Shader Parameter Constants ---
const VALIDATION_MODE_PARAM: StringName = "validation_mode"
const MIN_ALBEDO_PARAM: StringName = "min_albedo_linear"
const MAX_ALBEDO_PARAM: StringName = "max_albedo_linear"
const IN_RANGE_MODE_PARAM: StringName = "in_range_mode"
const UNDER_COLOR_PARAM: StringName = "under_color"
const OVER_COLOR_PARAM: StringName = "over_color"
const IN_RANGE_COLOR_PARAM: StringName = "in_range_color"
const FALLOFF_PARAM: StringName = "falloff"
const HARD_EDGES_PARAM: StringName = "use_hard_edges"
const HIGHLIGHT_ROUGHNESS_EXTREMES_PARAM: StringName = "highlight_roughness_extremes"
const ROUGHNESS_EXTREME_COLOR_PARAM: StringName = "roughness_extreme_color"
const ALBEDO_SOLID_COLOR_PARAM: StringName = "albedo_solid_color"
const ALBEDO_TEXTURE_PARAM: StringName = "albedo_texture"
const ROUGHNESS_TEXTURE_PARAM: StringName = "roughness_texture"
const METALLIC_TEXTURE_PARAM: StringName = "metallic_texture"
const ROUGHNESS_VALUE_PARAM: StringName = "roughness_value"
const METALLIC_VALUE_PARAM: StringName = "metallic_value"
const USE_TRIPLANAR_PARAM: StringName = "use_triplanar"
const TRIPLANAR_SCALE_PARAM: StringName = "triplanar_scale"
const TRIPLANAR_SHARPNESS_PARAM: StringName = "triplanar_sharpness"

# --- Default Values Constants ---
const DEFAULT_MIN_ALBEDO: float = 0.010
const DEFAULT_MAX_ALBEDO: float = 0.946
const DEFAULT_IN_RANGE_MODE: int = 1
const DEFAULT_UNDER_COLOR: Color = Color.RED
const DEFAULT_OVER_COLOR: Color = Color.BLUE
const DEFAULT_IN_RANGE_COLOR: Color = Color.GREEN
const DEFAULT_FALLOFF: float = 0.02
const DEFAULT_USE_HARD_EDGES: bool = true
const DEFAULT_HIGHLIGHT_ROUGHNESS_EXTREMES: bool = false
const DEFAULT_ROUGHNESS_EXTREME_COLOR: Color = Color.MAGENTA

var _base_override_material: ShaderMaterial = null
var _original_material_state: Dictionary[Node, Dictionary] = {}
var _renderable_nodes: Array[Node] = []

var _world_environment_node: WorldEnvironment = null
var _original_environment: Environment = null

# --- Store current validation parameters ---
var _current_mode: int = 0
var _min_albedo: float = DEFAULT_MIN_ALBEDO
var _max_albedo: float = DEFAULT_MAX_ALBEDO
var _in_range_mode: int = DEFAULT_IN_RANGE_MODE
var _under_color: Color = DEFAULT_UNDER_COLOR
var _over_color: Color = DEFAULT_OVER_COLOR
var _in_range_color: Color = DEFAULT_IN_RANGE_COLOR
var _falloff: float = DEFAULT_FALLOFF
var _use_hard_edges: bool = DEFAULT_USE_HARD_EDGES
var _highlight_roughness_extremes: bool = DEFAULT_HIGHLIGHT_ROUGHNESS_EXTREMES
var _roughness_extreme_color: Color = DEFAULT_ROUGHNESS_EXTREME_COLOR



func _ready() -> void:
	# Load the base shader material resource only once.
	var shader: Shader = load("res://addons/pbr_validator/pbr_validator.gdshader")
	_base_override_material = ShaderMaterial.new()
	_base_override_material.shader = shader
	print("PBR Validator: Loaded validation shader material.")


func _process(_delta: float) -> void:
	# This loop runs every frame to ensure material changes are caught in real-time.
	# It only iterates over the cached list of renderable nodes, which is much
	# more efficient than scanning the whole scene tree.
	for node: Node in _renderable_nodes:
		if not is_instance_valid(node):
			# Node was likely deleted, but the signal hasn't been processed yet.
			# It will be cleaned up from the list shortly.
			continue
		
		_process_renderable(node)


# --- UI-Connected Functions ---

# Called by the UI to change the validation mode.
func set_validation_mode(mode: int) -> void:
	_current_mode = mode

# Called by the UI to set the albedo range from a preset.
func set_albedo_range(min_val: float, max_val: float) -> void:
	_min_albedo = min_val
	_max_albedo = max_val

# Called by the UI to set the in-range display mode.
func set_in_range_mode(mode: int) -> void:
	_in_range_mode = mode

# Called by the UI to set the gradient falloff.
func set_falloff(value: float) -> void:
	_falloff = value

# Called by the UI to toggle hard-edged mode.
func set_hard_edges(value: bool) -> void:
	_use_hard_edges = value

# Functions for Roughness validation settings
func set_highlight_roughness_extremes(value: bool) -> void:
	_highlight_roughness_extremes = value

func set_roughness_extreme_color(color: Color) -> void:
	_roughness_extreme_color = color

# Functions to set custom validation colors
func set_under_color(color: Color) -> void:
	_under_color = color

func set_over_color(color: Color) -> void:
	_over_color = color

func set_in_range_color(color: Color) -> void:
	_in_range_color = color


# --- Core Validation Logic ---

# Enables the validation mode.
func enable_validation_mode(root_node: Node) -> void:
	if not _original_material_state.is_empty():
		return # Already enabled.

	# Disable WorldEnvironment for consistent lighting
	_world_environment_node = _find_world_environment_recursively(root_node)
	if _world_environment_node:
		_original_environment = _world_environment_node.environment
		_world_environment_node.environment = null
		print("PBR Validator: WorldEnvironment disabled.")

	# Connect to scene tree signals to track node changes
	var tree: SceneTree = get_tree()
	if tree:
		tree.node_added.connect(_on_node_added)
		tree.node_removed.connect(_on_node_removed)

	# Initial scan of the scene to find all renderable nodes
	_renderable_nodes.clear()
	_find_renderable_nodes_recursively(root_node, _renderable_nodes)
	for node: Node in _renderable_nodes:
		_apply_validation_to_node(node)

	set_process(true)
	print("PBR Validator: Enabled.")


# Disables the validation mode and restoring original materials.
func disable_validation_mode() -> void:
	if _original_material_state.is_empty():
		return

	set_process(false)

	# Disconnect from scene tree signals
	var tree: SceneTree = get_tree()
	if tree:
		if tree.node_added.is_connected(_on_node_added):
			tree.node_added.disconnect(_on_node_added)
		if tree.node_removed.is_connected(_on_node_removed):
			tree.node_removed.disconnect(_on_node_removed)

	# Restore original materials
	for node: Node in _renderable_nodes:
		_restore_original_material(node)
	
	# Restore WorldEnvironment
	if is_instance_valid(_world_environment_node) and _original_environment:
		_world_environment_node.environment = _original_environment
		print("PBR Validator: WorldEnvironment restored.")
	
	_world_environment_node = null
	_original_environment = null
	_original_material_state.clear()
	_renderable_nodes.clear()
	
	print("PBR Validator: Disabled and restored original materials.")


# --- Signal Handlers ---

func _on_node_added(node: Node) -> void:
	# If a new node is added to the scene, apply validation if it's renderable.
	var nodes_to_add: Array[Node] = []
	_find_renderable_nodes_recursively(node, nodes_to_add)
	for n: Node in nodes_to_add:
		if not n in _renderable_nodes:
			_renderable_nodes.append(n)
			_apply_validation_to_node(n)


func _on_node_removed(node: Node) -> void:
	# If a node is removed, restore its material and remove it from the list.
	if node in _original_material_state:
		_restore_original_material(node)
		_renderable_nodes.erase(node)


# --- Material Processing ---

func _apply_validation_to_node(node: Node) -> void:
	_process_renderable(node)


func _restore_original_material(node: Node) -> void:
	if not node in _original_material_state:
		return

	if is_instance_valid(node):
		var original_state: Dictionary = _original_material_state[node]
		if node is MeshInstance3D:
			node.material_override = original_state.material_override
			var surf_overrides: Array = original_state.surface_overrides
			for i: int in range(surf_overrides.size()):
				node.set_surface_override_material(i, surf_overrides[i])
		elif node is CSGPrimitive3D:
			node.material_override = original_state.material_override
			node.material = original_state.material
	
	_original_material_state.erase(node)


func _process_renderable(node: Node) -> void:
	if not (node is MeshInstance3D or node is CSGPrimitive3D):
		return

	# Initialize the node if it's the first time we see it.
	if not _original_material_state.has(node):
		var original_state: Dictionary
		if node is MeshInstance3D:
			var mesh: MeshInstance3D = node
			if not mesh.mesh: return
			
			original_state = { "material_override": mesh.material_override, "surface_overrides": [] }
			for i: int in range(mesh.mesh.get_surface_count()):
				original_state.surface_overrides.append(mesh.get_surface_override_material(i))
			
			if mesh.material_override:
				mesh.material_override = null
			
			for i: int in range(mesh.mesh.get_surface_count()):
				mesh.set_surface_override_material(i, _base_override_material.duplicate(true))

		elif node is CSGPrimitive3D:
			var csg: CSGPrimitive3D = node
			original_state = { "material": csg.material, "material_override": csg.material_override }
			
			csg.material_override = null
			csg.material = _base_override_material.duplicate(true)
		
		if original_state:
			_original_material_state[node] = original_state

	# Update the validation material parameters.
	var saved_state: Dictionary = _original_material_state.get(node)
	if not saved_state: return

	if node is MeshInstance3D:
		var mesh: MeshInstance3D = node
		if not mesh.mesh: return

		for i: int in range(mesh.mesh.get_surface_count()):
			var validation_material: Material = mesh.get_surface_override_material(i)
			if validation_material is ShaderMaterial:
				var users_material: Material = saved_state.material_override
				if not users_material:
					users_material = saved_state.surface_overrides[i]
				if not users_material:
					users_material = mesh.mesh.surface_get_material(i)
				_apply_parameters_to_material(users_material, validation_material)

	elif node is CSGPrimitive3D:
		var csg: CSGPrimitive3D = node
		var validation_material: Material = csg.material
		if validation_material is ShaderMaterial:
			var users_material: Material = saved_state.material_override
			if not users_material:
				users_material = saved_state.material
			_apply_parameters_to_material(users_material, validation_material)


# Centralizes the logic for setting shader parameters.
func _apply_parameters_to_material(original_material: Material, validation_material: ShaderMaterial) -> void:
	# Albedo Params
	validation_material.set_shader_parameter(VALIDATION_MODE_PARAM, _current_mode)
	validation_material.set_shader_parameter(MIN_ALBEDO_PARAM, _min_albedo)
	validation_material.set_shader_parameter(MAX_ALBEDO_PARAM, _max_albedo)
	validation_material.set_shader_parameter(IN_RANGE_MODE_PARAM, _in_range_mode)
	validation_material.set_shader_parameter(UNDER_COLOR_PARAM, _under_color)
	validation_material.set_shader_parameter(OVER_COLOR_PARAM, _over_color)
	validation_material.set_shader_parameter(IN_RANGE_COLOR_PARAM, _in_range_color)
	validation_material.set_shader_parameter(FALLOFF_PARAM, _falloff)
	validation_material.set_shader_parameter(HARD_EDGES_PARAM, _use_hard_edges)
	# Roughness Params
	validation_material.set_shader_parameter(HIGHLIGHT_ROUGHNESS_EXTREMES_PARAM, _highlight_roughness_extremes)
	validation_material.set_shader_parameter(ROUGHNESS_EXTREME_COLOR_PARAM, _roughness_extreme_color)

	if original_material:
		if "albedo_color" in original_material:
			validation_material.set_shader_parameter(ALBEDO_SOLID_COLOR_PARAM, original_material.albedo_color)
		if "albedo_texture" in original_material:
			validation_material.set_shader_parameter(ALBEDO_TEXTURE_PARAM, original_material.albedo_texture)

		var final_roughness_texture: Texture2D = null
		var final_metallic_texture: Texture2D = null

		if "texture_orm" in original_material and original_material.texture_orm != null:
			final_roughness_texture = original_material.texture_orm
			final_metallic_texture = original_material.texture_orm
		else:
			if "roughness_texture" in original_material:
				final_roughness_texture = original_material.roughness_texture
			if "metallic_texture" in original_material:
				final_metallic_texture = original_material.metallic_texture
		
		validation_material.set_shader_parameter(ROUGHNESS_TEXTURE_PARAM, final_roughness_texture)
		validation_material.set_shader_parameter(METALLIC_TEXTURE_PARAM, final_metallic_texture)
		
		if "roughness" in original_material:
			validation_material.set_shader_parameter(ROUGHNESS_VALUE_PARAM, original_material.roughness)
		if "metallic" in original_material:
			validation_material.set_shader_parameter(METALLIC_VALUE_PARAM, original_material.metallic)

		var is_triplanar: bool = false
		if "uv1_triplanar" in original_material: is_triplanar = original_material.uv1_triplanar
		validation_material.set_shader_parameter(USE_TRIPLANAR_PARAM, is_triplanar)
		if is_triplanar:
			if "uv1_scale" in original_material: validation_material.set_shader_parameter(TRIPLANAR_SCALE_PARAM, original_material.uv1_scale)
			if "uv1_triplanar_sharpness" in original_material: validation_material.set_shader_parameter(TRIPLANAR_SHARPNESS_PARAM, original_material.uv1_triplanar_sharpness)
	else:
		# Apply default parameters if there is no original material.
		validation_material.set_shader_parameter(ALBEDO_SOLID_COLOR_PARAM, Color.WHITE)
		validation_material.set_shader_parameter(ALBEDO_TEXTURE_PARAM, null)
		validation_material.set_shader_parameter(USE_TRIPLANAR_PARAM, false)
		validation_material.set_shader_parameter(ROUGHNESS_TEXTURE_PARAM, null)
		validation_material.set_shader_parameter(METALLIC_TEXTURE_PARAM, null)
		validation_material.set_shader_parameter(ROUGHNESS_VALUE_PARAM, 1.0)
		validation_material.set_shader_parameter(METALLIC_VALUE_PARAM, 0.0)


# --- Utility Functions ---

# Recursively finds all MeshInstance3D and CSGPrimitive3D nodes from a given start node.
func _find_renderable_nodes_recursively(node: Node, node_array: Array[Node]) -> void:
	if not is_inside_tree():
		return

	var edited_scene_root: Node = get_tree().edited_scene_root
	if not edited_scene_root:
		return

	if node is MeshInstance3D or node is CSGPrimitive3D:
		# Don't add nodes that are not part of the main edited scene (i.e. plugin UI)
		if edited_scene_root.is_ancestor_of(node) or node == edited_scene_root:
			node_array.append(node)
	
	for child: Node in node.get_children():
		_find_renderable_nodes_recursively(child, node_array)


# Recursively finds the first WorldEnvironment node.
func _find_world_environment_recursively(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node
	
	for child: Node in node.get_children():
		var found_node: WorldEnvironment = _find_world_environment_recursively(child)
		if found_node:
			return found_node
	
	return null
