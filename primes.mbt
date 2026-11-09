///|
pub(all) struct Literal {
  event : String
  failed : Bool
} derive(Eq, ToJson, @debug.Debug)

///|
pub extend Literal with Eq::{equal, not_equal}

///|
pub extend Literal with ToJson::{to_json}

///|
pub extend Literal with @debug.Debug::{to_repr}

///|
priv struct Cube {
  positive : UInt64
  negative : UInt64
}

///|
fn Cube::size(self : Cube) -> Int32 {
  self.positive.popcnt() + self.negative.popcnt()
}

///|
fn Cube::subsumes(self : Cube, other : Cube) -> Bool {
  (self.positive & other.positive) == self.positive &&
  (self.negative & other.negative) == self.negative
}

///|
fn Tree::prime_cubes(
  self : Tree,
  budget : Int32,
) -> Array[Cube] raise FaultError {
  guard budget >= 1 && budget <= 5000 else {
    raise Invalid("prime/cut antichain budget must be 1..5000")
  }
  // New conjunctions can be needed for consensus terms. Never mutate the original BDD.
  let manager : Manager = {
    nodes: self.nodes.copy(),
    unique: Map([]),
    cache: Map([]),
    work: 0,
  }
  for i = 2; i < self.nodes.length(); i = i + 1 {
    let n = self.nodes[i]
    manager.unique[(n.variable, n.low, n.high)] = i
  }
  let memo : Map[Int32, Array[Cube]] = Map([
    (0, []),
    (1, [{ positive: 0UL, negative: 0UL, }]),
  ])
  let checks = Ref(0)
  let stored = Ref(0)
  fn visit(id : Int32) -> Array[Cube] raise FaultError {
    if memo.get(id) is Some(result) {
      return result
    }
    let node = manager.nodes[id]
    // Primes omitting x are precisely the primes of f[x=0] AND f[x=1].
    // A prime mentioning x must reduce to a prime of its chosen cofactor.
    // Subsumption removes candidates for which the x literal is unnecessary.
    let common = manager.apply(0, node.low, node.high)
    let all = visit(common).copy()
    let bit = 1UL << node.variable
    for term in visit(node.low) {
      all.push({ ..term, negative: term.negative | bit, })
    }
    for term in visit(node.high) {
      all.push({ ..term, positive: term.positive | bit, })
    }
    all.sort_by_key(term => (term.size(), term.positive, term.negative))
    let minimal : Array[Cube] = []
    for term in all {
      let mut discard = false
      for accepted in minimal {
        checks.val = checks.val + 1
        guard checks.val <= 4000000 else {
          raise Limit("prime enumeration exceeds 4000000 subsumption checks")
        }
        if accepted.subsumes(term) {
          discard = true
          break
        }
      }
      if !discard {
        guard minimal.length() < budget else {
          raise Limit("prime/cut antichain exceeds requested budget")
        }
        minimal.push(term)
      }
    }
    stored.val = stored.val + minimal.length()
    guard stored.val <= 250000 else {
      raise Limit("prime cache exceeds 250000 cubes")
    }
    memo[id] = minimal
    minimal
  }
  visit(self.root)
}

///|
fn Tree::literals(self : Tree, cube : Cube) -> Array[Literal] {
  let out : Array[Literal] = []
  for i, e in self.events {
    let bit = 1UL << i
    if (cube.positive & bit) != 0UL {
      out.push({ event: e.id, failed: true, })
    }
    if (cube.negative & bit) != 0UL {
      out.push({ event: e.id, failed: false, })
    }
  }
  out
}

///|
/// Returns every prime, including consensus primes, or raises on budget exhaustion.
/// [] means false; [[]] means true (one empty implicant).
pub fn Tree::prime_implicants(
  self : Tree,
  budget : Int32,
) -> Array[Array[Literal]] raise FaultError {
  self.prime_cubes(budget).map(cube => self.literals(cube))
}
