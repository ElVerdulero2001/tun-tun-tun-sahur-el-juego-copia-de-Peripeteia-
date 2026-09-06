class_name TraversalState
extends RefCounted

## Estados de la máquina de traversal (Parkour V2 — doc de arquitectura V0.3,
## sección 6). Vive como tipo separado porque TraversalContext, y más
## adelante TraversalController y TraversalDebug, necesitan referenciar el
## mismo enum sin duplicarlo.

enum Value { FREE, ACQUIRE_LEDGE, HANGING, MANTLING, LADDER }
