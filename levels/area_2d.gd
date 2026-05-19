extends Area2D

@onready var LevelAnimationPlayer = $"../LevelAnimationPlayer"
var already_played = false



func _on_body_entered(body: CharacterBody2D) -> void:
	if !already_played :
		print("detected")
		LevelAnimationPlayer.play("Move")
	already_played= true


func _on_hitbox_area_entered(area: Area2D) -> void:
	already_played = false
	
	LevelAnimationPlayer.play("RESET")
