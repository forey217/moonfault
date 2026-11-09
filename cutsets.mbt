///|
/// Returns the complete positive minimal cut sets, rejecting nonmonotone models.
pub fn Tree::minimal_cut_sets(
  self : Tree,
  max_sets : Int32,
) -> Array[Array[String]] raise FaultError {
  let cubes = self.prime_cubes(max_sets)
  guard !cubes.any(c => c.negative != 0UL) else {
    raise Invalid(
      "nonmonotone model: use prime_implicants instead of minimal_cut_sets",
    )
  }
  cubes.map(c => self.literals(c).map(x => x.event))
}

///|
pub fn Tree::analyze(
  self : Tree,
  overrides : Map[String, Double],
  forced : Map[String, Bool],
  max_sets : Int32,
) -> Analysis raise FaultError {
  let probability = self.probability(overrides, forced)
  let minimal_cut_sets = self.minimal_cut_sets(max_sets)
  let probabilities : Map[String, Double] = Map([])
  for e in self.events {
    probabilities[e.id] = overrides.get(e.id).unwrap_or(e.probability)
  }
  for id, value in forced {
    probabilities[id] = if value { 1.0 } else { 0.0 }
  }
  let mut cut_union_bound = 0.0
  for set in minimal_cut_sets {
    let mut product = 1.0
    for id in set {
      product = product * probabilities.get(id).unwrap_or(0.0)
    }
    cut_union_bound = cut_union_bound + product
  }
  {
    probability,
    importance: self.importance(overrides, forced),
    minimal_cut_sets,
    cut_union_bound: cut_union_bound.min(1.0),
    bdd_nodes: self.nodes.length(),
    basic_events: self.events.length(),
  }
}
