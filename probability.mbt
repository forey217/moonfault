///|
fn Tree::weights(
  self : Tree,
  overrides : Map[String, Double],
  forced : Map[String, Bool],
) -> Array[Double] raise FaultError {
  let known : Map[String, Bool] = Map([])
  for e in self.events {
    known[e.id] = true
  }
  for id, p in overrides {
    guard known.contains(id) else {
      raise Invalid("unknown probability override")
    }
    valid_probability(p)
  }
  for id, _ in forced {
    guard known.contains(id) else { raise Invalid("unknown conditioned event") }
  }
  self.events.map(e => {
    match forced.get(e.id) {
      Some(true) => 1.0
      Some(false) => 0.0
      None => overrides.get(e.id).unwrap_or(e.probability)
    }
  })
}

///|
fn Tree::evaluate(self : Tree, weights : Array[Double]) -> Double {
  let values = [0.0, 1.0]
  for i = 2; i < self.nodes.length(); i = i + 1 {
    let n = self.nodes[i]
    let p = weights[n.variable]
    values.push((1.0 - p) * values[n.low] + p * values[n.high])
  }
  values[self.root]
}

///|
pub fn Tree::probability(
  self : Tree,
  overrides : Map[String, Double],
  forced : Map[String, Bool],
) -> Double raise FaultError {
  self.evaluate(self.weights(overrides, forced))
}

///|
pub fn Tree::importance(
  self : Tree,
  overrides : Map[String, Double],
  forced : Map[String, Bool],
) -> Array[Importance] raise FaultError {
  ignore(self.probability(overrides, forced))
  self.events.map(e => {
    let failed = forced.copy()
    failed[e.id] = true
    let working = forced.copy()
    working[e.id] = false
    let if_failed = self.probability(overrides, failed)
    let if_working = self.probability(overrides, working)
    { event: e.id, if_failed, if_working, birnbaum: if_failed - if_working, }
  })
}
