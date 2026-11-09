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
  } else if op == 1 {
    if a == 1 || b == 1 {
      return 1
    }
    if a == 0 {
      return b
    }
    if b == 0 {
      return a
    }
  } else {
    if a == 0 {
      return b
    }
    if b == 0 {
      return a
    }
    if a == b {
      return 0
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
/// Legacy flat coherent gate API. Use compile_logic for nested/nonmonotone models.
pub fn compile(
  events : Array[Event],
  gates : Array[Gate],
  top : String,
  order : Array[String],
) -> Tree raise FaultError {
  let gates = gates.map(g => {
    let seen : Map[String, Bool] = Map([])
    for id in g.inputs {
      guard !seen.contains(id) else {
        raise Invalid("duplicate direct gate input")
      }
      seen[id] = true
    }
    let inputs = g.inputs.map(id => EventRef(id))
    let formula = match g.kind {
      And => All(inputs)
      Or => Any(inputs)
      Vote(k) => {
        guard k > 0 else { raise Invalid("vote threshold must be positive") }
        Between(k, inputs.length(), inputs)
      }
    }
    { id: g.id, formula, }
  })
  compile_logic({ events, houses: [], gates, top, }, order)
}
