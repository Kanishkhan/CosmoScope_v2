# Shared constants for the XR layer (kept separate to avoid cyclic preloads).
extends RefCounted

const DESKTOP = 0
const VR = 1
const AR = 2


static func get_mode_name(mode: int) -> String:
	match mode:
		VR:
			return "VR"
		AR:
			return "AR"
	return "Desktop"
