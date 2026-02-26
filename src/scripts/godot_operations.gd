#!/usr/bin/env -S godot --headless --script
extends SceneTree

# Debug mode flag
var debug_mode = false
var pending_operation = ""
var pending_params = {}

func _initialize():
    var args = OS.get_cmdline_args()
    
    # Check for debug flag
    debug_mode = "--debug-godot" in args
    
    # Find the script argument and determine the positions of operation and params
    var script_index = args.find("--script")
    if script_index == -1:
        log_error("Could not find --script argument")
        quit(1)
    
    # The operation should be 2 positions after the script path (script_index + 1 is the script path itself)
    var operation_index = script_index + 2
    # The params should be 3 positions after the script path
    var params_index = script_index + 3
    
    if args.size() <= params_index:
        log_error("Usage: godot --headless --script godot_operations.gd <operation> <json_params>")
        log_error("Not enough command-line arguments provided.")
        quit(1)
    
    # Log all arguments for debugging
    log_debug("All arguments: " + str(args))
    log_debug("Script index: " + str(script_index))
    log_debug("Operation index: " + str(operation_index))
    log_debug("Params index: " + str(params_index))
    
    pending_operation = args[operation_index]
    var params_json = args[params_index]
    
    log_info("Operation: " + pending_operation)
    log_debug("Params JSON: " + params_json)
    
    # Parse JSON using Godot 4.x API
    var json = JSON.new()
    var error = json.parse(params_json)
    var params = null
    
    if error == OK:
        params = json.get_data()
    else:
        log_error("Failed to parse JSON parameters: " + params_json)
        log_error("JSON Error: " + json.get_error_message() + " at line " + str(json.get_error_line()))
        quit(1)
    
    if not params:
        log_error("Failed to parse JSON parameters: " + params_json)
        quit(1)
    pending_params = params

    log_info("Executing operation: " + pending_operation)
    call_deferred("_run_pending_operation")

func _run_pending_operation():
    await execute_operation(pending_operation, pending_params)
    quit()

# Logging functions
func log_debug(message):
    if debug_mode:
        print("[DEBUG] " + message)

func log_info(message):
    print("[INFO] " + message)

func log_error(message):
    printerr("[ERROR] " + message)

func execute_operation(operation, params):
    match operation:
        "create_scene":
            create_scene(params)
        "add_node":
            add_node(params)
        "create_script":
            create_script(params)
        "attach_script":
            attach_script(params)
        "render_scene_snapshot":
            await render_scene_snapshot(params)
        "dump_ui_layout":
            await dump_ui_layout(params)
        "load_sprite":
            load_sprite(params)
        "export_mesh_library":
            export_mesh_library(params)
        "save_scene":
            save_scene(params)
        "get_uid":
            get_uid(params)
        "resave_resources":
            resave_resources(params)
        _:
            log_error("Unknown operation: " + operation)
            quit(1)

func wait_for_frames(frame_count):
    var count = max(frame_count, 1)
    for i in range(count):
        await process_frame

# Get a script by name or path
func get_script_by_name(name_of_class):
    if debug_mode:
        print("Attempting to get script for class: " + name_of_class)
    
    # Try to load it directly if it's a resource path
    if ResourceLoader.exists(name_of_class, "Script"):
        if debug_mode:
            print("Resource exists, loading directly: " + name_of_class)
        var script = load(name_of_class) as Script
        if script:
            if debug_mode:
                print("Successfully loaded script from path")
            return script
        else:
            printerr("Failed to load script from path: " + name_of_class)
    elif debug_mode:
        print("Resource not found, checking global class registry")
    
    # Search for it in the global class registry if it's a class name
    var global_classes = ProjectSettings.get_global_class_list()
    if debug_mode:
        print("Searching through " + str(global_classes.size()) + " global classes")
    
    for global_class in global_classes:
        var found_name_of_class = global_class["class"]
        var found_path = global_class["path"]
        
        if found_name_of_class == name_of_class:
            if debug_mode:
                print("Found matching class in registry: " + found_name_of_class + " at path: " + found_path)
            var script = load(found_path) as Script
            if script:
                if debug_mode:
                    print("Successfully loaded script from registry")
                return script
            else:
                printerr("Failed to load script from registry path: " + found_path)
                break
    
    printerr("Could not find script for class: " + name_of_class)
    return null

# Instantiate a class by name
func instantiate_class(name_of_class):
    if name_of_class.is_empty():
        printerr("Cannot instantiate class: name is empty")
        return null
    
    var result = null
    if debug_mode:
        print("Attempting to instantiate class: " + name_of_class)
    
    # Check if it's a built-in class
    if ClassDB.class_exists(name_of_class):
        if debug_mode:
            print("Class exists in ClassDB, using ClassDB.instantiate()")
        if ClassDB.can_instantiate(name_of_class):
            result = ClassDB.instantiate(name_of_class)
            if result == null:
                printerr("ClassDB.instantiate() returned null for class: " + name_of_class)
        else:
            printerr("Class exists but cannot be instantiated: " + name_of_class)
            printerr("This may be an abstract class or interface that cannot be directly instantiated")
    else:
        # Try to get the script
        if debug_mode:
            print("Class not found in ClassDB, trying to get script")
        var script = get_script_by_name(name_of_class)
        if script is Script:
            if script.can_instantiate():
                if debug_mode:
                    print("Found Script, creating instance")
                result = script.new()
            else:
                printerr("Script cannot be instantiated: " + name_of_class)
                return null
        else:
            printerr("Failed to get script for class: " + name_of_class)
            return null
    
    if result == null:
        printerr("Failed to instantiate class: " + name_of_class)
    elif debug_mode:
        print("Successfully instantiated class: " + name_of_class + " of type: " + result.get_class())
    
    return result

func normalize_res_path(path_value):
    var normalized_path = str(path_value).strip_edges()
    if normalized_path.is_empty():
        return normalized_path
    if normalized_path.begins_with("res://"):
        return normalized_path
    return "res://" + normalized_path

func join_paths(base_path, file_name):
    var separator = "/"
    if base_path.find("\\") != -1:
        separator = "\\"

    if base_path.ends_with("/") or base_path.ends_with("\\"):
        return base_path + file_name
    return base_path + separator + file_name

func ensure_res_directory_exists(res_file_path):
    var res_dir = res_file_path.get_base_dir()
    if res_dir == "res://" or res_dir.is_empty():
        return OK

    var relative_dir = res_dir.substr(6) # remove "res://"
    var dir = DirAccess.open("res://")
    if dir == null:
        return DirAccess.get_open_error()
    return dir.make_dir_recursive(relative_dir)

func sanitize_identifier(raw_value, fallback):
    var source = str(raw_value).strip_edges()
    if source.is_empty():
        source = fallback

    var out = ""
    for i in range(source.length()):
        var c = source[i]
        var code = source.unicode_at(i)
        var is_alpha = (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
        var is_digit = code >= 48 and code <= 57
        var is_underscore = c == "_"
        if is_alpha or is_digit or is_underscore:
            out += c
        else:
            out += "_"

    if out.is_empty():
        out = fallback

    var first_code = out.unicode_at(0)
    var starts_with_digit = first_code >= 48 and first_code <= 57
    if starts_with_digit:
        out = "_" + out

    return out

func sanitize_namespace(raw_value, fallback):
    var source = str(raw_value).strip_edges()
    if source.is_empty():
        source = fallback

    var chunks = source.split(".")
    var sanitized_chunks = []
    for chunk in chunks:
        var safe_chunk = sanitize_identifier(chunk, fallback)
        if not safe_chunk.is_empty():
            sanitized_chunks.append(safe_chunk)

    if sanitized_chunks.is_empty():
        return sanitize_identifier(fallback, "GodotMcp")

    return ".".join(sanitized_chunks)

func get_snapshot_root_absolute():
    return join_paths(ProjectSettings.globalize_path("res://"), ".mcp_snapshots")

func get_snapshot_output_dir(params):
    var output_dir = ""
    if params.has("output_dir"):
        output_dir = str(params.output_dir).strip_edges()
    if output_dir.is_empty():
        output_dir = get_snapshot_root_absolute()
    return output_dir

func ensure_absolute_directory_exists(absolute_dir):
    if absolute_dir.is_empty():
        return ERR_INVALID_PARAMETER
    if DirAccess.dir_exists_absolute(absolute_dir):
        return OK
    return DirAccess.make_dir_recursive_absolute(absolute_dir)

func timestamp_slug():
    var dt = Time.get_datetime_dict_from_system()
    return "%04d%02d%02d-%02d%02d%02d" % [
        int(dt.year), int(dt.month), int(dt.day),
        int(dt.hour), int(dt.minute), int(dt.second)
    ]

func scene_slug(scene_path):
    var normalized = normalize_res_path(scene_path)
    var file_name = normalized.get_file().get_basename()
    return sanitize_identifier(file_name, "scene")

func bool_param(params, key, default_value):
    if params.has(key):
        return bool(params[key])
    return default_value

func int_param(params, key, default_value):
    if params.has(key):
        return int(params[key])
    return default_value

func collect_control_layout(control_root):
    var controls = []
    var pending = [control_root]
    while pending.size() > 0:
        var current = pending.pop_back()
        if current is Control:
            var ctrl = current as Control
            var global_rect = ctrl.get_global_rect()
            var rel_path = str(control_root.get_path_to(ctrl))
            var path_value = "root"
            if not rel_path.is_empty():
                path_value = "root/" + rel_path
            controls.append({
                "path": path_value,
                "name": ctrl.name,
                "class": ctrl.get_class(),
                "global_rect": {
                    "x": global_rect.position.x,
                    "y": global_rect.position.y,
                    "width": global_rect.size.x,
                    "height": global_rect.size.y
                },
                "anchors": {
                    "left": ctrl.anchor_left,
                    "top": ctrl.anchor_top,
                    "right": ctrl.anchor_right,
                    "bottom": ctrl.anchor_bottom
                },
                "offsets": {
                    "left": ctrl.offset_left,
                    "top": ctrl.offset_top,
                    "right": ctrl.offset_right,
                    "bottom": ctrl.offset_bottom
                },
                "size_flags_horizontal": ctrl.size_flags_horizontal,
                "size_flags_vertical": ctrl.size_flags_vertical,
                "custom_minimum_size": {
                    "x": ctrl.custom_minimum_size.x,
                    "y": ctrl.custom_minimum_size.y
                },
                "visible": ctrl.visible,
                "modulate": {
                    "r": ctrl.modulate.r,
                    "g": ctrl.modulate.g,
                    "b": ctrl.modulate.b,
                    "a": ctrl.modulate.a
                }
            })

        for child in current.get_children():
            if child is Node:
                pending.append(child)

    return controls

func build_layout_result(scene_root, width, height):
    var controls = collect_control_layout(scene_root)
    return {
        "timestamp": timestamp_slug(),
        "viewport": {
            "width": width,
            "height": height
        },
        "node_count": controls.size(),
        "controls": controls
    }

func setup_viewport_for_scene(scene_root, width, height):
    var viewport = SubViewport.new()
    viewport.disable_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    viewport.size = Vector2i(width, height)

    get_root().add_child(viewport)

    var host = Node2D.new()
    host.name = "SnapshotHost"
    viewport.add_child(host)
    host.add_child(scene_root)

    if scene_root is Control:
        var root_control = scene_root as Control
        root_control.visible = true
        root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
        root_control.offset_left = 0
        root_control.offset_top = 0
        root_control.offset_right = 0
        root_control.offset_bottom = 0
        root_control.size = Vector2(width, height)

    return viewport

func clear_node_scripts(node):
    if node is Node:
        if node.get_script() != null:
            node.set_script(null)
        for child in node.get_children():
            clear_node_scripts(child)

func normalize_scene_path_or_fail(params):
    if not params.has("scene_path"):
        printerr("scene_path is required")
        quit(1)
    var full_scene_path = normalize_res_path(params.scene_path)
    if not FileAccess.file_exists(full_scene_path):
        printerr("Scene file does not exist: " + full_scene_path)
        quit(1)
    return full_scene_path

func prepare_snapshot_paths(params, width, height):
    var output_dir_abs = get_snapshot_output_dir(params)
    var ensure_error = ensure_absolute_directory_exists(output_dir_abs)
    if ensure_error != OK:
        printerr("Failed to create snapshot directory: " + output_dir_abs)
        printerr("Error code: " + str(ensure_error))
        quit(1)

    var slug = scene_slug(params.scene_path)
    var stamp = timestamp_slug()
    var base_name = "%s_%dx%d_%s" % [slug, width, height, stamp]
    return {
        "output_dir_abs": output_dir_abs,
        "png_path_abs": join_paths(output_dir_abs, base_name + ".png"),
        "json_path_abs": join_paths(output_dir_abs, base_name + ".layout.json")
    }

func write_json_file(absolute_path, data):
    var file = FileAccess.open(absolute_path, FileAccess.WRITE)
    if file == null:
        return FileAccess.get_open_error()
    file.store_string(JSON.stringify(data, "  "))
    file.close()
    return OK

func extract_overlay_rects(layout_data):
    var overlay_rects = []
    for control_data in layout_data.controls:
        overlay_rects.append(control_data.global_rect)
    return overlay_rects

func render_scene_snapshot(params):
    var width = int_param(params, "width", 1920)
    var height = int_param(params, "height", 1080)
    var wait_frames = int_param(params, "wait_frames", 3)
    var overlay = bool_param(params, "overlay", true)
    var dump_layout = bool_param(params, "dump_layout", true)

    if width <= 0 or height <= 0:
        printerr("width and height must be positive")
        quit(1)
    if wait_frames < 0:
        wait_frames = 0

    var full_scene_path = normalize_scene_path_or_fail(params)
    var packed_scene = load(full_scene_path) as PackedScene
    if packed_scene == null:
        printerr("Failed to load scene as PackedScene: " + full_scene_path)
        quit(1)

    var scene_root = packed_scene.instantiate()
    if scene_root == null:
        printerr("Failed to instantiate scene: " + full_scene_path)
        quit(1)
    var strip_scripts = bool_param(params, "strip_scripts", false)
    if strip_scripts:
        clear_node_scripts(scene_root)

    var path_info = prepare_snapshot_paths(params, width, height)
    var viewport = setup_viewport_for_scene(scene_root, width, height)
    var layout_data = build_layout_result(scene_root, width, height)
    var warnings = []

    if overlay:
        var overlay_container = Control.new()
        overlay_container.name = "SnapshotOverlay"
        overlay_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
        overlay_container.set_anchors_preset(Control.PRESET_FULL_RECT)
        overlay_container.offset_left = 0
        overlay_container.offset_top = 0
        overlay_container.offset_right = 0
        overlay_container.offset_bottom = 0
        scene_root.add_child(overlay_container)
        overlay_container.owner = scene_root

        for rect_data in extract_overlay_rects(layout_data):
            var reference_rect = ReferenceRect.new()
            reference_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
            reference_rect.position = Vector2(rect_data["x"], rect_data["y"])
            reference_rect.size = Vector2(rect_data["width"], rect_data["height"])
            reference_rect.border_color = Color(1.0, 0.2, 0.2, 1.0)
            reference_rect.border_width = 2.0
            overlay_container.add_child(reference_rect)
            reference_rect.owner = scene_root

    await wait_for_frames(wait_frames + 2)

    var image = viewport.get_texture().get_image()
    if image == null:
        printerr("Failed to capture viewport image")
        quit(1)

    var png_error = image.save_png(path_info.png_path_abs)
    if png_error != OK:
        printerr("Failed to save PNG: " + path_info.png_path_abs)
        printerr("Error code: " + str(png_error))
        quit(1)

    var json_path_abs = null
    if dump_layout:
        json_path_abs = path_info.json_path_abs
        var write_error = write_json_file(json_path_abs, layout_data)
        if write_error != OK:
            warnings.append("Failed to write layout JSON. Error code: " + str(write_error))
            json_path_abs = null

    var result = {
        "ok": true,
        "pngPath": path_info.png_path_abs,
        "jsonPath": json_path_abs,
        "width": width,
        "height": height,
        "overlayUsed": overlay,
        "nodeCount": int(layout_data.node_count),
        "warnings": warnings
    }

    print(JSON.stringify(result))

    viewport.queue_free()

func dump_ui_layout(params):
    var width = int_param(params, "width", 1920)
    var height = int_param(params, "height", 1080)
    var wait_frames = int_param(params, "wait_frames", 1)
    if width <= 0 or height <= 0:
        printerr("width and height must be positive")
        quit(1)
    if wait_frames < 0:
        wait_frames = 0

    var full_scene_path = normalize_scene_path_or_fail(params)
    var packed_scene = load(full_scene_path) as PackedScene
    if packed_scene == null:
        printerr("Failed to load scene as PackedScene: " + full_scene_path)
        quit(1)

    var scene_root = packed_scene.instantiate()
    if scene_root == null:
        printerr("Failed to instantiate scene: " + full_scene_path)
        quit(1)
    var strip_scripts = bool_param(params, "strip_scripts", false)
    if strip_scripts:
        clear_node_scripts(scene_root)

    var path_info = prepare_snapshot_paths(params, width, height)
    var viewport = setup_viewport_for_scene(scene_root, width, height)

    await wait_for_frames(wait_frames + 1)

    var layout_data = build_layout_result(scene_root, width, height)
    var write_error = write_json_file(path_info.json_path_abs, layout_data)
    if write_error != OK:
        printerr("Failed to write layout JSON: " + path_info.json_path_abs)
        printerr("Error code: " + str(write_error))
        quit(1)

    var result = {
        "ok": true,
        "jsonPath": path_info.json_path_abs,
        "nodeCount": int(layout_data.node_count)
    }
    print(JSON.stringify(result))

    viewport.queue_free()

func create_script(params):
    if not params.has("script_path"):
        printerr("script_path is required")
        quit(1)

    var language = "csharp"
    if params.has("language"):
        language = str(params.language).to_lower().strip_edges()
    if language.is_empty():
        language = "csharp"

    var full_script_path = normalize_res_path(params.script_path)
    if full_script_path.is_empty():
        printerr("script_path cannot be empty")
        quit(1)

    var overwrite = false
    if params.has("overwrite"):
        overwrite = bool(params.overwrite)

    if FileAccess.file_exists(full_script_path) and not overwrite:
        printerr("Script already exists and overwrite is false: " + full_script_path)
        quit(1)

    var dir_error = ensure_res_directory_exists(full_script_path)
    if dir_error != OK:
        printerr("Failed to create script directory for path: " + full_script_path)
        printerr("Error code: " + str(dir_error))
        quit(1)

    var file_name = full_script_path.get_file()
    var inferred_class_name = file_name.get_basename()
    var script_name_token = inferred_class_name
    if params.has("class_name"):
        script_name_token = str(params.class_name)
    script_name_token = sanitize_identifier(script_name_token, "GeneratedScript")

    var base_type = "Node"
    if params.has("base_type"):
        base_type = str(params.base_type).strip_edges()
    if base_type.is_empty():
        base_type = "Node"

    var script_contents = ""
    if language == "csharp":
        if not ClassDB.class_exists("CSharpScript"):
            printerr("C# scripting is not available in this Godot build. Use a Mono/.NET-enabled Godot build.")
            quit(1)

        var namespace_value = ""
        if params.has("namespace"):
            namespace_value = str(params.namespace)
        if namespace_value.is_empty():
            namespace_value = str(ProjectSettings.get_setting("application/config/name", "GodotMcp"))
        namespace_value = sanitize_namespace(namespace_value, "GodotMcp")

        var attribute_lines = ""
        if params.has("tool") and bool(params.tool):
            attribute_lines += "    [Tool]\n"
        if params.has("global_class") and bool(params.global_class):
            attribute_lines += "    [GlobalClass]\n"

        script_contents = "using Godot;\n"
        script_contents += "using System;\n\n"
        script_contents += "namespace " + namespace_value + "\n"
        script_contents += "{\n"
        script_contents += attribute_lines
        script_contents += "    public partial class " + script_name_token + " : " + base_type + "\n"
        script_contents += "    {\n"
        script_contents += "        public override void _Ready()\n"
        script_contents += "        {\n"
        script_contents += "        }\n"
        script_contents += "    }\n"
        script_contents += "}\n"
    elif language == "gdscript":
        script_contents = "extends " + base_type + "\n"
        script_contents += "class_name " + script_name_token + "\n\n"
        if params.has("tool") and bool(params.tool):
            script_contents = "@tool\n" + script_contents
        script_contents += "func _ready() -> void:\n"
        script_contents += "    pass\n"
    else:
        printerr("Unsupported script language: " + language + ". Use 'csharp' or 'gdscript'.")
        quit(1)

    var script_file = FileAccess.open(full_script_path, FileAccess.WRITE)
    if script_file == null:
        printerr("Failed to open script for writing: " + full_script_path)
        printerr("FileAccess error: " + str(FileAccess.get_open_error()))
        quit(1)

    script_file.store_string(script_contents)
    script_file.close()
    print("Script created successfully at: " + full_script_path)

func attach_script(params):
    if not params.has("scene_path") or not params.has("node_path") or not params.has("script_path"):
        printerr("scene_path, node_path, and script_path are required")
        quit(1)

    var full_scene_path = normalize_res_path(params.scene_path)
    var full_script_path = normalize_res_path(params.script_path)
    var node_path = str(params.node_path).strip_edges()
    var overwrite = true
    if params.has("overwrite"):
        overwrite = bool(params.overwrite)

    if not FileAccess.file_exists(full_scene_path):
        printerr("Scene file does not exist at: " + full_scene_path)
        quit(1)
    if not FileAccess.file_exists(full_script_path):
        printerr("Script file does not exist at: " + full_script_path)
        quit(1)

    var scene = load(full_scene_path)
    if scene == null:
        printerr("Failed to load scene: " + full_scene_path)
        quit(1)

    var scene_root = scene.instantiate()
    if scene_root == null:
        printerr("Failed to instantiate scene: " + full_scene_path)
        quit(1)

    var target = scene_root
    if node_path != "root":
        var stripped_path = node_path
        if stripped_path.begins_with("root/"):
            stripped_path = stripped_path.substr(5)
        target = scene_root.get_node(stripped_path)

    if target == null:
        printerr("Target node not found: " + node_path)
        quit(1)

    var script = load(full_script_path) as Script
    if script == null:
        printerr("Failed to load script resource: " + full_script_path)
        quit(1)

    if not overwrite and target.get_script() != null:
        printerr("Target node already has a script and overwrite is false")
        quit(1)

    target.set_script(script)

    var packed_scene = PackedScene.new()
    var pack_error = packed_scene.pack(scene_root)
    if pack_error != OK:
        printerr("Failed to pack scene: " + str(pack_error))
        quit(1)

    var save_error = ResourceSaver.save(packed_scene, full_scene_path)
    if save_error != OK:
        printerr("Failed to save scene after attaching script: " + str(save_error))
        quit(1)

    print("Script attached successfully: " + full_script_path + " -> " + node_path)

# Create a new scene with a specified root node type
func create_scene(params):
    print("Creating scene: " + params.scene_path)
    
    # Get project paths and log them for debugging
    var project_res_path = "res://"
    var project_user_path = "user://"
    var global_res_path = ProjectSettings.globalize_path(project_res_path)
    var global_user_path = ProjectSettings.globalize_path(project_user_path)
    
    if debug_mode:
        print("Project paths:")
        print("- res:// path: " + project_res_path)
        print("- user:// path: " + project_user_path)
        print("- Globalized res:// path: " + global_res_path)
        print("- Globalized user:// path: " + global_user_path)
        
        # Print some common environment variables for debugging
        print("Environment variables:")
        var env_vars = ["PATH", "HOME", "USER", "TEMP", "GODOT_PATH"]
        for env_var in env_vars:
            if OS.has_environment(env_var):
                print("  " + env_var + " = " + OS.get_environment(env_var))
    
    # Normalize the scene path
    var full_scene_path = params.scene_path
    if not full_scene_path.begins_with("res://"):
        full_scene_path = "res://" + full_scene_path
    if debug_mode:
        print("Scene path (with res://): " + full_scene_path)
    
    # Convert resource path to an absolute path
    var absolute_scene_path = ProjectSettings.globalize_path(full_scene_path)
    if debug_mode:
        print("Absolute scene path: " + absolute_scene_path)
    
    # Get the scene directory paths
    var scene_dir_res = full_scene_path.get_base_dir()
    var scene_dir_abs = absolute_scene_path.get_base_dir()
    if debug_mode:
        print("Scene directory (resource path): " + scene_dir_res)
        print("Scene directory (absolute path): " + scene_dir_abs)
    
    # Only do extensive testing in debug mode
    if debug_mode:
        # Try to create a simple test file in the project root to verify write access
        var initial_test_file_path = "res://godot_mcp_test_write.tmp"
        var initial_test_file = FileAccess.open(initial_test_file_path, FileAccess.WRITE)
        if initial_test_file:
            initial_test_file.store_string("Test write access")
            initial_test_file.close()
            print("Successfully wrote test file to project root: " + initial_test_file_path)
            
            # Verify the test file exists
            var initial_test_file_exists = FileAccess.file_exists(initial_test_file_path)
            print("Test file exists check: " + str(initial_test_file_exists))
            
            # Clean up the test file
            if initial_test_file_exists:
                var remove_error = DirAccess.remove_absolute(ProjectSettings.globalize_path(initial_test_file_path))
                print("Test file removal result: " + str(remove_error))
        else:
            var write_error = FileAccess.get_open_error()
            printerr("Failed to write test file to project root: " + str(write_error))
            printerr("This indicates a serious permission issue with the project directory")
    
    # Use traditional if-else statement for better compatibility
    var root_node_type = "Node2D"  # Default value
    if params.has("root_node_type"):
        root_node_type = params.root_node_type
    if debug_mode:
        print("Root node type: " + root_node_type)
    
    # Create the root node
    var scene_root = instantiate_class(root_node_type)
    if not scene_root:
        printerr("Failed to instantiate node of type: " + root_node_type)
        printerr("Make sure the class exists and can be instantiated")
        printerr("Check if the class is registered in ClassDB or available as a script")
        quit(1)
    
    scene_root.name = "root"
    if debug_mode:
        print("Root node created with name: " + scene_root.name)
    
    # Set the owner of the root node to itself (important for scene saving)
    scene_root.owner = scene_root
    
    # Pack the scene
    var packed_scene = PackedScene.new()
    var result = packed_scene.pack(scene_root)
    if debug_mode:
        print("Pack result: " + str(result) + " (OK=" + str(OK) + ")")
    
    if result == OK:
        # Only do extensive testing in debug mode
        if debug_mode:
            # First, let's verify we can write to the project directory
            print("Testing write access to project directory...")
            var test_write_path = "res://test_write_access.tmp"
            var test_write_abs = ProjectSettings.globalize_path(test_write_path)
            var test_file = FileAccess.open(test_write_path, FileAccess.WRITE)
            
            if test_file:
                test_file.store_string("Write test")
                test_file.close()
                print("Successfully wrote test file to project directory")
                
                # Clean up test file
                if FileAccess.file_exists(test_write_path):
                    var remove_error = DirAccess.remove_absolute(test_write_abs)
                    print("Test file removal result: " + str(remove_error))
            else:
                var write_error = FileAccess.get_open_error()
                printerr("Failed to write test file to project directory: " + str(write_error))
                printerr("This may indicate permission issues with the project directory")
                # Continue anyway, as the scene directory might still be writable
        
        # Ensure the scene directory exists using DirAccess
        if debug_mode:
            print("Ensuring scene directory exists...")
        
        # Get the scene directory relative to res://
        var scene_dir_relative = scene_dir_res.substr(6)  # Remove "res://" prefix
        if debug_mode:
            print("Scene directory (relative to res://): " + scene_dir_relative)
        
        # Create the directory if needed
        if not scene_dir_relative.is_empty():
            # First check if it exists
            var dir_exists = DirAccess.dir_exists_absolute(scene_dir_abs)
            if debug_mode:
                print("Directory exists check (absolute): " + str(dir_exists))
            
            if not dir_exists:
                if debug_mode:
                    print("Directory doesn't exist, creating: " + scene_dir_relative)
                
                # Try to create the directory using DirAccess
                var dir = DirAccess.open("res://")
                if dir == null:
                    var open_error = DirAccess.get_open_error()
                    printerr("Failed to open res:// directory: " + str(open_error))
                    
                    # Try alternative approach with absolute path
                    if debug_mode:
                        print("Trying alternative directory creation approach...")
                    var make_dir_error = DirAccess.make_dir_recursive_absolute(scene_dir_abs)
                    if debug_mode:
                        print("Make directory result (absolute): " + str(make_dir_error))
                    
                    if make_dir_error != OK:
                        printerr("Failed to create directory using absolute path")
                        printerr("Error code: " + str(make_dir_error))
                        quit(1)
                else:
                    # Create the directory using the DirAccess instance
                    if debug_mode:
                        print("Creating directory using DirAccess: " + scene_dir_relative)
                    var make_dir_error = dir.make_dir_recursive(scene_dir_relative)
                    if debug_mode:
                        print("Make directory result: " + str(make_dir_error))
                    
                    if make_dir_error != OK:
                        printerr("Failed to create directory: " + scene_dir_relative)
                        printerr("Error code: " + str(make_dir_error))
                        quit(1)
                
                # Verify the directory was created
                dir_exists = DirAccess.dir_exists_absolute(scene_dir_abs)
                if debug_mode:
                    print("Directory exists check after creation: " + str(dir_exists))
                
                if not dir_exists:
                    printerr("Directory reported as created but does not exist: " + scene_dir_abs)
                    printerr("This may indicate a problem with path resolution or permissions")
                    quit(1)
            elif debug_mode:
                print("Directory already exists: " + scene_dir_abs)
        
        # Save the scene
        if debug_mode:
            print("Saving scene to: " + full_scene_path)
        var save_error = ResourceSaver.save(packed_scene, full_scene_path)
        if debug_mode:
            print("Save result: " + str(save_error) + " (OK=" + str(OK) + ")")
        
        if save_error == OK:
            # Only do extensive testing in debug mode
            if debug_mode:
                # Wait a moment to ensure file system has time to complete the write
                print("Waiting for file system to complete write operation...")
                OS.delay_msec(500)  # 500ms delay
                
                # Verify the file was actually created using multiple methods
                var file_check_abs = FileAccess.file_exists(absolute_scene_path)
                print("File exists check (absolute path): " + str(file_check_abs))
                
                var file_check_res = FileAccess.file_exists(full_scene_path)
                print("File exists check (resource path): " + str(file_check_res))
                
                var res_exists = ResourceLoader.exists(full_scene_path)
                print("Resource exists check: " + str(res_exists))
                
                # If file doesn't exist by absolute path, try to create a test file in the same directory
                if not file_check_abs and not file_check_res:
                    printerr("Scene file not found after save. Trying to diagnose the issue...")
                    
                    # Try to write a test file to the same directory
                    var test_scene_file_path = scene_dir_res + "/test_scene_file.tmp"
                    var test_scene_file = FileAccess.open(test_scene_file_path, FileAccess.WRITE)
                    
                    if test_scene_file:
                        test_scene_file.store_string("Test scene directory write")
                        test_scene_file.close()
                        print("Successfully wrote test file to scene directory: " + test_scene_file_path)
                        
                        # Check if the test file exists
                        var test_file_exists = FileAccess.file_exists(test_scene_file_path)
                        print("Test file exists: " + str(test_file_exists))
                        
                        if test_file_exists:
                            # Directory is writable, so the issue is with scene saving
                            printerr("Directory is writable but scene file wasn't created.")
                            printerr("This suggests an issue with ResourceSaver.save() or the packed scene.")
                            
                            # Try saving with a different approach
                            print("Trying alternative save approach...")
                            var alt_save_error = ResourceSaver.save(packed_scene, test_scene_file_path + ".tscn")
                            print("Alternative save result: " + str(alt_save_error))
                            
                            # Clean up test files
                            DirAccess.remove_absolute(ProjectSettings.globalize_path(test_scene_file_path))
                            if alt_save_error == OK:
                                DirAccess.remove_absolute(ProjectSettings.globalize_path(test_scene_file_path + ".tscn"))
                        else:
                            printerr("Test file couldn't be verified. This suggests filesystem access issues.")
                    else:
                        var write_error = FileAccess.get_open_error()
                        printerr("Failed to write test file to scene directory: " + str(write_error))
                        printerr("This confirms there are permission or path issues with the scene directory.")
                    
                    # Return error since we couldn't create the scene file
                    printerr("Failed to create scene: " + params.scene_path)
                    quit(1)
                
                # If we get here, at least one of our file checks passed
                if file_check_abs or file_check_res or res_exists:
                    print("Scene file verified to exist!")
                    
                    # Try to load the scene to verify it's valid
                    var test_load = ResourceLoader.load(full_scene_path)
                    if test_load:
                        print("Scene created and verified successfully at: " + params.scene_path)
                        print("Scene file can be loaded correctly.")
                    else:
                        print("Scene file exists but cannot be loaded. It may be corrupted or incomplete.")
                        # Continue anyway since the file exists
                    
                    print("Scene created successfully at: " + params.scene_path)
                else:
                    printerr("All file existence checks failed despite successful save operation.")
                    printerr("This indicates a serious issue with file system access or path resolution.")
                    quit(1)
            else:
                # In non-debug mode, just check if the file exists
                var file_exists = FileAccess.file_exists(full_scene_path)
                if file_exists:
                    print("Scene created successfully at: " + params.scene_path)
                else:
                    printerr("Failed to create scene: " + params.scene_path)
                    quit(1)
        else:
            # Handle specific error codes
            var error_message = "Failed to save scene. Error code: " + str(save_error)
            
            if save_error == ERR_CANT_CREATE:
                error_message += " (ERR_CANT_CREATE - Cannot create the scene file)"
            elif save_error == ERR_CANT_OPEN:
                error_message += " (ERR_CANT_OPEN - Cannot open the scene file for writing)"
            elif save_error == ERR_FILE_CANT_WRITE:
                error_message += " (ERR_FILE_CANT_WRITE - Cannot write to the scene file)"
            elif save_error == ERR_FILE_NO_PERMISSION:
                error_message += " (ERR_FILE_NO_PERMISSION - No permission to write the scene file)"
            
            printerr(error_message)
            quit(1)
    else:
        printerr("Failed to pack scene: " + str(result))
        printerr("Error code: " + str(result))
        quit(1)

# Add a node to an existing scene
func add_node(params):
    print("Adding node to scene: " + params.scene_path)
    
    var full_scene_path = params.scene_path
    if not full_scene_path.begins_with("res://"):
        full_scene_path = "res://" + full_scene_path
    if debug_mode:
        print("Scene path (with res://): " + full_scene_path)
    
    var absolute_scene_path = ProjectSettings.globalize_path(full_scene_path)
    if debug_mode:
        print("Absolute scene path: " + absolute_scene_path)
    
    if not FileAccess.file_exists(absolute_scene_path):
        printerr("Scene file does not exist at: " + absolute_scene_path)
        quit(1)
    
    var scene = load(full_scene_path)
    if not scene:
        printerr("Failed to load scene: " + full_scene_path)
        quit(1)
    
    if debug_mode:
        print("Scene loaded successfully")
    var scene_root = scene.instantiate()
    if debug_mode:
        print("Scene instantiated")
    
    # Use traditional if-else statement for better compatibility
    var parent_path = "root"  # Default value
    if params.has("parent_node_path"):
        parent_path = params.parent_node_path
    if debug_mode:
        print("Parent path: " + parent_path)
    
    var parent = scene_root
    if parent_path != "root":
        parent = scene_root.get_node(parent_path.replace("root/", ""))
        if not parent:
            printerr("Parent node not found: " + parent_path)
            quit(1)
    if debug_mode:
        print("Parent node found: " + parent.name)
    
    if debug_mode:
        print("Instantiating node of type: " + params.node_type)
    var new_node = instantiate_class(params.node_type)
    if not new_node:
        printerr("Failed to instantiate node of type: " + params.node_type)
        printerr("Make sure the class exists and can be instantiated")
        printerr("Check if the class is registered in ClassDB or available as a script")
        quit(1)
    new_node.name = params.node_name
    if debug_mode:
        print("New node created with name: " + new_node.name)
    
    if params.has("properties"):
        if debug_mode:
            print("Setting properties on node")
        var properties = params.properties
        for property in properties:
            if debug_mode:
                print("Setting property: " + property + " = " + str(properties[property]))
            new_node.set(property, properties[property])
    
    parent.add_child(new_node)
    new_node.owner = scene_root
    if debug_mode:
        print("Node added to parent and ownership set")
    
    var packed_scene = PackedScene.new()
    var result = packed_scene.pack(scene_root)
    if debug_mode:
        print("Pack result: " + str(result) + " (OK=" + str(OK) + ")")
    
    if result == OK:
        if debug_mode:
            print("Saving scene to: " + absolute_scene_path)
        var save_error = ResourceSaver.save(packed_scene, absolute_scene_path)
        if debug_mode:
            print("Save result: " + str(save_error) + " (OK=" + str(OK) + ")")
        if save_error == OK:
            if debug_mode:
                var file_check_after = FileAccess.file_exists(absolute_scene_path)
                print("File exists check after save: " + str(file_check_after))
                if file_check_after:
                    print("Node '" + params.node_name + "' of type '" + params.node_type + "' added successfully")
                else:
                    printerr("File reported as saved but does not exist at: " + absolute_scene_path)
            else:
                print("Node '" + params.node_name + "' of type '" + params.node_type + "' added successfully")
        else:
            printerr("Failed to save scene: " + str(save_error))
    else:
        printerr("Failed to pack scene: " + str(result))

# Load a sprite into a Sprite2D node
func load_sprite(params):
    print("Loading sprite into scene: " + params.scene_path)
    
    # Ensure the scene path starts with res:// for Godot's resource system
    var full_scene_path = params.scene_path
    if not full_scene_path.begins_with("res://"):
        full_scene_path = "res://" + full_scene_path
    
    if debug_mode:
        print("Full scene path (with res://): " + full_scene_path)
    
    # Check if the scene file exists
    var file_check = FileAccess.file_exists(full_scene_path)
    if debug_mode:
        print("Scene file exists check: " + str(file_check))
    
    if not file_check:
        printerr("Scene file does not exist at: " + full_scene_path)
        # Get the absolute path for reference
        var absolute_path = ProjectSettings.globalize_path(full_scene_path)
        printerr("Absolute file path that doesn't exist: " + absolute_path)
        quit(1)
    
    # Ensure the texture path starts with res:// for Godot's resource system
    var full_texture_path = params.texture_path
    if not full_texture_path.begins_with("res://"):
        full_texture_path = "res://" + full_texture_path
    
    if debug_mode:
        print("Full texture path (with res://): " + full_texture_path)
    
    # Load the scene
    var scene = load(full_scene_path)
    if not scene:
        printerr("Failed to load scene: " + full_scene_path)
        quit(1)
    
    if debug_mode:
        print("Scene loaded successfully")
    
    # Instance the scene
    var scene_root = scene.instantiate()
    if debug_mode:
        print("Scene instantiated")
    
    # Find the sprite node
    var node_path = params.node_path
    if debug_mode:
        print("Original node path: " + node_path)
    
    if node_path.begins_with("root/"):
        node_path = node_path.substr(5)  # Remove "root/" prefix
        if debug_mode:
            print("Node path after removing 'root/' prefix: " + node_path)
    
    var sprite_node = null
    if node_path == "":
        # If no node path, assume root is the sprite
        sprite_node = scene_root
        if debug_mode:
            print("Using root node as sprite node")
    else:
        sprite_node = scene_root.get_node(node_path)
        if sprite_node and debug_mode:
            print("Found sprite node: " + sprite_node.name)
    
    if not sprite_node:
        printerr("Node not found: " + params.node_path)
        quit(1)
    
    # Check if the node is a Sprite2D or compatible type
    if debug_mode:
        print("Node class: " + sprite_node.get_class())
    if not (sprite_node is Sprite2D or sprite_node is Sprite3D or sprite_node is TextureRect):
        printerr("Node is not a sprite-compatible type: " + sprite_node.get_class())
        quit(1)
    
    # Load the texture
    if debug_mode:
        print("Loading texture from: " + full_texture_path)
    var texture = load(full_texture_path)
    if not texture:
        printerr("Failed to load texture: " + full_texture_path)
        quit(1)
    
    if debug_mode:
        print("Texture loaded successfully")
    
    # Set the texture on the sprite
    if sprite_node is Sprite2D or sprite_node is Sprite3D:
        sprite_node.texture = texture
        if debug_mode:
            print("Set texture on Sprite2D/Sprite3D node")
    elif sprite_node is TextureRect:
        sprite_node.texture = texture
        if debug_mode:
            print("Set texture on TextureRect node")
    
    # Save the modified scene
    var packed_scene = PackedScene.new()
    var result = packed_scene.pack(scene_root)
    if debug_mode:
        print("Pack result: " + str(result) + " (OK=" + str(OK) + ")")
    
    if result == OK:
        if debug_mode:
            print("Saving scene to: " + full_scene_path)
        var error = ResourceSaver.save(packed_scene, full_scene_path)
        if debug_mode:
            print("Save result: " + str(error) + " (OK=" + str(OK) + ")")
        
        if error == OK:
            # Verify the file was actually updated
            if debug_mode:
                var file_check_after = FileAccess.file_exists(full_scene_path)
                print("File exists check after save: " + str(file_check_after))
                
                if file_check_after:
                    print("Sprite loaded successfully with texture: " + full_texture_path)
                    # Get the absolute path for reference
                    var absolute_path = ProjectSettings.globalize_path(full_scene_path)
                    print("Absolute file path: " + absolute_path)
                else:
                    printerr("File reported as saved but does not exist at: " + full_scene_path)
            else:
                print("Sprite loaded successfully with texture: " + full_texture_path)
        else:
            printerr("Failed to save scene: " + str(error))
    else:
        printerr("Failed to pack scene: " + str(result))

# Export a scene as a MeshLibrary resource
func export_mesh_library(params):
    print("Exporting MeshLibrary from scene: " + params.scene_path)
    
    # Ensure the scene path starts with res:// for Godot's resource system
    var full_scene_path = params.scene_path
    if not full_scene_path.begins_with("res://"):
        full_scene_path = "res://" + full_scene_path
    
    if debug_mode:
        print("Full scene path (with res://): " + full_scene_path)
    
    # Ensure the output path starts with res:// for Godot's resource system
    var full_output_path = params.output_path
    if not full_output_path.begins_with("res://"):
        full_output_path = "res://" + full_output_path
    
    if debug_mode:
        print("Full output path (with res://): " + full_output_path)
    
    # Check if the scene file exists
    var file_check = FileAccess.file_exists(full_scene_path)
    if debug_mode:
        print("Scene file exists check: " + str(file_check))
    
    if not file_check:
        printerr("Scene file does not exist at: " + full_scene_path)
        # Get the absolute path for reference
        var absolute_path = ProjectSettings.globalize_path(full_scene_path)
        printerr("Absolute file path that doesn't exist: " + absolute_path)
        quit(1)
    
    # Load the scene
    if debug_mode:
        print("Loading scene from: " + full_scene_path)
    var scene = load(full_scene_path)
    if not scene:
        printerr("Failed to load scene: " + full_scene_path)
        quit(1)
    
    if debug_mode:
        print("Scene loaded successfully")
    
    # Instance the scene
    var scene_root = scene.instantiate()
    if debug_mode:
        print("Scene instantiated")
    
    # Create a new MeshLibrary
    var mesh_library = MeshLibrary.new()
    if debug_mode:
        print("Created new MeshLibrary")
    
    # Get mesh item names if provided
    var mesh_item_names = []
    if params.has("mesh_item_names"):
        mesh_item_names = params.mesh_item_names
    var use_specific_items = mesh_item_names.size() > 0
    
    if debug_mode:
        if use_specific_items:
            print("Using specific mesh items: " + str(mesh_item_names))
        else:
            print("Using all mesh items in the scene")
    
    # Process all child nodes
    var item_id = 0
    if debug_mode:
        print("Processing child nodes...")
    
    for child in scene_root.get_children():
        if debug_mode:
            print("Checking child node: " + child.name)
        
        # Skip if not using all items and this item is not in the list
        if use_specific_items and not (child.name in mesh_item_names):
            if debug_mode:
                print("Skipping node " + child.name + " (not in specified items list)")
            continue
            
        # Check if the child has a mesh
        var mesh_instance = null
        if child is MeshInstance3D:
            mesh_instance = child
            if debug_mode:
                print("Node " + child.name + " is a MeshInstance3D")
        else:
            # Try to find a MeshInstance3D in the child's descendants
            if debug_mode:
                print("Searching for MeshInstance3D in descendants of " + child.name)
            for descendant in child.get_children():
                if descendant is MeshInstance3D:
                    mesh_instance = descendant
                    if debug_mode:
                        print("Found MeshInstance3D in descendant: " + descendant.name)
                    break
        
        if mesh_instance and mesh_instance.mesh:
            if debug_mode:
                print("Adding mesh: " + child.name)
            
            # Add the mesh to the library
            mesh_library.create_item(item_id)
            mesh_library.set_item_name(item_id, child.name)
            mesh_library.set_item_mesh(item_id, mesh_instance.mesh)
            if debug_mode:
                print("Added mesh to library with ID: " + str(item_id))
            
            # Add collision shape if available
            var collision_added = false
            for collision_child in child.get_children():
                if collision_child is CollisionShape3D and collision_child.shape:
                    mesh_library.set_item_shapes(item_id, [collision_child.shape])
                    if debug_mode:
                        print("Added collision shape from: " + collision_child.name)
                    collision_added = true
                    break
            
            if debug_mode and not collision_added:
                print("No collision shape found for mesh: " + child.name)
            
            # Add preview if available
            if mesh_instance.mesh:
                mesh_library.set_item_preview(item_id, mesh_instance.mesh)
                if debug_mode:
                    print("Added preview for mesh: " + child.name)
            
            item_id += 1
        elif debug_mode:
            print("Node " + child.name + " has no valid mesh")
    
    if debug_mode:
        print("Processed " + str(item_id) + " meshes")
    
    # Create directory if it doesn't exist
    var dir = DirAccess.open("res://")
    if dir == null:
        printerr("Failed to open res:// directory")
        printerr("DirAccess error: " + str(DirAccess.get_open_error()))
        quit(1)
        
    var output_dir = full_output_path.get_base_dir()
    if debug_mode:
        print("Output directory: " + output_dir)
    
    if output_dir != "res://" and not dir.dir_exists(output_dir.substr(6)):  # Remove "res://" prefix
        if debug_mode:
            print("Creating directory: " + output_dir)
        var error = dir.make_dir_recursive(output_dir.substr(6))  # Remove "res://" prefix
        if error != OK:
            printerr("Failed to create directory: " + output_dir + ", error: " + str(error))
            quit(1)
    
    # Save the mesh library
    if item_id > 0:
        if debug_mode:
            print("Saving MeshLibrary to: " + full_output_path)
        var error = ResourceSaver.save(mesh_library, full_output_path)
        if debug_mode:
            print("Save result: " + str(error) + " (OK=" + str(OK) + ")")
        
        if error == OK:
            # Verify the file was actually created
            if debug_mode:
                var file_check_after = FileAccess.file_exists(full_output_path)
                print("File exists check after save: " + str(file_check_after))
                
                if file_check_after:
                    print("MeshLibrary exported successfully with " + str(item_id) + " items to: " + full_output_path)
                    # Get the absolute path for reference
                    var absolute_path = ProjectSettings.globalize_path(full_output_path)
                    print("Absolute file path: " + absolute_path)
                else:
                    printerr("File reported as saved but does not exist at: " + full_output_path)
            else:
                print("MeshLibrary exported successfully with " + str(item_id) + " items to: " + full_output_path)
        else:
            printerr("Failed to save MeshLibrary: " + str(error))
    else:
        printerr("No valid meshes found in the scene")

# Find files with a specific extension recursively
func find_files(path, extension):
    var files = []
    var dir = DirAccess.open(path)
    
    if dir:
        dir.list_dir_begin()
        var file_name = dir.get_next()
        
        while file_name != "":
            if dir.current_is_dir() and not file_name.begins_with("."):
                files.append_array(find_files(path + file_name + "/", extension))
            elif file_name.ends_with(extension):
                files.append(path + file_name)
            
            file_name = dir.get_next()
    
    return files

# Get UID for a specific file
func get_uid(params):
    if not params.has("file_path"):
        printerr("File path is required")
        quit(1)
    
    # Ensure the file path starts with res:// for Godot's resource system
    var file_path = params.file_path
    if not file_path.begins_with("res://"):
        file_path = "res://" + file_path
    
    print("Getting UID for file: " + file_path)
    if debug_mode:
        print("Full file path (with res://): " + file_path)
    
    # Get the absolute path for reference
    var absolute_path = ProjectSettings.globalize_path(file_path)
    if debug_mode:
        print("Absolute file path: " + absolute_path)
    
    # Ensure the file exists
    var file_check = FileAccess.file_exists(file_path)
    if debug_mode:
        print("File exists check: " + str(file_check))
    
    if not file_check:
        printerr("File does not exist at: " + file_path)
        printerr("Absolute file path that doesn't exist: " + absolute_path)
        quit(1)
    
    # Check if the UID file exists
    var uid_path = file_path + ".uid"
    if debug_mode:
        print("UID file path: " + uid_path)
    
    var uid_check = FileAccess.file_exists(uid_path)
    if debug_mode:
        print("UID file exists check: " + str(uid_check))
    
    var f = FileAccess.open(uid_path, FileAccess.READ)
    
    if f:
        # Read the UID content
        var uid_content = f.get_as_text()
        f.close()
        if debug_mode:
            print("UID content read successfully")
        
        # Return the UID content
        var result = {
            "file": file_path,
            "absolutePath": absolute_path,
            "uid": uid_content.strip_edges(),
            "exists": true
        }
        if debug_mode:
            print("UID result: " + JSON.stringify(result))
        print(JSON.stringify(result))
    else:
        if debug_mode:
            print("UID file does not exist or could not be opened")
        
        # UID file doesn't exist
        var result = {
            "file": file_path,
            "absolutePath": absolute_path,
            "exists": false,
            "message": "UID file does not exist for this file. Use resave_resources to generate UIDs."
        }
        if debug_mode:
            print("UID result: " + JSON.stringify(result))
        print(JSON.stringify(result))

# Resave all resources to update UID references
func resave_resources(params):
    print("Resaving all resources to update UID references...")
    
    # Get project path if provided
    var project_path = "res://"
    if params.has("project_path"):
        project_path = params.project_path
        if not project_path.begins_with("res://"):
            project_path = "res://" + project_path
        if not project_path.ends_with("/"):
            project_path += "/"
    
    if debug_mode:
        print("Using project path: " + project_path)
    
    # Get all .tscn files
    if debug_mode:
        print("Searching for scene files in: " + project_path)
    var scenes = find_files(project_path, ".tscn")
    if debug_mode:
        print("Found " + str(scenes.size()) + " scenes")
    
    # Resave each scene
    var success_count = 0
    var error_count = 0
    
    for scene_path in scenes:
        if debug_mode:
            print("Processing scene: " + scene_path)
        
        # Check if the scene file exists
        var file_check = FileAccess.file_exists(scene_path)
        if debug_mode:
            print("Scene file exists check: " + str(file_check))
        
        if not file_check:
            printerr("Scene file does not exist at: " + scene_path)
            error_count += 1
            continue
        
        # Load the scene
        var scene = load(scene_path)
        if scene:
            if debug_mode:
                print("Scene loaded successfully, saving...")
            var error = ResourceSaver.save(scene, scene_path)
            if debug_mode:
                print("Save result: " + str(error) + " (OK=" + str(OK) + ")")
            
            if error == OK:
                success_count += 1
                if debug_mode:
                    print("Scene saved successfully: " + scene_path)
                
                    # Verify the file was actually updated
                    var file_check_after = FileAccess.file_exists(scene_path)
                    print("File exists check after save: " + str(file_check_after))
                
                    if not file_check_after:
                        printerr("File reported as saved but does not exist at: " + scene_path)
            else:
                error_count += 1
                printerr("Failed to save: " + scene_path + ", error: " + str(error))
        else:
            error_count += 1
            printerr("Failed to load: " + scene_path)
    
    # Get all .gd and .shader files
    if debug_mode:
        print("Searching for script and shader files in: " + project_path)
    var scripts = find_files(project_path, ".gd") + find_files(project_path, ".shader") + find_files(project_path, ".gdshader")
    if debug_mode:
        print("Found " + str(scripts.size()) + " scripts/shaders")
    
    # Check for missing .uid files
    var missing_uids = 0
    var generated_uids = 0
    
    for script_path in scripts:
        if debug_mode:
            print("Checking UID for: " + script_path)
        var uid_path = script_path + ".uid"
        
        var uid_check = FileAccess.file_exists(uid_path)
        if debug_mode:
            print("UID file exists check: " + str(uid_check))
        
        var f = FileAccess.open(uid_path, FileAccess.READ)
        if not f:
            missing_uids += 1
            if debug_mode:
                print("Missing UID file for: " + script_path + ", generating...")
            
            # Force a save to generate UID
            var res = load(script_path)
            if res:
                var error = ResourceSaver.save(res, script_path)
                if debug_mode:
                    print("Save result: " + str(error) + " (OK=" + str(OK) + ")")
                
                if error == OK:
                    generated_uids += 1
                    if debug_mode:
                        print("Generated UID for: " + script_path)
                    
                        # Verify the UID file was actually created
                        var uid_check_after = FileAccess.file_exists(uid_path)
                        print("UID file exists check after save: " + str(uid_check_after))
                    
                        if not uid_check_after:
                            printerr("UID file reported as generated but does not exist at: " + uid_path)
                else:
                    printerr("Failed to generate UID for: " + script_path + ", error: " + str(error))
            else:
                printerr("Failed to load resource: " + script_path)
        elif debug_mode:
            print("UID file already exists for: " + script_path)
    
    if debug_mode:
        print("Summary:")
        print("- Scenes processed: " + str(scenes.size()))
        print("- Scenes successfully saved: " + str(success_count))
        print("- Scenes with errors: " + str(error_count))
        print("- Scripts/shaders missing UIDs: " + str(missing_uids))
        print("- UIDs successfully generated: " + str(generated_uids))
    print("Resave operation complete")

# Save changes to a scene file
func save_scene(params):
    print("Saving scene: " + params.scene_path)
    
    # Ensure the scene path starts with res:// for Godot's resource system
    var full_scene_path = params.scene_path
    if not full_scene_path.begins_with("res://"):
        full_scene_path = "res://" + full_scene_path
    
    if debug_mode:
        print("Full scene path (with res://): " + full_scene_path)
    
    # Check if the scene file exists
    var file_check = FileAccess.file_exists(full_scene_path)
    if debug_mode:
        print("Scene file exists check: " + str(file_check))
    
    if not file_check:
        printerr("Scene file does not exist at: " + full_scene_path)
        # Get the absolute path for reference
        var absolute_path = ProjectSettings.globalize_path(full_scene_path)
        printerr("Absolute file path that doesn't exist: " + absolute_path)
        quit(1)
    
    # Load the scene
    var scene = load(full_scene_path)
    if not scene:
        printerr("Failed to load scene: " + full_scene_path)
        quit(1)
    
    if debug_mode:
        print("Scene loaded successfully")
    
    # Instance the scene
    var scene_root = scene.instantiate()
    if debug_mode:
        print("Scene instantiated")
    
    # Determine save path
    var save_path = full_scene_path
    if params.has("new_path"):
        save_path = params.new_path
    if params.has("new_path") and not save_path.begins_with("res://"):
        save_path = "res://" + save_path
    
    if debug_mode:
        print("Save path: " + save_path)
    
    # Create directory if it doesn't exist
    if params.has("new_path"):
        var dir = DirAccess.open("res://")
        if dir == null:
            printerr("Failed to open res:// directory")
            printerr("DirAccess error: " + str(DirAccess.get_open_error()))
            quit(1)
            
        var scene_dir = save_path.get_base_dir()
        if debug_mode:
            print("Scene directory: " + scene_dir)
        
        if scene_dir != "res://" and not dir.dir_exists(scene_dir.substr(6)):  # Remove "res://" prefix
            if debug_mode:
                print("Creating directory: " + scene_dir)
            var error = dir.make_dir_recursive(scene_dir.substr(6))  # Remove "res://" prefix
            if error != OK:
                printerr("Failed to create directory: " + scene_dir + ", error: " + str(error))
                quit(1)
    
    # Create a packed scene
    var packed_scene = PackedScene.new()
    var result = packed_scene.pack(scene_root)
    if debug_mode:
        print("Pack result: " + str(result) + " (OK=" + str(OK) + ")")
    
    if result == OK:
        if debug_mode:
            print("Saving scene to: " + save_path)
        var error = ResourceSaver.save(packed_scene, save_path)
        if debug_mode:
            print("Save result: " + str(error) + " (OK=" + str(OK) + ")")
        
        if error == OK:
            # Verify the file was actually created/updated
            if debug_mode:
                var file_check_after = FileAccess.file_exists(save_path)
                print("File exists check after save: " + str(file_check_after))
                
                if file_check_after:
                    print("Scene saved successfully to: " + save_path)
                    # Get the absolute path for reference
                    var absolute_path = ProjectSettings.globalize_path(save_path)
                    print("Absolute file path: " + absolute_path)
                else:
                    printerr("File reported as saved but does not exist at: " + save_path)
            else:
                print("Scene saved successfully to: " + save_path)
        else:
            printerr("Failed to save scene: " + str(error))
    else:
        printerr("Failed to pack scene: " + str(result))
