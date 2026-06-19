extends PathFollow3D

enum RoutePointType {
	BRAKE,
	STOP,
	CRUISE
}

@export var point_type : RoutePointType
