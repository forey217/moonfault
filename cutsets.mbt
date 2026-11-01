///|
fn is_subset(a : Array[Int], b : Array[Int]) -> Bool {
  for x in a { if !b.contains(x) { return false } }
  true
}

///|
/// Exact minimal cut sets for the unconditioned coherent top event.
/// Intermediate antichains are bounded; exceeding budget raises Limit, never a partial success.
pub fn Tree::minimal_cut_sets(self : Tree, max_sets : Int) -> Array[Array[String]] raise FaultError {
  guard max_sets >= 1 && max_sets <= 5000 else { raise Invalid("cut-set budget must be 1..5000") }
  let cache : Map[Int, Array[Array[Int]]] = Map([(0, []), (1, [[]])])
  let work = Ref(0)
  fn visit(id : Int) -> Array[Array[Int]] raise FaultError {
    if cache.get(id) is Some(sets) { return sets }
    let n = self.nodes[id]
    let all = visit(n.low).copy()
    for rest in visit(n.high) { let set = [n.variable]; set.append(rest); all.push(set) }
    all.sort_by_key(s => s.length())
    let minimal : Array[Array[Int]] = []
    for set in all {
      let mut redundant = false
      for old in minimal {
        work.val = work.val + 1
        guard work.val <= 2000000 else { raise Limit("cut-set minimization exceeds 2000000 subset checks") }
        if is_subset(old, set) { redundant = true; break }
      }
      if !redundant {
        guard minimal.length() < max_sets else { raise Limit("cut-set antichain exceeds requested budget") }
        minimal.push(set)
      }
    }
    cache[id] = minimal
    minimal
  }
  visit(self.root).map(set => set.map(i => self.events[i].id))
}

///|
pub fn Tree::analyze(self : Tree, overrides : Map[String, Double], forced : Map[String, Bool], max_sets : Int) -> Analysis raise FaultError {
  let probability = self.probability(overrides, forced)
  let minimal_cut_sets = self.minimal_cut_sets(max_sets)
  let probabilities : Map[String, Double] = Map([])
  for e in self.events { probabilities[e.id] = overrides.get(e.id).unwrap_or(e.probability) }
  for id, value in forced { probabilities[id] = if value { 1.0 } else { 0.0 } }
  let mut cut_union_bound = 0.0
  for set in minimal_cut_sets {
    let mut product = 1.0
    for id in set { product = product * probabilities.get(id).unwrap_or(0.0) }
    cut_union_bound = cut_union_bound + product
  }
  { probability, importance: self.importance(overrides, forced), minimal_cut_sets, cut_union_bound: cut_union_bound.min(1.0), bdd_nodes: self.nodes.length(), basic_events: self.events.length() }
}
