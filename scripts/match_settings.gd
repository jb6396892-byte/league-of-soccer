extends RefCounted
## Free matches select allied and opposing NPC profiles independently.
enum Difficulty { EASY, NORMAL, HARD }
const NAMES := ["简单", "一般", "困难"]
const PROFILES := [
	{"think": Vector2(0.45, 0.7), "skill": Vector2(0.5, 0.9), "tackle": Vector2(0.55, 0.9), "turn_speed": Vector2(120, 210), "turn_error": 10.0, "shot_error": 16.0, "pass_error": 10.0, "pressure": 0.75},
	{"think": Vector2(0.25, 0.45), "skill": Vector2(0.25, 0.55), "tackle": Vector2(0.3, 0.6), "turn_speed": Vector2(180, 300), "turn_error": 6.0, "shot_error": 10.0, "pass_error": 6.0, "pressure": 1.0},
	{"think": Vector2(0.16, 0.28), "skill": Vector2(0.16, 0.32), "tackle": Vector2(0.24, 0.42), "turn_speed": Vector2(230, 340), "turn_error": 3.0, "shot_error": 7.5, "pass_error": 4.0, "pressure": 1.15}
]
