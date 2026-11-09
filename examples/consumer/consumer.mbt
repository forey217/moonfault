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

///|
test "consumer imports MEF and evaluates signed primes and worth metrics" {
  let d = @lib.import_mef(
    "<opsa-mef><define-fault-tree name=\"FT\"><define-gate name=\"top\"><not><basic-event name=\"a\"/></not></define-gate></define-fault-tree><model-data><define-basic-event name=\"a\"><float value=\"0.2\"/></define-basic-event></model-data></opsa-mef>",
  )
  let t = d.compile("", Map([]), [])
  assert_true(t.prime_implicants(10)[0][0].failed == false)
  assert_true(t.risk_importance(Map([]), Map([]))[0].raw is @lib.Finite(0.0))
}
