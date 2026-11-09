///|
fn formula_references(f : Formula, out : Array[String]) -> Unit {
  match f {
    EventRef(id) => out.push(id)
    Constant(_) => ()
    Invert(x) => formula_references(x, out)
    Equivalent(a, b) | Implies(a, b) => {
      formula_references(a, out)
      formula_references(b, out)
    }
    All(xs) | Any(xs) | Parity(xs) | Between(_, _, xs) =>
      for x in xs {
        formula_references(x, out)
      }
  }
}

///|
fn write_formula(
  w : @xml.Writer,
  f : Formula,
  kinds : Map[String, String],
) -> Unit raise @xml.WriterError {
  match f {
    EventRef(id) => w.empty_element(kinds[id], [("name", id)])
    Constant(x) => w.empty_element("constant", [("value", x.to_string())])
    Invert(x) => {
      w.start_element("not", [])
      write_formula(w, x, kinds)
      w.end_element("not")
    }
    Equivalent(a, b) | Implies(a, b) => {
      let tag = if f is Equivalent(_, _) { "iff" } else { "imply" }
      w.start_element(tag, [])
      write_formula(w, a, kinds)
      write_formula(w, b, kinds)
      w.end_element(tag)
    }
    All(xs) | Any(xs) | Parity(xs) | Between(_, _, xs) => {
      let (tag, attrs) = match f {
        All(_) => ("and", [])
        Any(_) => ("or", [])
        Parity(_) => ("xor", [])
        Between(lo, hi, _) if lo > 0 && hi == xs.length() =>
          ("atleast", [("min", lo.to_string())])
        Between(lo, hi, _) =>
          ("cardinality", [("min", lo.to_string()), ("max", hi.to_string())])
        _ => ("and", [])
      }
      w.start_element(tag, attrs)
      for x in xs {
        write_formula(w, x, kinds)
      }
      w.end_element(tag)
    }
  }
}

///|
/// Exports the selected top and its reachable gates to a flat Open-PSA MEF document.
/// All identifiers must be portable, unqualified MEF names.
pub fn export_mef(
  model : LogicModel,
  tree_name : String,
) -> String raise FaultError {
  validate_mef_name(tree_name)
  ignore(compile_logic(model, []))
  let kinds : Map[String, String] = Map([])
  let gs : Map[String, Formula] = Map([])
  for e in model.events {
    validate_mef_name(e.id)
    kinds[e.id] = "basic-event"
  }
  for h in model.houses {
    validate_mef_name(h.id)
    kinds[h.id] = "house-event"
  }
  for g in model.gates {
    validate_mef_name(g.id)
    kinds[g.id] = "gate"
    gs[g.id] = g.formula
  }
  // The tree container and global model-data identifiers share a namespace.
  guard !kinds.contains(tree_name) else {
    raise Invalid("MEF tree name collides with an event or gate ID")
  }
  let reachable : Map[String, Bool] = Map([])
  fn visit(id : String) -> Unit {
    if reachable.contains(id) {
      return
    }
    reachable[id] = true
    if gs.get(id) is Some(f) {
      let refs : Array[String] = []
      formula_references(f, refs)
      for ref_id in refs {
        visit(ref_id)
      }
    }
  }
  visit(model.top)
  try {
    let w = @xml.Writer::new()
    w.start_element("opsa-mef", [])
    w.start_element("define-fault-tree", [("name", tree_name)])
    for g in model.gates {
      if !reachable.contains(g.id) {
        continue
      }
      valid_id(qualify(tree_name, g.id))
      w.start_element("define-gate", [("name", g.id)])
      write_formula(w, g.formula, kinds)
      w.end_element("define-gate")
    }
    if !gs.contains(model.top) {
      let mut id = "MoonFaultTop"
      let mut suffix = 0
      while kinds.contains(id) || id == tree_name {
        suffix = suffix + 1
        id = "MoonFaultTop" + suffix.to_string()
      }
      valid_id(qualify(tree_name, id))
      w.start_element("define-gate", [("name", id)])
      write_formula(w, EventRef(model.top), kinds)
      w.end_element("define-gate")
    }
    w.end_element("define-fault-tree")
    if !model.events.is_empty() || !model.houses.is_empty() {
      w.start_element("model-data", [])
      for e in model.events {
        w.start_element("define-basic-event", [("name", e.id)])
        w.empty_element("float", [("value", e.probability.to_string())])
        w.end_element("define-basic-event")
      }
      for h in model.houses {
        w.start_element("define-house-event", [("name", h.id)])
        w.empty_element("constant", [("value", h.value.to_string())])
        w.end_element("define-house-event")
      }
      w.end_element("model-data")
    }
    w.end_element("opsa-mef")
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" + w.to_string() + "\n"
  } catch {
    _ => raise Invalid("could not encode the model as MEF XML")
  }
}
