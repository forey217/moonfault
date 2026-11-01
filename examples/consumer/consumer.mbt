///|
pub fn probability() -> Double raise @lib.FaultError {
  let t = @lib.compile(
    [{ id: "power", probability: 0.02, }, { id: "disk", probability: 0.1, }],
    [{ id: "failed", kind: @lib.Or, inputs: ["power", "disk"], }],
    "failed",
    [],
  )
  t.probability(Map([]), Map([]))
}

///|
test "consumer evaluates a failure model through the public package" {
  assert_true((probability() - 0.118).abs() < 1.0e-12)
}
