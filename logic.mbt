///|
pub(all) enum Formula {
  EventRef(String)
  Constant(Bool)
  All(Array[Formula])
  Any(Array[Formula])
  Invert(Formula)
  Parity(Array[Formula])
  Equivalent(Formula, Formula)
  Implies(Formula, Formula)
  Between(Int32, Int32, Array[Formula])
} derive(Eq, @debug.Debug)

///|
pub extend Formula with Eq::{equal, not_equal}

///|
pub extend Formula with @debug.Debug::{to_repr}

///|
pub(all) struct HouseEvent {
  id : String
  value : Bool
} derive(Eq, @debug.Debug)

///|
pub extend HouseEvent with Eq::{equal, not_equal}

///|
pub extend HouseEvent with @debug.Debug::{to_repr}

///|
pub(all) struct FormulaGate {
  id : String
  formula : Formula
} derive(Eq, @debug.Debug)

///|
pub extend FormulaGate with Eq::{equal, not_equal}

///|
pub extend FormulaGate with @debug.Debug::{to_repr}

///|
pub(all) struct LogicModel {
  events : Array[Event]
  houses : Array[HouseEvent]
  gates : Array[FormulaGate]
  top : String
} derive(Eq, @debug.Debug)

///|
pub extend LogicModel with Eq::{equal, not_equal}

///|
pub extend LogicModel with @debug.Debug::{to_repr}

///|
priv struct LogicBuilder {
  manager : Manager
  roots : Map[String, Int32]
  gates : Map[String, Formula]
  visiting : Map[String, Bool]
  mut formulas : Int32
}

///|
fn LogicBuilder::reference(
  self : LogicBuilder,
  id : String,
  depth : Int32,
) -> Int32 raise FaultError {
  guard depth <= 128 else { raise Limit("gate/formula depth exceeds 128") }
  if self.roots.get(id) is Some(root) {
    return root
  }
  guard !self.visiting.contains(id) else {
    raise Invalid("gate cycle at " + id)
  }
  guard self.gates.get(id) is Some(formula) else {
    raise Invalid("unknown gate/event reference: " + id)
  }
  self.visiting[id] = true
  let root = self.formula(formula, depth + 1)
  self.visiting.remove(id)
  self.roots[id] = root
  root
}

///|
fn validate_arity(children : Array[Formula]) -> Unit raise FaultError {
  guard children.length() >= 1 && children.length() <= 64 else {
    raise Invalid("operator needs 1..64 operands")
  }
}

///|
fn LogicBuilder::formula(
  self : LogicBuilder,
  f : Formula,
  depth : Int32,
) -> Int32 raise FaultError {
  guard depth <= 128 else { raise Limit("gate/formula depth exceeds 128") }
  self.formulas = self.formulas + 1
  guard self.formulas <= 20000 else {
    raise Limit("at most 20000 formula occurrences")
  }
  let m = self.manager
  match f {
    EventRef(id) => self.reference(id, depth)
    Constant(value) => if value { 1 } else { 0 }
    Invert(x) => m.apply(2, self.formula(x, depth + 1), 1)
    Equivalent(a, b) =>
      m.apply(
        2,
        m.apply(2, self.formula(a, depth + 1), self.formula(b, depth + 1)),
        1,
      )
    Implies(a, b) =>
      m.apply(
        1,
        m.apply(2, self.formula(a, depth + 1), 1),
        self.formula(b, depth + 1),
      )
    All(children) | Any(children) | Parity(children) => {
      validate_arity(children)
      let (op, initial) = match f {
        All(_) => (0, 1)
        Any(_) => (1, 0)
        _ => (2, 0)
      }
      children.fold(init=initial, (result, child) => {
        m.apply(op, result, self.formula(child, depth + 1))
      })
    }
    Between(lo, hi, children) => {
      validate_arity(children)
      guard lo >= 0 && hi >= lo && hi <= children.length() else {
        raise Invalid("cardinality requires 0 <= min <= max <= arity")
      }
      let limit = if hi == children.length() { lo } else { hi + 1 }
      let dp = Array::make(limit + 1, 0)
      dp[0] = 1
      for child in children {
        let x = self.formula(child, depth + 1)
        for j = limit; j > 0; j = j - 1 {
          dp[j] = m.apply(1, dp[j], m.apply(0, x, dp[j - 1]))
        }
      }
      if hi == children.length() {
        dp[lo]
      } else {
        m.apply(0, dp[lo], m.apply(2, dp[hi + 1], 1))
      }
    }
  }
}

///|
/// Compiles a bounded static Boolean model. House events are constants, not random variables.
pub fn compile_logic(
  model : LogicModel,
  order : Array[String],
) -> Tree raise FaultError {
  guard model.events.length() <= 64 &&
    model.houses.length() <= 256 &&
    model.gates.length() <= 256 else {
    raise Limit("use at most 64 basic events, 256 house events and 256 gates")
  }
  let seen : Map[String, Bool] = Map([])
  let events : Map[String, Event] = Map([])
  let roots : Map[String, Int32] = Map([])
  let gates : Map[String, Formula] = Map([])
  let m = Manager::new()
  fn register(id : String) -> Unit raise FaultError {
    valid_id(id)
    guard !seen.contains(id) else {
      raise Invalid("duplicate declaration: " + id)
    }
    seen[id] = true
  }
  for e in model.events {
    register(e.id)
    valid_probability(e.probability)
    events[e.id] = e
  }
  for h in model.houses {
    register(h.id)
    roots[h.id] = if h.value { 1 } else { 0 }
  }
  for g in model.gates {
    register(g.id)
    gates[g.id] = g.formula
  }
  let ids = if order.length() == 0 {
    let xs = model.events.map(e => e.id)
    xs.sort()
    xs
  } else {
    order
  }
  guard ids.length() == events.length() else {
    raise Invalid("order must contain every basic event exactly once")
  }
  let ordered : Array[Event] = []
  for i, id in ids {
    guard !roots.contains(id) && events.get(id) is Some(e) else {
      raise Invalid("order must be a permutation of basic-event IDs")
    }
    ordered.push(e)
    roots[id] = m.make(i, 0, 1)
  }
  let builder : LogicBuilder = {
    manager: m,
    roots,
    gates,
    visiting: Map([]),
    formulas: 0,
  }
  for g in model.gates {
    ignore(builder.reference(g.id, 0))
  }
  let root = builder.reference(model.top, 0)
  { events: ordered, nodes: m.nodes, root, }
}
