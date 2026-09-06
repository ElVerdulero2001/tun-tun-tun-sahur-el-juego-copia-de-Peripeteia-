class_name TraversalDecision
extends RefCounted

## Salida pura de TraversalResolver (doc de arquitectura V0.3, sección 5).
## NONE significa "sin decisión" — el resolver no interrumpe FREE — no un error.

enum Value { NONE, ACQUIRE_LEDGE, ENTER_LADDER }
