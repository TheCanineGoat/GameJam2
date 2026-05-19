extends Area2D

const FILE_BEGIN ="res://levels/world_"


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("Player"):
		print("door Collided with Playeer")
		var current_scene_file = get_tree().current_scene.scene_file_path
		print(current_scene_file)
		
		##Level switch
		var next_level_number = current_scene_file.to_int()+1
		print(next_level_number)
		var next_level_path = FILE_BEGIN +str(next_level_number)+".tscn"
		print(next_level_path)
		get_tree().change_scene_to_file(next_level_path)
		print("Level 2")
