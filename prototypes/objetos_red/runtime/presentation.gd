extends RefCounted

## Único selector de pose visible. No mueve el cuerpo físico.
const State := preload("res://runtime/state.gd")
const MAX_SAMPLES := 120

var samples: Array = []
var latest_revision := 0
var latest_epoch := 0
var shown := Transform3D.IDENTITY
var shown_tick := -1.0
var initialized := false

func accept(sample) -> bool:
	if not sample.valid():
		return false
	if sample.epoch < latest_epoch or (sample.epoch == latest_epoch and sample.revision < latest_revision):
		return false
	if sample.epoch != latest_epoch or sample.revision != latest_revision:
		samples.clear()
		latest_epoch = sample.epoch
		latest_revision = sample.revision
	if not samples.is_empty() and sample.tick <= samples.back().tick:
		return false
	samples.append(sample.copy())
	while samples.size() > MAX_SAMPLES:
		samples.pop_front()
	return true

func at(tick: float):
	if samples.is_empty():
		return null
	var before = samples.front()
	var after = samples.back()
	for s in samples:
		if s.tick <= tick:
			before = s
		if s.tick >= tick:
			after = s
			break
	var result = before.copy()
	if after.tick > before.tick:
		var fraction := clampf((tick - before.tick) / float(after.tick - before.tick), 0.0, 1.0)
		result.pose = before.pose.interpolate_with(after.pose, fraction)
		result.lv = before.lv.lerp(after.lv, fraction)
		result.av = before.av.lerp(after.av, fraction)
	return result

func remote(tick: float):
	var sample = at(maxf(tick, shown_tick))
	if sample == null:
		return null
	shown = sample.pose
	shown_tick = maxf(shown_tick, minf(tick, float(samples.back().tick)))
	initialized = true
	return sample

func predicted(pose: Transform3D, tick: int) -> Transform3D:
	shown = pose
	shown_tick = maxf(shown_tick, float(tick))
	initialized = true
	return shown

func can_handoff(sample, local_sleeping: bool, remote_tick: float) -> bool:
	# Primer candidato deliberadamente conservador: no devolver un cuerpo en
	# vuelo al pasado. Se espera reposo autorizado y que el buffer lo alcance.
	return sample != null and sample.sleeping and local_sleeping and remote_tick >= sample.tick \
		and sample.epoch == latest_epoch and sample.revision == latest_revision
