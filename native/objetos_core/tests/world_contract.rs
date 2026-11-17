use sahur_object_world::world::*;

const DT: f32 = 1.0 / 60.0;
fn key(uid: u32) -> Key {
    Key::new(uid, 1).unwrap()
}
fn at(x: f32, y: f32, z: f32) -> rapier3d::prelude::Pose {
    pose([x, y, z], [0.0, 0.0, 0.0, 1.0]).unwrap()
}
fn scene(reverse: bool, seal: bool) -> ObjectWorld {
    let mut world = ObjectWorld::default();
    world
        .add_box(
            key(1),
            BoxSpec::new([10.0, 0.2, 10.0], 0.0),
            at(0.0, -0.1, 0.0),
        )
        .unwrap();
    for uid in if reverse { [3, 2] } else { [2, 3] } {
        let p = if uid == 2 {
            at(0.0, 0.2, 0.0)
        } else {
            pose([0.15, 1.0, 0.0], [0.0, 0.0, 0.1_f32.sin(), 0.1_f32.cos()]).unwrap()
        };
        world
            .add_box(key(uid), BoxSpec::new([0.6, 0.4, 0.4], 2.0), p)
            .unwrap();
    }
    if seal {
        world.seal(1).unwrap();
    }
    world
}
fn exact(a: &[Sample], b: &[Sample]) {
    assert_eq!(a.len(), b.len());
    for (x, y) in a.iter().zip(b) {
        assert_eq!(
            (x.key, x.tick, x.sleeping, x.held, &x.contacts),
            (y.key, y.tick, y.sleeping, y.held, &y.contacts)
        );
        let xb: Vec<_> = x
            .pose
            .iter()
            .chain(&x.linear)
            .chain(&x.angular)
            .map(|v| v.to_bits())
            .collect();
        let yb: Vec<_> = y
            .pose
            .iter()
            .chain(&y.linear)
            .chain(&y.angular)
            .map(|v| v.to_bits())
            .collect();
        assert_eq!(xb, yb, "body {:?} tick {}", x.key, x.tick);
    }
}
fn contact_checkpoint(w: &mut ObjectWorld) -> u64 {
    let mut observations = Vec::new();
    for _ in 0..120 {
        w.step(DT).unwrap();
        let a = w.sample(key(2)).unwrap();
        let b = w.sample(key(3)).unwrap();
        if w.tick() <= 35 {
            observations.push(format!(
                "{} A.y={:.5} B.y={:.5} B.v={:?} A.c={:?} B.c={:?}",
                w.tick(),
                a.pose[1],
                b.pose[1],
                b.linear,
                a.contacts,
                b.contacts
            ));
        }
        if a.contacts.contains(&key(3))
            && b.contacts.contains(&key(2))
            && b.linear.iter().any(|v| v.abs() > 0.1)
        {
            return w.cache_checkpoint().unwrap();
        }
    }
    panic!(
        "no moving dynamic contact in fixture: {}",
        observations.join("\n")
    );
}
fn branch(w: &mut ObjectWorld) -> Vec<Vec<Sample>> {
    (1..=360)
        .map(|n| {
            if n == 30 {
                w.impulse(key(2), [1.2, 0.0, 0.0]).unwrap();
            }
            if n == 240 {
                w.impulse(key(3), [0.6, 0.0, 0.0]).unwrap();
            }
            w.step(DT).unwrap();
            w.samples()
        })
        .collect()
}

#[test]
fn replay_active_contacts_sleep_and_wake_exactly() {
    let mut w = scene(false, true);
    let cp = contact_checkpoint(&mut w);
    let initial = w.samples();
    let checkpoint = w.snapshot().unwrap();
    let start = std::time::Instant::now();
    let reference = branch(&mut w);
    assert!(
        reference[..239]
            .iter()
            .any(|s| s.iter().filter(|v| v.key.uid > 1).all(|v| v.sleeping)),
        "must test sleep"
    );
    assert!(
        !reference[239]
            .iter()
            .find(|s| s.key == key(3))
            .unwrap()
            .sleeping,
        "must test wake"
    );
    w.restore_cached(cp).unwrap();
    exact(&initial, &w.samples());
    let repeated = branch(&mut w);
    for (a, b) in reference.iter().zip(&repeated) {
        exact(a, b);
    }
    w.restore_trusted(&checkpoint).unwrap();
    w.impulse(key(3), [-2.0, 0.0, 0.0]).unwrap();
    for _ in 0..90 {
        w.step(DT).unwrap();
    }
    assert_ne!(w.samples(), reference[89]);
    w.restore_trusted(&checkpoint).unwrap();
    for (a, b) in reference.iter().zip(branch(&mut w)) {
        exact(a, &b);
    }
    println!(
        "CONTACT_REPLAY checkpoint_tick={cp} bytes={} compared_steps=720 seconds={:.5}",
        checkpoint.len(),
        start.elapsed().as_secs_f64()
    );
}

#[test]
fn imported_handles_can_replace_different_creation_order() {
    let mut source = scene(false, true);
    contact_checkpoint(&mut source);
    let snapshot = source.snapshot().unwrap();
    let mut destination = scene(true, true);
    for _ in 0..40 {
        destination.step(DT).unwrap();
    }
    destination.restore_trusted(&snapshot).unwrap();
    exact(&source.samples(), &destination.samples());
    assert_eq!(
        source.ray([0.0, 3.0, 0.0], [0.0, -1.0, 0.0], 5.0).unwrap(),
        destination
            .ray([0.0, 3.0, 0.0], [0.0, -1.0, 0.0], 5.0)
            .unwrap()
    );
    let a = branch(&mut source);
    let b = branch(&mut destination);
    for (x, y) in a.iter().zip(b) {
        exact(x, &y);
    }
}

#[test]
fn restore_does_not_touch_another_world_or_reuse_its_ids() {
    let mut island = scene(false, true);
    let cp = contact_checkpoint(&mut island);
    let mut other = scene(false, false);
    let mut control = scene(false, false);
    for world in [&mut other, &mut control] {
        world
            .add_box(key(100), BoxSpec::new([0.4; 3], 1.0), at(2.0, 0.2, 0.0))
            .unwrap();
        for _ in 0..30 {
            world.step(DT).unwrap();
        }
    }
    for _ in 0..30 {
        island.step(DT).unwrap();
    }
    let before = other.samples();
    island.restore_cached(cp).unwrap();
    exact(&before, &other.samples());
    for world in [&mut other, &mut control] {
        world
            .add_box(key(101), BoxSpec::new([0.4; 3], 1.0), at(-2.0, 0.2, 0.0))
            .unwrap();
        assert_eq!(
            world
                .ray([2.0, 3.0, 0.0], [0.0, -1.0, 0.0], 5.0)
                .unwrap()
                .unwrap()
                .0,
            key(100)
        );
        world.remove(key(101)).unwrap();
        assert_eq!(
            world
                .ray([2.0, 3.0, 0.0], [0.0, -1.0, 0.0], 5.0)
                .unwrap()
                .unwrap()
                .0,
            key(100)
        );
        world.impulse(key(100), [3.0, 0.0, 0.0]).unwrap();
    }
    let initial_x = other.sample(key(100)).unwrap().pose[0];
    for _ in 0..120 {
        other.step(DT).unwrap();
        control.step(DT).unwrap();
        exact(&other.samples(), &control.samples());
    }
    assert!(other.sample(key(100)).unwrap().pose[0] - initial_x > 0.1);
}

#[test]
fn snapshot_rejection_is_atomic_for_manifest_context_and_damage() {
    let mut source = scene(false, true);
    contact_checkpoint(&mut source);
    let snapshot = source.snapshot().unwrap();
    let mut wrong = ObjectWorld::default();
    wrong
        .add_box(
            key(1),
            BoxSpec::new([10.0, 0.2, 10.0], 0.0),
            at(0.0, -0.1, 0.0),
        )
        .unwrap();
    wrong
        .add_box(
            key(2),
            BoxSpec::new([0.5, 0.4, 0.4], 2.0),
            at(0.0, 0.2, 0.0),
        )
        .unwrap();
    wrong
        .add_box(
            key(3),
            BoxSpec::new([0.6, 0.4, 0.4], 2.0),
            at(0.15, 1.0, 0.0),
        )
        .unwrap();
    wrong.seal(1).unwrap();
    let untouched = wrong.snapshot().unwrap();
    assert_eq!(
        wrong.restore_trusted(&snapshot),
        Err(Error("snapshot_manifest"))
    );
    assert_eq!(wrong.snapshot().unwrap(), untouched);
    let mut context = scene(false, false);
    context.seal(2).unwrap();
    let before = context.snapshot().unwrap();
    assert!(context.restore_trusted(&snapshot).is_err());
    assert_eq!(before, context.snapshot().unwrap());
    let mut good = scene(true, true);
    for bad in [
        snapshot[..20].to_vec(),
        {
            let mut b = snapshot.clone();
            b.push(0);
            b
        },
        {
            let mut b = snapshot.clone();
            *b.last_mut().unwrap() ^= 1;
            b
        },
    ] {
        let before = good.snapshot().unwrap();
        assert!(good.restore_trusted(&bad).is_err());
        assert_eq!(before, good.snapshot().unwrap());
    }
}

fn hand_action(w: &mut ObjectWorld, n: u64, omit_release: bool) {
    if n == 1 {
        w.begin_hold(key(2), [0.0; 3], at(-0.5, 0.7, 0.0)).unwrap();
    }
    if (2..=45).contains(&n) {
        w.set_goal(key(2), at(-0.5 + n as f32 * 0.003, 0.7, 0.0))
            .unwrap();
    }
    if n == 46 && !omit_release {
        w.release(key(2), [1.0, 0.6, 0.0]).unwrap();
    }
}
#[test]
fn hand_release_replayed_from_authority_checkpoint_converges() {
    let mut authority = scene(false, true);
    let mut predictor = scene(true, true);
    let mut checkpoint = Vec::new();
    for n in 1..=70 {
        hand_action(&mut authority, n, false);
        authority.step(DT).unwrap();
        hand_action(&mut predictor, n, true);
        predictor.step(DT).unwrap();
        if n == 40 {
            checkpoint = authority.snapshot().unwrap();
        }
    }
    assert_ne!(
        authority.sample(key(2)).unwrap().pose,
        predictor.sample(key(2)).unwrap().pose
    );
    predictor.restore_trusted(&checkpoint).unwrap();
    for n in 41..=70 {
        hand_action(&mut predictor, n, false);
        predictor.step(DT).unwrap();
    }
    exact(&authority.samples(), &predictor.samples());
    let before = predictor.samples();
    assert_eq!(
        predictor.release(key(2), [1.0, 0.6, 0.0]),
        Err(Error("not_held"))
    );
    exact(&before, &predictor.samples());
}

#[test]
fn cache_has_limits_and_discards_future_branch() {
    let mut w = scene(false, true);
    for _ in 0..135 {
        w.cache_checkpoint().unwrap();
        w.step(DT).unwrap();
    }
    assert_eq!(w.cache_stats().0, MAX_CACHED_TICKS);
    assert!(w.cache_stats().1 <= 16 * MAX_SNAPSHOT_BYTES);
    assert_eq!(w.restore_cached(0), Err(Error("checkpoint_expired")));
    w.restore_cached(100).unwrap();
    assert_eq!(w.tick(), 100);
    assert_eq!(w.restore_cached(130), Err(Error("checkpoint_expired")));
}

#[test]
fn invalid_calls_do_not_change_the_world() {
    let mut w = scene(false, true);
    let before = w.snapshot().unwrap();
    for dt in [0.0, -1.0, f32::NAN, 0.1] {
        assert!(w.step(dt).is_err());
    }
    assert!(
        w.begin_hold(key(2), [f32::NAN, 0.0, 0.0], at(0.0, 1.0, 0.0))
            .is_err()
    );
    assert!(w.impulse(key(2), [f32::INFINITY, 0.0, 0.0]).is_err());
    assert!(
        w.add_box(key(4), BoxSpec::new([0.4; 3], 1.0), at(2.0, 1.0, 0.0))
            .is_err()
    );
    assert!(w.remove(key(2)).is_err());
    assert_eq!(before, w.snapshot().unwrap());
    assert!(Key::new(0, 1).is_err());
    assert!(pose([0.0; 3], [0.0; 4]).is_err());
}

#[test]
fn authority_import_invalidates_old_prediction_cache() {
    let mut w = scene(false, true);
    w.cache_checkpoint().unwrap();
    let snapshot = w.snapshot().unwrap();
    w.step(DT).unwrap();
    w.cache_checkpoint().unwrap();
    assert_eq!(w.cache_stats().0, 2);
    w.restore_trusted(&snapshot).unwrap();
    assert_eq!(w.cache_stats(), (0, 0));
    assert_eq!(w.restore_cached(0), Err(Error("checkpoint_expired")));
}

#[test]
fn retired_identity_requires_a_new_epoch() {
    let mut w = ObjectWorld::default();
    w.add_box(key(2), BoxSpec::new([0.4; 3], 1.0), at(0.0, 1.0, 0.0))
        .unwrap();
    w.remove(key(2)).unwrap();
    assert_eq!(
        w.add_box(key(2), BoxSpec::new([0.4; 3], 1.0), at(0.0, 1.0, 0.0)),
        Err(Error("retired_identity"))
    );
    w.add_box(
        Key::new(2, 2).unwrap(),
        BoxSpec::new([0.4; 3], 1.0),
        at(0.0, 1.0, 0.0),
    )
    .unwrap();
    assert!(w.sample(key(2)).is_err());
}
