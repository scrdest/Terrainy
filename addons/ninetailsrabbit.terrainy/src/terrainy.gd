@tool
extends Node

@export var button_Generate_Terrain: String
@export_category("Terrain")
## More resolution means more detail (more dense vertex) in the terrain generation, this increases the mesh subdivisions it could reduce the performance in low-spec pcs
@export_range(1, 16, 1) var mesh_resolution: int = 1:
	set(value):
		if value != mesh_resolution:
			mesh_resolution = value
			
			generate_terrain()
## The depth size of the mesh (z) in godot units (meters)
@export var size_depth: int = 100:
	set(value):
		if value != size_depth:
			size_depth = max(1, value)
			
			generate_terrain()
			
## The width size of the mesh (x) in godot units (meters)
@export var size_width: int = 100:
	set(value):
		if value != size_width:
			size_width = max(1, value)
			
			generate_terrain()
## The maximum height this terrain can have
@export var max_terrain_height: float = 50.0:
	set(value):
		if value != max_terrain_height:
			max_terrain_height = maxf(0.5, value)
			generate_terrain()
## The target MeshInstance3D where the mesh will be generated. If no Mesh is defined, a new PlaneMesh is created instead.
@export var target_mesh: MeshInstance3D:
	set(value):
		if value != target_mesh:
			target_mesh = value
			update_configuration_warnings()
## The terrain material that will be applied on the surface
@export var terrain_material: Material

@export_category("Water")
@export var water_material: Material = preload("res://addons/ninetailsrabbit.terrainy/assets/water/simple/simple_water.tres")
@export var water_mesh: MeshInstance3D:
	set(value):
		if value != water_mesh:
			water_mesh = value
## If the underwater mesh is not defined it will create a duplicated of the water mesh with flip faces
@export var underwater_mesh: MeshInstance3D:
	set(value):
		if value != underwater_mesh:
			underwater_mesh = value
## The water level percent about the lowest point of this terrain
@export_range(0, 1.0, 0.01) var water_level: float = 0.2
## The size of the water will be the terrain size + this value to create oceans
@export var water_size_width_extension: float = 1.0
## The size of the water will be the terrain size + this value to create oceans
@export var water_size_depth_extension: float = 1.0
@export var water_scale: Vector3 = Vector3.ONE
@export_category("Noise")
@export var randomize_noise_seed: bool = false
## Noise values are perfect to generate a variety of surfaces, higher frequencies tend to generate more mountainous terrain.
## Rocky: +Octaves -Period, Hills: -Octaves +Period
@export var noise: FastNoiseLite:
	set(value):
		if value != noise:
			noise = value
			update_configuration_warnings()
## Use a texture as noise to generate the terrain. If a noise is defined, this texture will be ignored.
@export var noise_texture: CompressedTexture2D:
	set(value):
		if value != noise_texture:
			noise_texture = value
			update_configuration_warnings()
@export var elevation_curve: Curve
## Use an image to smooth the edges on this terrain. Useful if you want to connect other plots of land
@export var falloff_texture: CompressedTexture2D = preload("res://addons/ninetailsrabbit.terrainy/assets/falloff_images/TerrainFalloff.png"):
	set(new_texture):
		if new_texture != falloff_texture:
			falloff_texture = new_texture
			
			if falloff_texture:
				falloff_image = falloff_texture.get_image()
			else:
				falloff_image = null
				
			generate_terrain()
@export_category("Navigation region")
@export var nav_source_group_name: StringName = &"terrain_navigation_source"
## This navigation needs to set the value Source Geometry -> Group Explicit
@export var navigation_region: NavigationRegion3D
## This will create a NavigationRegion3D automatically with the correct parameters
@export var create_navigation_region_in_runtime: bool = false
@export var bake_navigation_region_in_runtime: bool = false


var falloff_image: Image


func _get_configuration_warnings():
	var warnings: PackedStringArray = []
	
	if target_mesh == null:
		warnings.append("No target mesh found. Expected a MeshInstance3D")
	
	if noise == null and noise_texture == null:
		warnings.append("No noise found. Expected a FastNoiseLite or a Texture2D that represents a grayscale noise")
		
	return warnings
	

func _ready() -> void:
	if falloff_texture:
		falloff_image = falloff_texture.get_image()
		
	generate_terrain()


func generate_terrain(selected_mesh: MeshInstance3D = target_mesh) -> void:
	if selected_mesh == null:
		push_warning("Terrainy: This node needs a selected_mesh to create the terrain, aborting generation...")
		return
	
	if noise == null and noise_texture == null:
		push_warning("Terrainy: This node needs a noise value or noise texture to create the terrain, aborting generation...")
		return
		
	_set_owner_to_edited_scene_root(selected_mesh)
	
	if selected_mesh.mesh is PlaneMesh:
		set_terrain_size_on_plane_mesh(selected_mesh.mesh)
	elif selected_mesh.mesh is QuadMesh:
		set_terrain_size_on_plane_mesh(selected_mesh.mesh)
	elif  selected_mesh.mesh is BoxMesh:
		set_terrain_size_on_box_mesh(selected_mesh.mesh)
	elif selected_mesh.mesh is PrismMesh:
		set_terrain_size_on_prism_mesh(selected_mesh.mesh)
	elif selected_mesh.mesh is ArrayMesh:
		selected_mesh.mesh = null
	
	if selected_mesh.mesh == null:
		var plane_mesh = PlaneMesh.new()
		set_terrain_size_on_plane_mesh(plane_mesh)
		selected_mesh.mesh = plane_mesh
	
	_free_children(selected_mesh)
	create_surface(selected_mesh)
	create_water(water_mesh, underwater_mesh)
	create_navigation_region(navigation_region)


func create_navigation_region(selected_navigation_region: NavigationRegion3D = navigation_region) -> void:
	if selected_navigation_region == null and create_navigation_region_in_runtime:
		selected_navigation_region = NavigationRegion3D.new()
		selected_navigation_region.navigation_mesh = NavigationMesh.new()
		add_child(selected_navigation_region)
		_set_owner_to_edited_scene_root(selected_navigation_region)
	
	if selected_navigation_region:
		selected_navigation_region.navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_BOTH
		selected_navigation_region.navigation_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_EXPLICIT
		selected_navigation_region.navigation_mesh.geometry_source_group_name = nav_source_group_name
		
		if bake_navigation_region_in_runtime:
			selected_navigation_region.navigation_mesh.clear()
			selected_navigation_region.bake_navigation_mesh()
			await selected_navigation_region.bake_finished
	
	navigation_region = selected_navigation_region


func create_water(selected_water_mesh: MeshInstance3D, selected_underwater_mesh: MeshInstance3D) -> void:
	if selected_water_mesh:
		if water_material and selected_water_mesh.get_surface_override_material(0) == null:
			selected_water_mesh.set_surface_override_material(0, water_material)
			
		selected_water_mesh.mesh.flip_faces = false
		selected_water_mesh.global_position = target_mesh.global_position
		selected_water_mesh.global_position.y = water_level * max_terrain_height
		selected_water_mesh.mesh.size.x = size_width + water_size_width_extension
		selected_water_mesh.mesh.size.y = size_depth + water_size_depth_extension
		selected_water_mesh.scale = water_scale
		#selected_water_mesh.mesh.subdivide_width = size_width * mesh_resolution
		#selected_water_mesh.mesh.subdivide_depth = size_depth * mesh_resolution
		_set_owner_to_edited_scene_root(selected_water_mesh)
		
		if selected_underwater_mesh == null:
			selected_underwater_mesh = MeshInstance3D.new()
			selected_underwater_mesh.mesh = PlaneMesh.new()
			selected_underwater_mesh.set_surface_override_material(0, selected_water_mesh.get_surface_override_material(0).duplicate())
			
			selected_water_mesh.add_child(selected_underwater_mesh)
		
		selected_underwater_mesh.mesh.flip_faces = true
		selected_underwater_mesh.global_position = selected_water_mesh.global_position
		selected_underwater_mesh.mesh.size.x = selected_water_mesh.mesh.size.x
		selected_underwater_mesh.mesh.size.y =  selected_water_mesh.mesh.size.y
		selected_underwater_mesh.scale = selected_water_mesh.scale
		#selected_underwater_mesh.mesh.subdivide_width = selected_water_mesh.mesh.subdivide_width
		#selected_underwater_mesh.mesh.subdivide_depth = selected_water_mesh.mesh.subdivide_depth
		_set_owner_to_edited_scene_root(selected_underwater_mesh)
	

func create_surface(mesh_instance: MeshInstance3D = target_mesh) -> void:
	var surface = SurfaceTool.new()
	var mesh_data_tool = MeshDataTool.new()
	
	surface.create_from(mesh_instance.mesh, 0)

	var array_mesh = surface.commit()
	mesh_data_tool.create_from_surface(array_mesh, 0)

	if noise is FastNoiseLite and noise_texture == null:
		if randomize_noise_seed:
			noise.seed = randi()
			
		generate_heightmap_with_noise(noise, mesh_data_tool)
	elif noise == null and noise_texture is CompressedTexture2D:
		generate_heightmap_with_noise_texture(noise_texture, mesh_data_tool)
		
	array_mesh.clear_surfaces()
	mesh_data_tool.commit_to_surface(array_mesh)
	
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.create_from(array_mesh, 0)
	surface.generate_normals()

	mesh_instance.mesh = surface.commit()
	mesh_instance.create_trimesh_collision()
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.add_to_group(nav_source_group_name)


func generate_heightmap_with_noise(selected_noise: FastNoiseLite, mesh_data_tool: MeshDataTool) -> void:
	for vertex_idx: int in mesh_data_tool.get_vertex_count():
		var vertex: Vector3 = mesh_data_tool.get_vertex(vertex_idx)
		## Convert to a range of 0 ~ 1 instead of -1 ~ 1
		var noise_y: float = get_noise_y(selected_noise, vertex)
		noise_y = apply_elevation_curve(noise_y)
		var falloff = calculate_falloff(vertex)
		
		vertex.y = noise_y * max_terrain_height * falloff
		
		mesh_data_tool.set_vertex(vertex_idx, vertex)


func get_noise_y(selected_noise: FastNoiseLite, vertex: Vector3) -> float:
	return (selected_noise.get_noise_2d(vertex.x, vertex.z) + 1) / 2
	
	
func generate_heightmap_with_noise_texture(selected_texture: CompressedTexture2D, mesh_data_tool: MeshDataTool) -> void:
	var noise_image: Image = selected_texture.get_image()
	var width: int = noise_image.get_width()
	var height: int = noise_image.get_height()
	
	for vertex_idx: int in mesh_data_tool.get_vertex_count():
		var vertex: Vector3 = mesh_data_tool.get_vertex(vertex_idx)
		## This operation is needed to avoid being generated symmetrically only using positive values and avoid errors when obtaining the pixel from the image
		var x = vertex.x if vertex.x > 0 else width - absf(vertex.x)
		var z = vertex.z if vertex.z > 0 else height - absf(vertex.z)
		
		vertex.y = noise_image.get_pixel(x, z).r
		vertex.y = apply_elevation_curve(vertex.y)
		
		var falloff = calculate_falloff(vertex)
		
		vertex.y *= max_terrain_height * falloff
		
		mesh_data_tool.set_vertex(vertex_idx, vertex)


func calculate_falloff(vertex: Vector3) -> float:
	var falloff: float = 1.0
	
	if falloff_image:
		var x_percent: float = (vertex.x + (size_width / 2)) / size_width
		var z_percent: float = (vertex.z + (size_depth / 2)) / size_depth
		var x_pixel: int = int(x_percent * falloff_image.get_width())
		var y_pixel: int = int(z_percent * falloff_image.get_height())
		
		# In this case we can go for any channel (r,g b) as the colors are the same
		falloff = falloff_image.get_pixel(x_pixel, y_pixel).r
		
	return falloff
	

func apply_elevation_curve(noise_y: float) -> float:
	if elevation_curve:
		noise_y = elevation_curve.sample(noise_y)
		
	return noise_y


func set_terrain_size_on_plane_mesh(plane_mesh: PlaneMesh) -> void:
	plane_mesh.size = Vector2(size_width, size_depth)
	plane_mesh.subdivide_depth = size_depth * mesh_resolution
	plane_mesh.subdivide_width = size_width * mesh_resolution
	plane_mesh.material = terrain_material
	

func set_terrain_size_on_box_mesh(box_mesh: BoxMesh) -> void:
	box_mesh.size = Vector3(size_width, box_mesh.size.y, size_depth)
	box_mesh.subdivide_depth = size_depth * mesh_resolution
	box_mesh.subdivide_width = size_width * mesh_resolution
	box_mesh.material = terrain_material


func set_terrain_size_on_prism_mesh(prism_mesh: PrismMesh) -> void:
	prism_mesh.size = Vector3(size_width, prism_mesh.size.y, size_depth)
	prism_mesh.subdivide_depth = size_depth * mesh_resolution
	prism_mesh.subdivide_width = size_width * mesh_resolution
	prism_mesh.material = terrain_material

#region Helpers
func _set_owner_to_edited_scene_root(node: Node) -> void:
	if Engine.is_editor_hint() and node.get_tree():
		node.owner = node.get_tree().edited_scene_root


func _free_children(node: Node) -> void:
	if node.get_child_count() == 0:
		return

	var childrens = node.get_children()
	childrens.reverse()
	
	for child in childrens.filter(func(_node: Node): return is_instance_valid(node)):
		child.free()


func _on_tool_button_pressed(text: String) -> void:
	match text:
		"Generate Terrain":
			generate_terrain()

#endregion
