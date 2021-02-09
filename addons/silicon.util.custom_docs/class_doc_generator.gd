tool
extends Reference

const _GD_TYPES = [
	"", "bool", "int", "float",
	"String", "Vector2", "Rect2", "Vector3",
	"Transform2D", "Plane", "Quat", "AABB",
	"Basis", "Transform", "Color", "NodePath",
	"RID", "Object", "Dictionary", "Array",
	"PoolByteArray", "PoolIntArray", "PoolRealArray", "PoolStringArray",
	"PoolVector2Array", "PoolVector3Array", "PoolColorArray"
]

var plugin: EditorPlugin

func generate(name: String, base: String, script_path: String) -> ClassDocItem:
	var script: GDScript = load(script_path)
	var code_lines := script.source_code.split("\n")
	var doc := ClassDocItem.new({
		name = name,
		base = base
	})
	
	var inherits := base
	var parent_props := []
	var parent_methods := []
	while inherits != "" and inherits in plugin.class_docs:
		for prop in plugin.class_docs[inherits].properties:
			parent_props.append(prop.name)
		for method in plugin.class_docs[inherits].methods:
			parent_methods.append(method.name)
		inherits = plugin.get_parent_class(inherits)
	
	for method in script.get_script_method_list():
		if method.name.begins_with("_") or method.name in parent_methods:
			continue
		doc.methods.append(_create_method_doc(method.name, script, method))
	
	for property in script.get_script_property_list():
		if property.name.begins_with("_") or property.name in parent_props:
			continue
		doc.properties.append(_create_property_doc(property.name, script, property))
	
	for _signal in script.get_script_signal_list():
		var signal_doc := SignalDocItem.new({
			"name": _signal.name
		})
		doc.signals.append(signal_doc)
		
		for arg in _signal.args:
			signal_doc.args.append(ArgumentDocItem.new({
				"name": arg.name,
				"type": _type_string(
					arg.type, 
					arg["class_name"]
				) if arg.type != TYPE_NIL else "Variant"
			}))
	
	for constant in script.get_script_constant_map():
		var value = script.get_script_constant_map()[constant]
		
		# Check if constant is an enumerator.
		var is_enum := false
		if typeof(value) == TYPE_DICTIONARY:
			is_enum = true
			for i in value.size():
				if typeof(value.keys()[i]) != TYPE_STRING or typeof(value.values()[i]) != TYPE_INT:
					is_enum = false
					break
		
		if is_enum:
			for _enum in value:
				doc.constants.append(ConstantDocItem.new({
					"name": _enum,
					"value": value[_enum],
					"enumeration": constant
				}))
		else:
			doc.constants.append(ConstantDocItem.new({
				"name": constant,
				"value": value
			}))
	
	var comment_block := ""
	var annotations := {}
	var reading_block := false
	var enum_block := false
	for line in code_lines:
		var indented: bool = line.begins_with(" ") or line.begins_with("\t")
		if line.begins_with("##"):
			reading_block = true
		else:
			reading_block = false
			comment_block = comment_block.trim_suffix("\n")
		
		if line.begins_with("enum"):
			enum_block = true
		if line.find("}") != -1 and enum_block:
			enum_block = false
		
		if line.find("##") != -1 and not reading_block:
			var offset := 3 if line.find("## ") != -1 else 2
			comment_block = line.right(line.find("##") + offset)
		
		if reading_block:
			if line.begins_with("## "):
				line = line.trim_prefix("## ")
			else:
				line = line.trim_prefix("##")
			if line.begins_with("@"):
				var annote: Array = line.split(" ", true, 1)
				if annote[0] == "@tutorial" and annote.size() == 2:
					if annotations.has("@tutorial"):
						annotations["@tutorial"].append(annote[1])
						annote[1] = annotations["@tutorial"]
					else:
						annote[1] = [annote[1]]
				annotations[annote[0]] = null if annote.size() == 1 else annote[1]
			else:
				comment_block += line + "\n"
			
		elif not comment_block.empty():
			if line.begins_with("extends") or line.begins_with("tool") or line.begins_with("class_name"):
				if annotations.has("@doc-ignore"):
					return null
				if annotations.has("@contribute"):
					doc.contriute_url = annotations["@contribute"]
				if annotations.has("@tutorial"):
					doc.tutorials = annotations["@tutorial"]
				var doc_split = comment_block.split("\n", true, 1)
				doc.brief = doc_split[0]
				if doc_split.size() == 2:
					doc.description = doc_split[1]
				
			elif line.find("func ") != -1 and not indented:
				var regex := RegEx.new()
				regex.compile("func ([a-zA-Z0-9_]+)")
				var method := regex.search(line).get_string(1)
				var method_doc := doc.get_method_doc(method)
				
				if not method_doc and method:
					method_doc = _create_method_doc(method, script)
					doc.methods.append(method_doc)
				
				if method_doc:
					if annotations.has("@args"):
						var params = annotations["@args"].split(",")
						for i in min(params.size(), method_doc.args.size()):
							method_doc.args[i].name = params[i].strip_edges()
					if annotations.has("@arg-types"):
						var params = annotations["@arg-types"].split(",")
						for i in min(params.size(), method_doc.args.size()):
							method_doc.args[i].type = params[i].strip_edges()
					if annotations.has("@arg-enums"):
						var params = annotations["@arg-enums"].split(",")
						for i in min(params.size(), method_doc.args.size()):
							method_doc.args[i].enumeration = params[i].strip_edges()
					if annotations.has("@return"):
						method_doc.return_type = annotations["@return"]
					if annotations.has("@return-enum"):
						method_doc.return_enum = annotations["@return-enum"]
					method_doc.is_virtual = annotations.has("@virtual")
					method_doc.description = comment_block
				
			elif line.find("var ") != -1 and not indented:
				var regex := RegEx.new()
				regex.compile("var ([a-zA-Z0-9_]+)")
				var prop := regex.search(line).get_string(1)
				var prop_doc := doc.get_property_doc(prop)
				
				if not prop_doc and prop:
					prop_doc = _create_property_doc(prop, script)
					doc.properties.append(prop_doc)
				
				if prop_doc:
					if annotations.has("@type"):
						prop_doc.type = annotations["@type"]
					if annotations.has("@default"):
						prop_doc.default = annotations["@default"]
					if annotations.has("@enum"):
						prop_doc.enumeration = annotations["@enum"]
					if annotations.has("@setter"):
						prop_doc.setter = annotations["@setter"]
					if annotations.has("@getter"):
						prop_doc.getter = annotations["@getter"]
					prop_doc.description = comment_block
				
			elif line.find("signal") != -1 and not indented:
				var regex := RegEx.new()
				regex.compile("signal ([a-zA-Z0-9_]+)")
				var signl := regex.search(line).get_string(1)
				var signal_doc := doc.get_signal_doc(signl)
				if signal_doc:
					if annotations.has("@arg-types"):
						var params = annotations["@arg-types"].split(",")
						for i in min(params.size(), signal_doc.args.size()):
							signal_doc.args[i].type = params[i].strip_edges()
					if annotations.has("@arg-enums"):
						var params = annotations["@arg-enums"].split(",")
						for i in min(params.size(), signal_doc.args.size()):
							signal_doc.args[i].enumeration = params[i].strip_edges()
					signal_doc.description = comment_block
				
			elif line.find("const") != -1 and not indented:
				var regex := RegEx.new()
				regex.compile("const ([a-zA-Z0-9_]+)")
				var constant := regex.search(line).get_string(1)
				var const_doc := doc.get_constant_doc(constant)
				if const_doc:
					const_doc.description = comment_block
			
			else:
				for constant in doc.constants:
					if line.find(constant.name) != -1:
						constant.description = comment_block
						break
			
			comment_block = ""
			annotations.clear()
	
	return doc


func _create_method_doc(name: String, script: Script = null, method := {}) -> MethodDocItem:
	if method.empty():
		var methods := script.get_script_method_list()
		for m in methods:
			if m.name == name:
				method = m
				break
	
	var method_doc := MethodDocItem.new({
		"name": method.name,
		"return_type": _type_string(
			method["return"]["type"],
			method["return"]["class_name"]
		) if method["return"]["type"] != TYPE_NIL else "void",
	})
	for arg in method.args:
		method_doc.args.append(ArgumentDocItem.new({
			"name": arg.name,
			"type": _type_string(
				arg.type, 
				arg["class_name"]
			) if arg.type != TYPE_NIL else "Variant"
		}))
	return method_doc


func _create_property_doc(name: String, script: Script = null, property := {}) -> PropertyDocItem:
	if property.empty():
		var properties := script.get_script_property_list()
		for p in properties:
			if p.name == name:
				property = p
				break
	
	var property_doc := PropertyDocItem.new({
		"name": property.name,
		"type": _type_string(
			property.type,
			property["class_name"]
		) if property.type != TYPE_NIL else "Variant"
	})
	return property_doc


func _type_string(type: int, _class_name: String) -> String:
	if type == TYPE_OBJECT:
		return _class_name
	else:
		return _GD_TYPES[type]
