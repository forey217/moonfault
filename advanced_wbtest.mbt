///|
test "consensus terms are required in addition to signed BDD paths" {
  let model : LogicModel = {
    events: [
      { id: "x", probability: 0.2, },
      { id: "a", probability: 0.1, },
      { id: "b", probability: 0.4, },
    ],
    houses: [],
    gates: [
      {
        id: "top",
        formula: Any([
          All([EventRef("x"), EventRef("a")]),
          All([Invert(EventRef("x")), EventRef("b")]),
        ]),
      },
    ],
    top: "top",
  }
  let t = compile_logic(model, ["x", "a", "b"])
  let ps = t.prime_implicants(50)
  assert_eq(ps.length(), 3)
  assert_true(
    ps.contains([{ event: "a", failed: true, }, { event: "b", failed: true, }]),
  )
  assert_true(
    ps.contains([{ event: "x", failed: false, }, { event: "b", failed: true, }]),
  )
  try t.minimal_cut_sets(50) catch {
    FaultError::Invalid(_) => ()
    _ => fail("expected nonmonotone diagnostic")
  } noraise {
    _ => fail("cannot treat primes as positive cuts")
  }
}

///|
test "constant true and false have distinct complete prime families" {
  let t = compile_logic(
    {
      events: [],
      houses: [{ id: "mode", value: true, }],
      gates: [],
      top: "mode",
    },
    [],
  )
  let f = compile_logic(
    {
      events: [],
      houses: [{ id: "mode", value: false, }],
      gates: [],
      top: "mode",
    },
    [],
  )
  assert_eq(t.prime_implicants(1), [[]])
  assert_eq(f.prime_implicants(1), [])
  assert_eq(t.probability(Map([]), Map([])), 1.0)
}

///|
test "signed cubes distinguish the highest UInt64 variable from bit zero" {
  let events = Array::makei(64, i => Event::{
    id: "e" + i.to_string(),
    probability: 0.5,
  })
  let t = compile_logic(
    {
      events,
      houses: [],
      gates: [
        { id: "top", formula: All([EventRef("e0"), Invert(EventRef("e63"))]), },
      ],
      top: "top",
    },
    events.map(e => e.id),
  )
  assert_eq(t.prime_implicants(5), [
    [{ event: "e0", failed: true, }, { event: "e63", failed: false, }],
  ])
  assert_eq(t.probability(Map([]), Map([])), 0.25)
}

///|
test "risk ratios separate zero-risk undefined values from unbounded risk" {
  let t = compile([{ id: "a", probability: 0.0, }], [], "a", [])
  let zero = t.risk_importance(Map([]), Map([]))[0]
  assert_eq(zero.fussell_vesely, Undefined)
  assert_eq(zero.raw, Unbounded)
  assert_eq(zero.rrw, Undefined)
  let positive = t.risk_importance(Map([("a", 0.2)]), Map([]))[0]
  assert_eq(positive.fussell_vesely, Finite(1.0))
  assert_eq(positive.raw, Finite(5.0))
  assert_eq(positive.rrw, Unbounded)
}

///|
test "nonmonotone importance can be negative or below one" {
  let t = compile_logic(
    {
      events: [{ id: "a", probability: 0.25, }],
      houses: [],
      gates: [{ id: "top", formula: Invert(EventRef("a")), }],
      top: "top",
    },
    [],
  )
  let r = t.risk_importance(Map([]), Map([]))[0]
  assert_eq(r.birnbaum, -1.0)
  assert_eq(r.fussell_vesely, Finite(-1.0 / 3.0))
  assert_eq(r.raw, Finite(0.0))
  assert_eq(r.rrw, Finite(0.75))
  assert_eq(r.scram_dif, Finite(0.0))
}

///|
test "MEF keeps missing probabilities explicit and can bind them at analysis time" {
  let d = import_mef(
    "<opsa-mef><define-fault-tree name=\"FT\"><define-gate name=\"top\"><basic-event name=\"a\"/></define-gate></define-fault-tree><model-data><define-basic-event name=\"a\"/></model-data></opsa-mef>",
  )
  assert_eq(d.top_events(), ["FT.top"])
  assert_eq(d.missing_probabilities(), ["a"])
  assert_eq(import_mef(d.to_xml()).missing_probabilities(), ["a"])
  try d.compile("", Map([]), []) catch {
    FaultError::Invalid(_) => ()
    _ => fail("missing probability expected")
  } noraise {
    _ => fail("must not invent a default")
  }
  assert_eq(
    d.compile("", Map([("a", 0.2)]), []).probability(Map([]), Map([])),
    0.2,
  )
}

///|
test "flat export keeps the selected top and discards unrelated gate roots" {
  let m : LogicModel = {
    events: [{ id: "a", probability: 0.1, }],
    houses: [],
    gates: [
      { id: "g", formula: Invert(EventRef("a")), },
      { id: "unused", formula: Constant(true), },
    ],
    top: "g",
  }
  let d = import_mef(export_mef(m, "T"))
  assert_eq(d.top_events(), ["T.g"])
  assert_eq(d.compile("", Map([]), []).probability(Map([]), Map([])), 0.9)
}
