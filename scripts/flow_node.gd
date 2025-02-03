extends GraphNode

var node_type: String = ""
var style_colors = {
	"输入": Color(0.2, 0.6, 1.0, 0.7),
	"输出": Color(0.2, 0.8, 0.2, 0.7),
	"赋值": Color(0.8, 0.8, 0.2, 0.7),
	"选择": Color(0.8, 0.4, 0.2, 0.7),
	"循环": Color(0.6, 0.2, 0.8, 0.7),
	"开始": Color(0.2, 0.8, 0.4, 0.7),
	"结束": Color(0.8, 0.2, 0.2, 0.7),
	"字符串": Color(0.4, 0.6, 0.8, 0.7)
}

func _ready():
	await get_tree().process_frame
	_update_style()

func _update_style():
	if node_type in style_colors:
		var style = get_theme_stylebox("frame").duplicate()
		style.bg_color = style_colors[node_type]
		add_theme_stylebox_override("frame", style)
		
		title = node_type
		$MainContent/Label.text = node_type
		
		# 隐藏所有额外的内容
		$MainContent/InputContainer.visible = false
		$TrueBranch.visible = false
		$FalseBranch.visible = false
		
		# 禁用所有槽位
		for i in range(3):  # 主内容、True分支、False分支
			set_slot_enabled_left(i, false)
			set_slot_enabled_right(i, false)
		
		match node_type:
			"开始":
				# 只有一个右侧输出
				set_slot_enabled_right(0, true)
			"结束":
				# 只有一个左侧输入
				set_slot_enabled_left(0, true)
			"输入":
				# 一个输入框，一个输入和一个输出
				set_slot_enabled_left(0, true)
				set_slot_enabled_right(0, true)
				$MainContent/InputContainer.visible = true
				$MainContent/InputContainer/ValueInput.visible = false
				$MainContent/InputContainer/VarNameInput.placeholder_text = "变量名"
			"输出":
				# 一个输入框，一个输入和一个输出
				set_slot_enabled_left(0, true)
				set_slot_enabled_right(0, true)
				$MainContent/InputContainer.visible = true
				$MainContent/InputContainer/ValueInput.visible = false
				$MainContent/InputContainer/VarNameInput.placeholder_text = "变量名"
			"赋值":
				# 两个输入框，一个输入和一个输出
				set_slot_enabled_left(0, true)
				set_slot_enabled_right(0, true)
				$MainContent/InputContainer.visible = true
				$MainContent/InputContainer/VarNameInput.placeholder_text = "变量名"
				$MainContent/InputContainer/ValueInput.placeholder_text = "表达式"
			"选择":
				# 左侧一个输入，右侧两个输出
				set_slot_enabled_left(0, true)  # 主内容的输入
				$MainContent/InputContainer.visible = true
				$MainContent/InputContainer/ValueInput.visible = false
				$MainContent/InputContainer/VarNameInput.placeholder_text = "条件表达式"
				
				# 显示分支并启用它们的输出槽位
				$TrueBranch.visible = true
				$FalseBranch.visible = true
				set_slot_enabled_right(1, true)  # True分支的输出
				set_slot_enabled_right(0, true)  # False分支的输出
				set_slot_color_right(1, Color(0.8, 0.2, 0.2))  # 绿色表示True
				set_slot_color_right(0, Color(0.2, 0.8, 0.2))  # 红色表示False
				
			"循环":
				# 左侧一个输入，右侧两个输出，循环体有一个输入
				set_slot_enabled_left(0, true)  # 主内容的输入
				$MainContent/InputContainer.visible = true
				$MainContent/InputContainer/ValueInput.visible = false
				$MainContent/InputContainer/VarNameInput.placeholder_text = "循环条件"
				
				# 显示分支并启用它们的输出槽位
				$TrueBranch.visible = true
				$TrueBranch/Label.text = "输出"
				$FalseBranch.visible = true
				$FalseBranch/Label.text = "循环体"
				
				# 设置槽位
				set_slot_enabled_right(0, true)  # 主输出
				set_slot_enabled_right(1, true)  # 循环体输出
				set_slot_enabled_left(1, true)   # 循环体返回
				
				set_slot_color_right(0, Color(1, 1, 1))  # 白色表示主输出
				set_slot_color_right(1, Color(0.6, 0.4, 0.8))  # 紫色表示循环体
				set_slot_color_left(1, Color(0.6, 0.4, 0.8))   # 循环体返回也用紫色
			"字符串":
				# 只有一个输入和一个输出
				set_slot_enabled_left(0, true)
				set_slot_enabled_right(0, true)
				$MainContent/InputContainer.visible = true
				$MainContent/InputContainer/ValueInput.visible = false
				$TrueBranch.visible = false
				$FalseBranch.visible = false
				$MainContent/InputContainer/VarNameInput.placeholder_text = "输入文本"

# 获取节点的值（用于执行）
func get_value() -> Dictionary:
	var data = {
		"type": node_type,
		"var_name": $MainContent/InputContainer/VarNameInput.text,
		"value": $MainContent/InputContainer/ValueInput.text if $MainContent/InputContainer/ValueInput.visible else ""
	}
	return data 
