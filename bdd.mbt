///|
fn Manager::new() -> Manager {
  {
    nodes: [
      { variable: 1000, low: 0, high: 0, },
      { variable: 1000, low: 1, high: 1, },
    ],
    unique: Map([]),
    cache: Map([]),
    work: 0,
  }
}

///|
fn Manager::make(
  self : Manager,
  variable : Int32,
  low : Int32,
  high : Int32,
) -> Int32 raise FaultError {
  if low == high {
    return low
  }
  let key = (variable, low, high)
  if self.unique.get(key) is Some(id) {
    return id
  }
  guard self.nodes.length() < 20000 else {
    raise Limit(
      "ROBDD exceeds 20000 nodes; change variable order or simplify model",
    )
  }
  let id = self.nodes.length()
  self.nodes.push({ variable, low, high, })
  self.unique[key] = id
  id
}

///|
fn Manager::apply(
  self : Manager,
  op : Int32,
  a : Int32,
  b : Int32,
) -> Int32 raise FaultError {
  self.work = self.work + 1
  guard self.work <= 2000000 else {
    raise Limit("BDD apply work exceeds 2000000 calls")
  }
  if op == 0 {
    if a == 0 || b == 0 {
      return 0
    }
    if a == 1 {
      return b
    }
    if b == 1 {
      return a
    }
  } else {
    if a == 1 || b == 1 {
      return 1
    }
    if a == 0 {
      return b
    }
    if b == 0 {
      return a
    }
  }
  if a == b {
    return a
  }
  let key = (op, a.min(b), a.max(b))
  if self.cache.get(key) is Some(id) {
    return id
  }
  let x = self.nodes[a]
  let y = self.nodes[b]
  let variable = x.variable.min(y.variable)
  let (al, ah) = if x.variable == variable { (x.low, x.high) } else { (a, a) }
  let (bl, bh) = if y.variable == variable { (y.low, y.high) } else { (b, b) }
  let low = self.apply(op, al, bl)
  let high = self.apply(op, ah, bh)
  let result = self.make(variable, low, high)
  self.cache[key] = result
  result
}

///|
fn build_gate(
  id : String,
  gates : Map[String, Gate],
  states : Map[String, Int32],
  roots : Map[String, Int32],
  manager : Manager,
  depth : Int32,
) -> Int32 raise FaultError {
  guard depth <= 128 else { raise Limit("gate dependency depth exceeds 128") }
  if roots.get(id) is Some(root) {
    return root
  }
  guard states.get(id) != Some(1) else { raise Invalid("gate cycle at " + id) }
  guard gates.get(id) is Some(gate) else {
    raise Invalid("unknown gate/event reference: " + id)
  }
  states[id] = 1
  let inputs = gate.inputs.map(child => {
    build_gate(child, gates, states, roots, manager, depth + 1)
  })
  let root = match gate.kind {
    And => inputs.fold(init=1, (a, b) => manager.apply(0, a, b))
    Or => inputs.fold(init=0, (a, b) => manager.apply(1, a, b))
    Vote(k) => {
      let dp = Array::make(k + 1, 0)
      dp[0] = 1
      for input in inputs {
        for j = k; j > 0; j = j - 1 {
          dp[j] = manager.apply(1, dp[j], manager.apply(0, input, dp[j - 1]))
        }
      }
      dp[k]
    }
  }
  states[id] = 2
  roots[id] = root
  root
}

///|
/// Compile a coherent AND/OR/k-of-n DAG. Repeated event references share one variable.
/// order is an exact permutation of event IDs, or [] for stable lexical ordering.
pub fn compile(
  events : Array[Event],
  gates : Array[Gate],
  top : String,
  order : Array[String],
) -> Tree raise FaultError {
  guard events.length() > 0 && events.length() <= 64 && gates.length() <= 256 else {
    raise Limit("use 1..64 events and at most 256 gates")
  }
  let names : Map[String, Bool] = Map([])
  let event_map : Map[String, Event] = Map([])
  for event in events {
    valid_id(event.id)
    valid_probability(event.probability)
    guard !names.contains(event.id) else {
      raise Invalid("duplicate event/gate id")
    }
    names[event.id] = true
    event_map[event.id] = event
  }
  let gs : Map[String, Gate] = Map([])
  for g in gates {
    valid_id(g.id)
    guard !names.contains(g.id) else {
      raise Invalid("duplicate event/gate id")
    }
    guard g.inputs.length() > 0 && g.inputs.length() <= 64 else {
      raise Invalid("gate needs 1..64 inputs")
    }
    if g.kind is Vote(k) {
      guard k > 0 && k <= g.inputs.length() else {
        raise Invalid("vote threshold must be 1..input count")
      }
    }
    let seen : Map[String, Bool] = Map([])
    for input in g.inputs {
      guard !seen.contains(input) else {
        raise Invalid("duplicate direct gate input")
      }
      seen[input] = true
    }
    names[g.id] = true
    gs[g.id] = { ..g, inputs: g.inputs.copy(), }
  }
  let ids = if order.length() == 0 {
    let ids = events.map(e => e.id)
    ids.sort()
    ids
  } else {
    order.copy()
  }
  guard ids.length() == events.length() else {
    raise Invalid("variable order must contain every event exactly once")
  }
  let seen : Map[String, Bool] = Map([])
  let ordered : Array[Event] = []
  let roots : Map[String, Int32] = Map([])
  let manager = Manager::new()
  for i, id in ids {
    guard !seen.contains(id) && event_map.get(id) is Some(event) else {
      raise Invalid("variable order must be a permutation of event IDs")
    }
    seen[id] = true
    ordered.push(event)
    roots[id] = manager.make(i, 0, 1)
  }
  let states : Map[String, Int32] = Map([])
  for gate in gates {
    ignore(build_gate(gate.id, gs, states, roots, manager, 0))
  }
  let root = build_gate(top, gs, states, roots, manager, 0)
  { events: ordered, nodes: manager.nodes, root, }
}
