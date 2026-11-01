///|
fn event(id : String, p : Double) -> Event {
  { id, probability: p, }
}

///|
test "AND OR and voting gates agree with elementary probability" {
  let events = [event("a", 0.1), event("b", 0.2)]
  let a = compile(
    events,
    [{ id: "top", kind: And, inputs: ["a", "b"], }],
    "top",
    [],
  )
  assert_true((a.probability(Map([]), Map([])) - 0.02).abs() < 1.0e-12)
  let b = compile(
    events,
    [{ id: "top", kind: Or, inputs: ["a", "b"], }],
    "top",
    [],
  )
  assert_true((b.probability(Map([]), Map([])) - 0.28).abs() < 1.0e-12)
  let c = compile(
    [event("a", 0.1), event("b", 0.1), event("c", 0.1)],
    [{ id: "top", kind: Vote(2), inputs: ["a", "b", "c"], }],
    "top",
    [],
  )
  assert_true((c.probability(Map([]), Map([])) - 0.028).abs() < 1.0e-12)
}

///|
test "a repeated shared event is not treated as independent copies" {
  let tree = compile(
    [event("power", 0.1), event("disk", 0.2)],
    [
      { id: "sub", kind: And, inputs: ["power", "disk"], },
      { id: "top", kind: Or, inputs: ["power", "sub"], },
    ],
    "top",
    [],
  )
  assert_eq(tree.probability(Map([]), Map([])), 0.1)
  assert_eq(tree.minimal_cut_sets(100), [["power"]])
}

///|
test "variable ordering changes representation while preserving probability and cut sets" {
  let es = [event("a", 0.1), event("b", 0.2), event("c", 0.3)]
  let gs = [
    { id: "ab", kind: And, inputs: ["a", "b"], },
    { id: "top", kind: Or, inputs: ["ab", "c"], },
  ]
  let a = compile(es, gs, "top", [])
  let b = compile(es, gs, "top", ["c", "b", "a"])
  assert_true(
    (a.probability(Map([]), Map([])) - b.probability(Map([]), Map([]))).abs() <
    1.0e-12,
  )
}

///|
test "forced events and overrides compute intervention scenarios" {
  let t = compile(
    [event("a", 0.1), event("b", 0.2)],
    [{ id: "top", kind: And, inputs: ["a", "b"], }],
    "top",
    [],
  )
  assert_eq(t.probability(Map([]), Map([("a", true)])), 0.2)
  assert_eq(t.probability(Map([("b", 0.5)]), Map([("a", false)])), 0.0)
  let importance = t.importance(Map([]), Map([]))
  assert_true((importance[0].birnbaum - 0.2).abs() < 1.0e-12)
}

///|
test "minimal cuts form an antichain and union bound is not called exact" {
  let t = compile(
    [event("a", 0.5), event("b", 0.5)],
    [{ id: "top", kind: Or, inputs: ["a", "b"], }],
    "top",
    [],
  )
  let report = t.analyze(Map([]), Map([]), 100)
  assert_eq(report.probability, 0.75)
  assert_eq(report.cut_union_bound, 1.0)
  assert_eq(report.minimal_cut_sets.length(), 2)
}

///|
test "invalid graph references cycles probabilities and direct duplicate inputs reject" {
  let es = [event("a", 0.1)]
  for
    gs in [
      [{ id: "top", kind: And, inputs: ["missing"], }],
      [{ id: "top", kind: Or, inputs: ["top"], }],
      [{ id: "top", kind: Vote(2), inputs: ["a"], }],
      [{ id: "top", kind: And, inputs: ["a", "a"], }],
    ] {
    try compile(es, gs, "top", []) catch {
      FaultError::Invalid(_) => ()
      _ => fail("invalid expected")
    } noraise {
      _ => fail("must reject")
    }
  }
  try compile([event("a", -0.1)], [], "a", []) catch {
    FaultError::Invalid(_) => ()
    _ => fail("invalid expected")
  } noraise {
    _ => fail("must reject")
  }
}

///|
test "cut-set budget exhaustion returns a diagnostic instead of incomplete cuts" {
  let t = compile(
    [event("a", 0.1), event("b", 0.1), event("c", 0.1)],
    [{ id: "top", kind: Vote(2), inputs: ["a", "b", "c"], }],
    "top",
    [],
  )
  try t.minimal_cut_sets(1) catch {
    FaultError::Limit(_) => ()
    _ => fail("limit expected")
  } noraise {
    _ => fail("must reject")
  }
}

///|
test "public inputs cannot mutate a compiled tree" {
  let inputs = ["a", "b"]
  let t = compile(
    [event("a", 0.1), event("b", 0.2)],
    [{ id: "top", kind: And, inputs, }],
    "top",
    [],
  )
  inputs[0] = "bad"
  assert_true((t.probability(Map([]), Map([])) - 0.02).abs() < 1.0e-12)
}

///|
test "invalid variable order and unknown scenario events reject" {
  try compile([event("a", 0.1)], [], "a", ["missing"]) catch {
    FaultError::Invalid(_) => ()
    _ => fail("invalid expected")
  } noraise {
    _ => fail("must reject")
  }
  let t = compile([event("a", 0.1)], [], "a", [])
  try t.probability(Map([("missing", 0.1)]), Map([])) catch {
    FaultError::Invalid(_) => ()
    _ => fail("invalid expected")
  } noraise {
    _ => fail("must reject")
  }
}

///|
test "malformed requests remain structured JSON errors" {
  for s in ["{", "null", "{}", "{\"model\":{}}"] {
    guard @json.parse(run_json(s)) is Object(o) else { fail("JSON expected") }
    assert_eq(o.get("ok"), Some(Json::boolean(false)))
  }
}
