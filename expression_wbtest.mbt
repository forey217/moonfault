///|
fn expression_test_probability(expr : String) -> Double raise FaultError {
  let source = "<opsa-mef><define-fault-tree name=\"T\"><define-gate name=\"top\"><basic-event name=\"a\"/></define-gate></define-fault-tree><model-data><define-basic-event name=\"a\">" +
    expr +
    "</define-basic-event></model-data></opsa-mef>"
  import_mef(source).compile("", Map([]), []).probability(Map([]), Map([]))
}

///|
test "MEF stable time distributions and Boolean condition across backends" {
  let p = expression_test_probability(
    "<exponential><float value=\"1e-20\"/><int value=\"1\"/></exponential>",
  )
  assert_true((p / 1.0e-20 - 1.0).abs() < 1.0e-12)
  assert_eq(
    expression_test_probability(
      "<GLM><float value=\"0.3\"/><float value=\"1e308\"/><float value=\"1e308\"/><int value=\"0\"/></GLM>",
    ),
    0.3,
  )
  assert_eq(
    expression_test_probability(
      "<GLM><float value=\"0.3\"/><float value=\"1e308\"/><float value=\"1e308\"/><int value=\"1\"/></GLM>",
    ),
    0.5,
  )
  assert_eq(
    expression_test_probability(
      "<ite><bool value=\"true\"/><float value=\"0.25\"/><div><int value=\"1\"/><int value=\"0\"/></div></ite>",
    ),
    0.25,
  )
  let w = expression_test_probability(
    "<Weibull><float value=\"1e300\"/><float value=\"0.1\"/><int value=\"0\"/><float value=\"1e-300\"/></Weibull>",
  )
  assert_true((w / 1.0e-60 - 1.0).abs() < 1.0e-12)
}

///|
test "MEF mathematical functions have consistent scalar values across targets" {
  assert_eq(
    expression_test_probability(
      "<div><int value=\"4294967296\"/><float value=\"8589934592\"/></div>",
    ),
    0.5,
  )
  let p = expression_test_probability(
    "<div><acos><int value=\"0\"/></acos><pi/></div>",
  )
  assert_true((p - 0.5).abs() < 1.0e-14)
  assert_eq(
    expression_test_probability(
      "<div><mean><float value=\"1e308\"/><float value=\"1e308\"/></mean><float value=\"1e308\"/></div>",
    ),
    1.0,
  )
  assert_eq(
    expression_test_probability(
      "<neg><mod><float value=\"-0.5\"/><int value=\"2\"/></mod></neg>",
    ),
    0.5,
  )
}

///|
test "MEF arithmetic catches invalid intermediate even if final value looks usable" {
  try
    expression_test_probability(
      "<div><float value=\"1e308\"/><float value=\"1e-308\"/><float value=\"1e308\"/></div>",
    )
  catch {
    FaultError::Invalid(_) => ()
    _ => fail("expected numerical error")
  } noraise {
    _ => fail("overflow must not become an apparent probability")
  }
  try
    expression_test_probability(
      "<ite><bool value=\"true\"/><float value=\"0.2\"/><parameter name=\"missing\"/></ite>",
    )
  catch {
    FaultError::Invalid(_) => ()
    _ => fail("expected unknown reference error")
  } noraise {
    _ => fail("dead branch must still be structurally validated")
  }
}
