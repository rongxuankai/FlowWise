extends AcceptDialog

func _ready():
	# 等待一帧确保所有节点都准备好
	await get_tree().process_frame
	popup_centered()
