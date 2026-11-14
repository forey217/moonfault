///|
priv struct Declaration {
  path : String
  scope : String
  category : String
  body : Array[XmlNode]
  source : XmlNode
}

///|
priv struct MefTable {
  declarations : Map[String, Declaration]
  public_names : Map[String, String]
  occupied : Map[String, Bool]
}

///|
priv struct MefBasic {
  id : String
  probability : Double?
}

///|
pub struct MefDocument {
  priv xml : XmlNode
  priv basics : Array[MefBasic]
  priv houses : Array[HouseEvent]
  priv gates : Array[FormulaGate]
  priv tops : Array[String]
}

///|
fn qualify(scope : String, name : String) -> String {
  if scope == "" {
    name
  } else {
    scope + "." + name
  }
}

///|
fn name_start(c : Char) -> Bool {
  let n = c.to_int()
  c.is_ascii_alphabetic() ||
  c == '_' ||
  (n >= 0xC0 && n <= 0xD6) ||
  (n >= 0xD8 && n <= 0xF6) ||
  (n >= 0xF8 && n <= 0x2FF) ||
  (n >= 0x370 && n <= 0x37D) ||
  (n >= 0x37F && n <= 0x1FFF) ||
  (n >= 0x200C && n <= 0x200D) ||
  (n >= 0x2070 && n <= 0x218F) ||
  (n >= 0x2C00 && n <= 0x2FEF) ||
  (n >= 0x3001 && n <= 0xD7FF) ||
  (n >= 0xF900 && n <= 0xFDCF) ||
  (n >= 0xFDF0 && n <= 0xFFFD) ||
  (n >= 0x10000 && n <= 0xEFFFF)
}

///|
fn validate_mef_name(name : String) -> Unit raise FaultError {
  valid_id(name)
  let chars = name.iter()
  guard chars.next() is Some(first) && name_start(first) else {
    raise Invalid("invalid MEF identifier: " + name)
  }
  for c in chars {
    let n = c.to_int()
    guard name_start(c) ||
      c.is_ascii_digit() ||
      c == '-' ||
      n == 0xB7 ||
      (n >= 0x300 && n <= 0x36F) ||
      (n >= 0x203F && n <= 0x2040) else {
      raise Invalid("invalid MEF identifier: " + name)
    }
  }
}

///|
fn role(node : XmlNode, inherited : Bool) -> Bool raise FaultError {
  match node.get("role") {
    None => inherited
    Some("public") => true
    Some("private") => false
    _ => raise node.error("role must be public or private")
  }
}

///|
fn MefTable::collect(
  self : MefTable,
  nodes : Array[XmlNode],
  scope : String,
  inherited : Bool,
  container : String,
) -> Unit raise FaultError {
  for node in nodes {
    let category = match node.tag {
      "define-component" if container != "model-data" => "component"
      "define-gate" if container != "model-data" => "gate"
      "define-basic-event" => "basic-event"
      "define-house-event" => "house-event"
      "define-parameter" => "parameter"
      _ => raise node.error("outside the static MEF profile")
    }
    node.allow_attributes(
      if category == "parameter" {
        ["name", "role", "unit"]
      } else {
        ["name", "role"]
      },
    )
    if category == "parameter" {
      let unit = node.get("unit").unwrap_or("float")
      guard ["float", "int", "bool"].contains(unit) else {
        raise node.error(
          "dimensioned parameters are outside the static probability profile",
        )
      }
    }
    let name = node.require("name").trim().to_owned()
    validate_mef_name(name)
    let path = qualify(scope, name)
    valid_id(path)
    guard !self.occupied.contains(path) else {
      raise node.error("duplicate declaration " + path)
    }
    self.occupied[path] = true
    let is_public = role(node, inherited)
    let body = node.content()
    if category == "component" {
      self.collect(body, path, is_public, category)
    } else {
      if is_public {
        guard !self.public_names.contains(name) else {
          raise node.error("duplicate public identifier " + name)
        }
        self.public_names[name] = path
      }
      self.declarations[path] = { path, scope, category, body, source: node, }
    }
  }
}

///|
fn MefTable::resolve(
  self : MefTable,
  scope : String,
  name : String,
) -> Declaration? {
  if self.declarations.get(qualify(scope, name)) is Some(d) {
    return Some(d)
  }
  if name.contains(".") || scope == "" {
    if self.declarations.get(name) is Some(d) {
      return Some(d)
    }
  }
  match self.public_names.get(name) {
    Some(path) => self.declarations.get(path)
    None => None
  }
}

///|
fn MefTable::read_reference(
  self : MefTable,
  n : XmlNode,
  scope : String,
  expected : String,
) -> Declaration raise FaultError {
  let name = n.require("name").trim().to_owned()
  guard self.resolve(scope, name) is Some(d) else {
    raise n.error("unknown or out-of-scope reference " + name)
  }
  guard expected == "" || expected == d.category else {
    raise n.error(
      "type mismatch for " +
      name +
      ": expected " +
      expected +
      ", found " +
      d.category,
    )
  }
  d
}

///|
fn boolean_value(n : XmlNode) -> Bool raise FaultError {
  n.leaf(["value"])
  match n.require("value").trim().to_owned() {
    "true" => true
    "false" => false
    _ => raise n.error("expected true or false")
  }
}

///|
fn xml_int(n : XmlNode, attribute : String) -> Int32 raise FaultError {
  let value = n.require(attribute)
  @string.parse_int(value.trim()) catch {
    _ => raise n.error("invalid integer attribute " + attribute)
  }
}

///|
fn MefTable::formula(
  self : MefTable,
  n : XmlNode,
  scope : String,
  refs : Map[String, Bool],
) -> Formula raise FaultError {
  if n.tag == "constant" {
    return Constant(boolean_value(n))
  }
  if ["event", "basic-event", "house-event", "gate"].contains(n.tag) {
    n.leaf(if n.tag == "event" { ["name", "type"] } else { ["name"] })
    let expected = if n.tag == "event" {
      n.get("type").unwrap_or("")
    } else {
      n.tag
    }
    guard ["", "basic-event", "house-event", "gate"].contains(expected) else {
      raise n.error("invalid event type")
    }
    let d = self.read_reference(n, scope, expected)
    guard d.category != "parameter" else {
      raise n.error("parameter is not a Boolean event")
    }
    if d.category == "gate" {
      refs[d.path] = true
    }
    return EventRef(d.path)
  }
  n.structural()
  n.allow_attributes(
    match n.tag {
      "atleast" => ["min"]
      "cardinality" => ["min", "max"]
      _ => []
    },
  )
  guard n.children.length() >= 1 && n.children.length() <= 64 else {
    raise n.error("expected 1..64 formula operands")
  }
  let operands = n.children.map(child => self.formula(child, scope, refs))
  match n.tag {
    "and" => All(operands)
    "or" => Any(operands)
    "nand" => Invert(All(operands))
    "nor" => Invert(Any(operands))
    "xor" => Parity(operands)
    "iff" => {
      let mut f = operands[0]
      for i = 1; i < operands.length(); i = i + 1 {
        f = Equivalent(f, operands[i])
      }
      f
    }
    "not" => {
      guard operands.length() == 1 else {
        raise n.error("not needs one operand")
      }
      Invert(operands[0])
    }
    "imply" => {
      guard operands.length() == 2 else {
        raise n.error("imply needs two operands")
      }
      Implies(operands[0], operands[1])
    }
    "atleast" => {
      let min = xml_int(n, "min")
      guard min > 0 && min <= operands.length() else {
        raise n.error("invalid voting threshold")
      }
      Between(min, operands.length(), operands)
    }
    "cardinality" => {
      let min = xml_int(n, "min")
      let max = xml_int(n, "max")
      guard min >= 0 && max >= min && max <= operands.length() else {
        raise n.error("invalid cardinality bounds")
      }
      Between(min, max, operands)
    }
    _ => raise n.error("unsupported static Boolean formula")
  }
}

///|
fn MefTable::parameter(
  self : MefTable,
  d : Declaration,
  values : Map[String, Double],
  active : Map[String, Bool],
  depth : Int32,
) -> Double raise FaultError {
  if values.get(d.path) is Some(v) {
    return v
  }
  guard !active.contains(d.path) else {
    raise d.source.error("cyclic parameter " + d.path)
  }
  guard d.body.length() == 1 else {
    raise d.source.error("parameter needs one expression")
  }
  active[d.path] = true
  let value = self.expression(d.body[0], d.scope, values, active, depth + 1)
  match d.source.get("unit") {
    Some("bool") => ignore(expression_bool(d.source, value))
    Some("int") => {
      guard value == @math.floor(value) && value.abs() <= 9007199254740991.0 else {
        raise d.source.error(
          "int parameter must be an exactly representable integer",
        )
      }
    }
    _ => ()
  }
  active.remove(d.path)
  values[d.path] = value
  value
}

///|
/// Parses static Open-PSA MEF 2.0 XML, resolving scope and checking all declared logic.
pub fn import_mef(source : String) -> MefDocument raise FaultError {
  let xml = parse_xml(source)
  guard xml.tag == "opsa-mef" else { raise xml.error("expected opsa-mef root") }
  xml.allow_attributes(["name"])
  let t : MefTable = {
    declarations: Map([]),
    public_names: Map([]),
    occupied: Map([]),
  }
  let mut has_data = false
  for node in xml.content() {
    match node.tag {
      "model-data" => {
        node.allow_attributes([])
        guard !has_data else { raise node.error("duplicate model-data") }
        has_data = true
        t.collect(node.content(), "", true, "model-data")
      }
      "define-fault-tree" => {
        node.allow_attributes(["name"])
        let scope = node.require("name").trim().to_owned()
        validate_mef_name(scope)
        guard !t.occupied.contains(scope) else {
          raise node.error("duplicate tree " + scope)
        }
        t.occupied[scope] = true
        t.collect(node.content(), scope, true, "tree")
      }
      _ => raise node.error("outside the static MEF profile")
    }
  }
  let checked : Map[String, Bool] = Map([])
  let checking : Map[String, Bool] = Map([])
  for _, d in t.declarations {
    if d.category == "parameter" {
      t.check_parameter(d, checked, checking, 0)
    } else if d.category == "basic-event" {
      for body in d.body {
        t.check_expression(body, d.scope, checked, checking, 0)
      }
    }
  }
  let basics : Array[MefBasic] = []
  let houses : Array[HouseEvent] = []
  let gates : Array[FormulaGate] = []
  let refs : Map[String, Bool] = Map([])
  let values : Map[String, Double] = Map([])
  let active : Map[String, Bool] = Map([])
  for _, d in t.declarations {
    match d.category {
      "gate" => {
        guard d.body.length() == 1 else {
          raise d.source.error("gate needs one Boolean formula")
        }
        gates.push({ id: d.path, formula: t.formula(d.body[0], d.scope, refs), })
      }
      "house-event" => {
        guard d.body.length() <= 1 else {
          raise d.source.error("house event needs zero or one constant")
        }
        let value = if d.body.is_empty() {
          false
        } else {
          guard d.body[0].tag == "constant" else {
            raise d.body[0].error("expected Boolean constant")
          }
          boolean_value(d.body[0])
        }
        houses.push({ id: d.path, value, })
      }
      "basic-event" => {
        guard d.body.length() <= 1 else {
          raise d.source.error("basic event needs at most one expression")
        }
        let probability = if d.body.is_empty() {
          None
        } else {
          let p = t.expression(d.body[0], d.scope, values, active, 0)
          valid_probability(p)
          Some(p)
        }
        basics.push({ id: d.path, probability, })
      }
      _ => ignore(t.parameter(d, values, active, 0))
    }
  }
  guard !gates.is_empty() else { raise xml.error("no defined static gates") }
  // A placeholder is used only to validate topology, never as a numerical result.
  let check_events = basics.map(b => Event::{
    id: b.id,
    probability: b.probability.unwrap_or(0.0),
  })
  ignore(
    compile_logic({ events: check_events, houses, gates, top: gates[0].id, }, []),
  )
  let tops = gates.filter(g => !refs.contains(g.id)).map(g => g.id)
  tops.sort()
  { xml, basics, houses, gates, tops, }
}

///|
pub fn MefDocument::top_events(self : MefDocument) -> Array[String] {
  self.tops.copy()
}

///|
pub fn MefDocument::missing_probabilities(self : MefDocument) -> Array[String] {
  self.basics.filter(b => b.probability is None).map(b => b.id)
}

///|
pub fn MefDocument::compile(
  self : MefDocument,
  top : String,
  probabilities : Map[String, Double],
  order : Array[String],
) -> Tree raise FaultError {
  let chosen = if top == "" {
    guard self.tops.length() == 1 else {
      raise Invalid(
        "MEF has multiple top gates; select one of " + self.tops.join(", "),
      )
    }
    self.tops[0]
  } else {
    let matches = self.gates.filter(g => {
      g.id == top ||
      (g.id.split(".").last() is Some(name) && name.to_owned() == top)
    })
    guard matches.length() == 1 else {
      raise Invalid("MEF top gate is unknown or ambiguous: " + top)
    }
    matches[0].id
  }
  for id, p in probabilities {
    guard self.basics.any(b => b.id == id) else {
      raise Invalid("unknown MEF basic event probability: " + id)
    }
    valid_probability(p)
  }
  let events = self.basics.map(b => {
    let probability = match probabilities.get(b.id) {
      Some(p) => Some(p)
      None => b.probability
    }
    guard probability is Some(p) else {
      raise Invalid("missing probability for " + b.id)
    }
    Event::{ id: b.id, probability: p, }
  })
  compile_logic(
    { events, houses: self.houses, gates: self.gates, top: chosen, },
    order,
  )
}

///|
/// Writes the same scoped MEF model, retaining labels and user attributes, not XML bytes.
pub fn MefDocument::to_xml(self : MefDocument) -> String raise FaultError {
  try {
    let w = @xml.Writer::new()
    self.xml.write(w)
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" + w.to_string() + "\n"
  } catch {
    _ => raise Invalid("could not write normalized MEF XML")
  }
}
