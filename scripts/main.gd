extends VBoxContainer

var variables = {}  # 存储变量值
var is_running = false
var current_node = null
var waiting_for_input = false
var popup_menu: PopupMenu
var node_execution_count = {}  # 记录每个节点的执行次数
var execution_start_time = 0   # 记录执行开始时间
const MAX_EXECUTIONS = 10000    # 单个节点最大执行次数
const MAX_EXECUTION_TIME = 30   # 最大执行时间（秒）
var HelpWindow = preload("res://scenes/HelpWindow.tscn")
var FlowNode = preload("res://scenes/FlowNode.tscn")  # 恢复使用单一的 FlowNode
var is_dragging = false
var drag_start_pos = Vector2()
var initial_scroll_offset = Vector2()
var right_click_start_time = 0  # 记录右键按下的时间
const LONG_PRESS_TIME = 0.3     # 长按判定时间（秒）

func _ready():
	var component_list = $WorkArea/ComponentPanel/ComponentList
	for button in component_list.get_children():
		button.pressed.connect(_on_component_button_pressed.bind(button))
	
	# 更新 GraphEdit 的路径
	$WorkArea/VBoxContainer/GraphEdit.connection_request.connect(_on_connection_request)
	$WorkArea/VBoxContainer/GraphEdit.disconnection_request.connect(_on_disconnection_request)
	$WorkArea/VBoxContainer/GraphEdit.delete_nodes_request.connect(_on_delete_nodes_request)
	$MenuBar/HBoxContainer/RunButton.pressed.connect(_on_run_button_pressed)
	$WorkArea/VBoxContainer/TerminalPanel/VBoxContainer/Terminal.gui_input.connect(_on_terminal_gui_input)
	
	# 连接小地图按钮信号
	$MenuBar/HBoxContainer/MinimapButton.toggled.connect(_on_minimap_button_toggled)
	$MenuBar/HBoxContainer/MinimapButton.button_pressed = false  # 初始状态为关闭
	_update_minimap_button_text(false)
	
	# 创建右键菜单
	popup_menu = PopupMenu.new()
	add_child(popup_menu)
	popup_menu.add_item("输入", 0)
	popup_menu.add_item("输出", 1)
	popup_menu.add_item("赋值", 2)
	popup_menu.add_item("选择", 3)
	popup_menu.add_item("循环", 4)
	popup_menu.add_item("结束", 5)
	popup_menu.add_item("字符串", 6)
	popup_menu.id_pressed.connect(_on_popup_menu_item_selected)
	
	# 连接 GraphEdit 的右键菜单信号
	$WorkArea/VBoxContainer/GraphEdit.gui_input.connect(_on_graph_edit_gui_input)
	
	# 创建开始节点
	_create_node("开始", Vector2(100, 100))
	
	# 连接帮助按钮信号
	$MenuBar/HBoxContainer/HelpButton.pressed.connect(_on_help_button_pressed)
	
	# 连接保存和导入按钮信号
	$MenuBar/HBoxContainer/SaveButton.pressed.connect(_on_save_button_pressed)
	$MenuBar/HBoxContainer/LoadButton.pressed.connect(_on_load_button_pressed)
	
	# 连接终端按钮信号
	$WorkArea/VBoxContainer/TerminalPanel/VBoxContainer/TitleBar/ResetButton.pressed.connect(_on_reset_button_pressed)
	$WorkArea/VBoxContainer/TerminalPanel/VBoxContainer/TitleBar/CopyButton.pressed.connect(_on_copy_button_pressed)

func _create_node(type: String, position: Vector2) -> GraphNode:
	var node = FlowNode.instantiate()
	node.node_type = type
	node.position_offset = position
	$WorkArea/VBoxContainer/GraphEdit.add_child(node)
	return node

func _on_component_button_pressed(button: Button):
	var mouse_pos = get_viewport().get_mouse_position()
	var graph_pos = $WorkArea/VBoxContainer/GraphEdit.get_local_mouse_position()
	_create_node(button.text, graph_pos)

func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int):
	# 检查是否是有效的连接
	var from_node_obj = $WorkArea/VBoxContainer/GraphEdit.get_node(NodePath(from_node))
	var to_node_obj = $WorkArea/VBoxContainer/GraphEdit.get_node(NodePath(to_node))
	
	# 不允许连接到开始节点
	if to_node_obj.node_type == "开始":
		return
	
	# 不允许从结束节点连出
	if from_node_obj.node_type == "结束":
		return
	
	# 不允许连接到已经有输入的节点
	var existing_connections = $WorkArea/VBoxContainer/GraphEdit.get_connection_list()
	for connection in existing_connections:
		if connection["to_node"] == to_node and connection["to_port"] == to_port:
			return
	
	# 如果所有检查都通过，创建连接
	$WorkArea/VBoxContainer/GraphEdit.connect_node(from_node, from_port, to_node, to_port)

func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int):
	$WorkArea/VBoxContainer/GraphEdit.disconnect_node(from_node, from_port, to_node, to_port)

func _on_delete_nodes_request(nodes: Array):
	for node_name in nodes:
		var node = $WorkArea/VBoxContainer/GraphEdit.get_node(NodePath(node_name))
		if node.node_type != "开始":  # 不允许删除开始节点
			node.queue_free()

func _on_run_button_pressed():
	if is_running:
		return
		
	is_running = true
	variables.clear()
	node_execution_count.clear()  # 清空执行计数
	execution_start_time = Time.get_unix_time_from_system()  # 记录开始时间
	$WorkArea/VBoxContainer/TerminalPanel/VBoxContainer/Terminal.clear()
	add_terminal_line("=== 程序开始执行 ===")
	
	# 从开始节点开始执行
	for node in $WorkArea/VBoxContainer/GraphEdit.get_children():
		if node is GraphNode and node.node_type == "开始":
			current_node = node
			execute_node(node)
			break

func add_terminal_line(text: String, color: Color = Color.WHITE):
	if color == Color.WHITE:
		$WorkArea/VBoxContainer/TerminalPanel/VBoxContainer/Terminal.text += text + "\n"
	else:
		$WorkArea/VBoxContainer/TerminalPanel/VBoxContainer/Terminal.text += "[" + color.to_html() + "]" + text + "\n"
	$WorkArea/VBoxContainer/TerminalPanel/VBoxContainer/Terminal.scroll_vertical = INF

func _on_terminal_gui_input(event: InputEvent):
	if waiting_for_input and event is InputEventKey:
		if event.pressed and event.keycode == KEY_ENTER and not event.echo:
			var lines = $WorkArea/VBoxContainer/TerminalPanel/VBoxContainer/Terminal.text.split("\n")
			var last_line = lines[-1]  # 获取最后一行
			if last_line.begins_with("> "):
				var text = last_line.substr(2).strip_edges()
				if not text.is_empty():
					$WorkArea/VBoxContainer/TerminalPanel/VBoxContainer/Terminal.text += "\n"  # 添加换行
					_handle_input(text)
			get_viewport().set_input_as_handled()

func _handle_input(text: String):
	if waiting_for_input:
		waiting_for_input = false
		var var_name = current_node.get_value()["var_name"]
		
		# 尝试将输入转换为数字
		if text.is_valid_float():
			variables[var_name] = float(text)
			add_terminal_line("已输入数值：" + var_name + " = " + text)
		else:
			variables[var_name] = text
			add_terminal_line("已输入文本：" + var_name + " = " + text)
		
		$WorkArea/VBoxContainer/TerminalPanel/VBoxContainer/Terminal.editable = false
		continue_execution()

func check_infinite_loop() -> bool:
	# 检查执行时间
	var current_time = Time.get_unix_time_from_system()
	if current_time - execution_start_time > MAX_EXECUTION_TIME:
		add_terminal_line("警告：程序执行时间超过 " + str(MAX_EXECUTION_TIME) + " 秒")
		add_terminal_line("如果这是预期的，请考虑优化算法")
		return true
	
	# 检查节点执行次数
	if current_node.name in node_execution_count:
		node_execution_count[current_node.name] += 1
	else:
		node_execution_count[current_node.name] = 1
	
	if node_execution_count[current_node.name] > MAX_EXECUTIONS:
		add_terminal_line("警告：节点 '" + current_node.node_type + "' 执行次数超过 " + str(MAX_EXECUTIONS) + " 次")
		add_terminal_line("如果这是预期的，请考虑优化循环逻辑")
		return true
	
	return false

func execute_node(node: GraphNode):
	if not node:
		is_running = false
		add_terminal_line("=== 程序执行结束 ===")
		return
	
	# 检查死循环
	if check_infinite_loop():
		is_running = false
		add_terminal_line("=== 程序异常终止 ===")
		return
		
	match node.node_type:
		"输入":
			var var_name = node.get_value()["var_name"]
			if var_name.strip_edges().is_empty():
				add_terminal_line("错误：输入变量名不能为空")
				is_running = false
				return
			add_terminal_line("请输入 " + var_name + " 的值：")
			$WorkArea/VBoxContainer/TerminalPanel/VBoxContainer/Terminal.text += "> "
			waiting_for_input = true
			current_node = node
			$WorkArea/VBoxContainer/TerminalPanel/VBoxContainer/Terminal.editable = true
			$WorkArea/VBoxContainer/TerminalPanel/VBoxContainer/Terminal.scroll_vertical = INF
			$WorkArea/VBoxContainer/TerminalPanel/VBoxContainer/Terminal.set_caret_line($WorkArea/VBoxContainer/TerminalPanel/VBoxContainer/Terminal.get_line_count() - 1)
			$WorkArea/VBoxContainer/TerminalPanel/VBoxContainer/Terminal.set_caret_column($WorkArea/VBoxContainer/TerminalPanel/VBoxContainer/Terminal.get_line($WorkArea/VBoxContainer/TerminalPanel/VBoxContainer/Terminal.get_line_count() - 1).length())
			$WorkArea/VBoxContainer/TerminalPanel/VBoxContainer/Terminal.grab_focus()
			
		"赋值":
			var data = node.get_value()
			var var_name = data["var_name"]
			var expression = data["value"]
			
			if var_name.strip_edges().is_empty() or expression.strip_edges().is_empty():
				add_terminal_line("错误：变量名和表达式不能为空")
				is_running = false
				return
				
			# 计算表达式
			var expr = Expression.new()
			var error = expr.parse(expression, variables.keys())
			if error != OK:
				add_terminal_line("错误：表达式无效 - " + expression)
				is_running = false
				return
				
			var result = expr.execute(variables.values())
			if expr.has_execute_failed():
				add_terminal_line("错误：表达式执行失败 - " + expression)
				is_running = false
				return
				
			variables[var_name] = result
			add_terminal_line("赋值：" + var_name + " = " + str(result))
			continue_execution()
			
		"输出":
			var var_name = node.get_value()["var_name"]
			if var_name.strip_edges().is_empty():
				add_terminal_line("错误：输出变量名不能为空")
				is_running = false
				return
				
			if not variables.has(var_name):
				add_terminal_line("错误：变量 " + var_name + " 未定义")
				is_running = false
				return
				
			add_terminal_line(var_name + " 的值为：" + str(variables[var_name]))
			continue_execution()
			
		"选择":
			var condition = node.get_value()["var_name"]
			if condition.strip_edges().is_empty():
				add_terminal_line("错误：条件表达式不能为空")
				is_running = false
				return
			
			# 创建表达式对象
			var expr = Expression.new()
			var error = expr.parse(condition, variables.keys())
			if error != OK:
				add_terminal_line("错误：条件无效 - " + condition)
				is_running = false
				return
			
			var result = expr.execute(variables.values())
			if expr.has_execute_failed():
				add_terminal_line("错误：条件执行失败 - " + condition)
				is_running = false
				return
			
			add_terminal_line("条件检查：" + condition + " = " + str(result))
			
			# 根据条件选择分支
			var connections = $WorkArea/VBoxContainer/GraphEdit.get_connection_list()
			var next_node = null
			
			if result:  # 条件为真，执行True分支（槽位2）
				for connection in connections:
					if connection["from_node"] == current_node.name and connection["from_port"] == 0:  # True分支（绿色）
						next_node = $WorkArea/VBoxContainer/GraphEdit.get_node(NodePath(connection["to_node"]))
						break
			else:  # 条件为假，执行False分支（槽位1）
				for connection in connections:
					if connection["from_node"] == current_node.name and connection["from_port"] == 1:  # False分支（红色）
						next_node = $WorkArea/VBoxContainer/GraphEdit.get_node(NodePath(connection["to_node"]))
						break
			
			if next_node:
				current_node = next_node
				execute_node(next_node)
			else:
				add_terminal_line("错误：找不到下一个要执行的节点")
				is_running = false
			
		"循环":
			var condition = node.get_value()["var_name"]
			if condition.strip_edges().is_empty():
				add_terminal_line("错误：循环条件不能为空")
				is_running = false
				return
			
			# 解析循环条件
			var expr = Expression.new()
			var error = expr.parse(condition, variables.keys())
			if error != OK:
				add_terminal_line("错误：循环条件无效 - " + condition)
				is_running = false
				return
			
			var result = expr.execute(variables.values())
			if expr.has_execute_failed():
				add_terminal_line("错误：循环条件执行失败 - " + condition)
				is_running = false
				return
			
			add_terminal_line("循环条件检查：" + condition + " = " + str(result))
			
			# 根据条件选择分支
			var connections = $WorkArea/VBoxContainer/GraphEdit.get_connection_list()
			var next_node = null
			
			if result:  # 条件为真，执行循环体
				for connection in connections:
					if connection["from_node"] == current_node.name and connection["from_port"] == 1:
						next_node = $WorkArea/VBoxContainer/GraphEdit.get_node(NodePath(connection["to_node"]))
						break
			else:  # 条件为假，执行输出分支
				for connection in connections:
					if connection["from_node"] == current_node.name and connection["from_port"] == 0:
						next_node = $WorkArea/VBoxContainer/GraphEdit.get_node(NodePath(connection["to_node"]))
						break
			
			if next_node:
				current_node = next_node
				execute_node(next_node)
			else:
				add_terminal_line("错误：找不到下一个要执行的节点")
				is_running = false
			
		"结束":
			is_running = false
			add_terminal_line("=== 程序执行结束 ===")
			return
			
		"字符串":
			var text = node.get_value()["var_name"]
			add_terminal_line(text)  # 直接在终端显示文本
			continue_execution()
			
		_:
			continue_execution()

func continue_execution():
	if not is_running:
		return
		
	# 获取当前节点的连接
	var connections = $WorkArea/VBoxContainer/GraphEdit.get_connection_list()
	var next_node = null
	
	# 检查当前节点的类型和连接
	for connection in connections:
		if connection["from_node"] == current_node.name:
			if connection["to_port"] == 2:  # 如果是连接到循环节点的循环体返回槽位
				next_node = $WorkArea/VBoxContainer/GraphEdit.get_node(NodePath(connection["to_node"]))
				break
			elif connection["from_port"] == 0:  # 普通连接
				next_node = $WorkArea/VBoxContainer/GraphEdit.get_node(NodePath(connection["to_node"]))
				break
	
	if next_node:
		current_node = next_node
		execute_node(next_node)
	else:
		is_running = false

func _on_graph_edit_gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				# 记录按下时的时间和位置
				right_click_start_time = Time.get_unix_time_from_system()
				drag_start_pos = event.position
				initial_scroll_offset = $WorkArea/VBoxContainer/GraphEdit.scroll_offset
			else:
				# 松开右键时
				var press_duration = Time.get_unix_time_from_system() - right_click_start_time
				var mouse_movement = (event.position - drag_start_pos).length()
				
				if press_duration < LONG_PRESS_TIME and mouse_movement < 5:
					# 短按，显示右键菜单
					popup_menu.position = get_viewport().get_mouse_position()
					popup_menu.popup()
				
				# 结束拖动状态
				is_dragging = false
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	
	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			# 如果右键按住且移动
			var current_duration = Time.get_unix_time_from_system() - right_click_start_time
			if current_duration >= LONG_PRESS_TIME:
				# 长按，进入拖动模式
				is_dragging = true
				Input.set_default_cursor_shape(Input.CURSOR_DRAG)
				# 计算拖动偏移量并更新滚动位置
				var delta = drag_start_pos - event.position
				$WorkArea/VBoxContainer/GraphEdit.scroll_offset = initial_scroll_offset + delta

func _on_popup_menu_item_selected(id: int):
	var node_type = popup_menu.get_item_text(id)
	# 使用相对于 GraphEdit 的鼠标位置
	var graph_pos = $WorkArea/VBoxContainer/GraphEdit.get_local_mouse_position()
	# 考虑滚动和缩放
	graph_pos = (graph_pos + $WorkArea/VBoxContainer/GraphEdit.scroll_offset) / $WorkArea/VBoxContainer/GraphEdit.zoom
	_create_node(node_type, graph_pos)

# 添加新的功能函数
func _on_minimap_button_toggled(button_pressed: bool):
	$WorkArea/VBoxContainer/GraphEdit.minimap_enabled = button_pressed
	_update_minimap_button_text(button_pressed)

func _update_minimap_button_text(is_enabled: bool):
	var minimap_button = $MenuBar/HBoxContainer/MinimapButton
	minimap_button.text = "关闭小地图" if is_enabled else "显示小地图"

func _on_help_button_pressed():
	var help_window = HelpWindow.instantiate()
	add_child(help_window)

# 添加保存和导入功能
func _on_save_button_pressed():
	var save_dialog = FileDialog.new()
	add_child(save_dialog)
	save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	save_dialog.filters = ["*.fw ; Flow Work Files"]
	save_dialog.current_path = "flow_work.fw"
	save_dialog.title = "保存流程图"
	
	save_dialog.file_selected.connect(func(path): _save_flow(path))
	save_dialog.popup_centered(Vector2(800, 600))

func _on_load_button_pressed():
	var load_dialog = FileDialog.new()
	add_child(load_dialog)
	load_dialog.access = FileDialog.ACCESS_FILESYSTEM
	load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	load_dialog.filters = ["*.fw ; Flow Work Files"]
	load_dialog.title = "导入流程图"
	
	load_dialog.file_selected.connect(func(path): _load_flow(path))
	load_dialog.popup_centered(Vector2(800, 600))

func _save_flow(path: String):
	var save_data = {
		"nodes": [],
		"connections": $WorkArea/VBoxContainer/GraphEdit.get_connection_list()
	}
	
	# 保存所有节点的信息
	for node in $WorkArea/VBoxContainer/GraphEdit.get_children():
		if node is GraphNode:
			var node_data = {
				"type": node.node_type,
				"position": {
					"x": node.position_offset.x,
					"y": node.position_offset.y
				},
				"name": node.name,
				"value": node.get_value()
			}
			save_data.nodes.append(node_data)
	
	# 将数据保存到文件
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data))
		add_terminal_line("流程图已保存到：" + path)
	else:
		add_terminal_line("错误：无法保存文件")

func _load_flow(path: String):
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		add_terminal_line("错误：无法打开文件")
		return
	
	var json_string = file.get_as_text()
	var json = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		add_terminal_line("错误：无法解析文件")
		return
	
	var data = json.data
	
	# 清除现有的节点和连接
	for node in $WorkArea/VBoxContainer/GraphEdit.get_children():
		if node is GraphNode and node.node_type != "开始":
			node.queue_free()
	
	# 保存节点名称映射
	var name_mapping = {}
	
	# 创建新节点
	for node_data in data.nodes:
		if node_data.type != "开始":  # 跳过开始节点，因为它已经存在
			var position = Vector2(
				float(node_data.position.x),
				float(node_data.position.y)
			)
			var node = _create_node(node_data.type, position)
			# 保存新旧节点名称的映射关系
			name_mapping[node_data.name] = node.name
			
			# 恢复节点的值
			if node_data.value.var_name:
				node.get_node("MainContent/InputContainer/VarNameInput").text = node_data.value.var_name
			if node_data.value.value:
				node.get_node("MainContent/InputContainer/ValueInput").text = node_data.value.value
	
	# 等待一帧确保所有节点都创建完成
	await get_tree().process_frame
	
	# 恢复连接，使用名称映射
	for connection in data.connections:
		var from_node = connection.from_node
		var to_node = connection.to_node
		
		# 如果节点名称在映射中，使用新的名称
		if from_node in name_mapping:
			from_node = name_mapping[from_node]
		if to_node in name_mapping:
			to_node = name_mapping[to_node]
		
		$WorkArea/VBoxContainer/GraphEdit.connect_node(
			from_node,
			connection.from_port,
			to_node,
			connection.to_port
		)
	
	add_terminal_line("流程图已导入：" + path)

# 添加新的功能函数
func _on_reset_button_pressed():
	# 重置功能与运行按钮相同
	_on_run_button_pressed()

func _on_copy_button_pressed():
	# 复制终端内容到剪贴板
	var terminal = $WorkArea/VBoxContainer/TerminalPanel/VBoxContainer/Terminal
	if not terminal.text.is_empty():
		DisplayServer.clipboard_set(terminal.text)
		# 可选：显示复制成功提示
		add_terminal_line("终端内容已复制到剪贴板")
