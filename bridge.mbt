///|
fn probability_value(v : Json) -> Double raise FaultError {
  match v {
    Number(p, ..) => {
      valid_probability(p)
      p
    }
    _ => raise Invalid("probability must be a number")
  }
}

///|
fn truth_value(v : Json) -> Bool raise FaultError {
  match v {
    True => true
    False => false
    _ => raise Invalid("expected Boolean value")
  }
}

///|
fn prob_map(v : Json) -> Map[String, Double] raise FaultError {
  let out : Map[String, Double] = Map([])
  for id, p in obj(v) {
    out[id] = probability_value(p)
  }
  out
}

///|
fn formula_op(
  o : Map[String, Json],
  kind : String,
  args : Array[Formula],
) -> Formula raise FaultError {
  validate_arity(args)
  match kind {
    "and" => All(args)
    "or" => Any(args)
    "nand" => Invert(All(args))
    "nor" => Invert(Any(args))
    "xor" => Parity(args)
    "not" => {
      guard args.length() == 1 else { raise Invalid("not needs one operand") }
      Invert(args[0])
    }
    "iff" => {
      let mut result = args[0]
      for i = 1; i < args.length(); i = i + 1 {
        result = Equivalent(result, args[i])
      }
      result
    }
    "imply" => {
      guard args.length() == 2 else {
        raise Invalid("imply needs two operands")
      }
      Implies(args[0], args[1])
    }
    "vote" | "atleast" => {
      let k = num(required(o, "threshold"))
      guard k >= 1 && k <= args.length() else {
        raise Invalid("invalid vote threshold")
      }
      Between(k, args.length(), args)
    }
    "cardinality" =>
      Between(num(required(o, "min")), num(required(o, "max")), args)
    _ => raise Invalid("unsupported Boolean operator " + kind)
  }
}

///|
fn decode_formula(v : Json, depth : Int32) -> Formula raise FaultError {
  guard depth <= 128 else { raise Limit("JSON formula depth exceeds 128") }
  match v {
    String(id) => EventRef(id)
    True => Constant(true)
    False => Constant(false)
    Object(o) =>
      formula_op(
        o,
        txt(required(o, "kind")),
        arr(required(o, "args")).map(x => decode_formula(x, depth + 1)),
      )
    _ => raise Invalid("formula must be an ID, Boolean, or operator object")
  }
}

///|
fn decode_model(model : Map[String, Json]) -> LogicModel raise FaultError {
  let events = arr(required(model, "events")).map(v => {
    let e = obj(v)
    Event::{
      id: txt(required(e, "id")),
      probability: probability_value(required(e, "probability")),
    }
  })
  let houses = arr(model.get("houses").unwrap_or(Json::array([]))).map(v => {
    let h = obj(v)
    HouseEvent::{
      id: txt(required(h, "id")),
      value: truth_value(required(h, "value")),
    }
  })
  let gates = arr(required(model, "gates")).map(v => {
    let g = obj(v)
    let id = txt(required(g, "id"))
    let formula = match g.get("formula") {
      Some(f) => {
        guard !g.contains("kind") && !g.contains("inputs") else {
          raise Invalid("gate cannot mix formula and kind/inputs")
        }
        decode_formula(f, 0)
      }
      None => {
        let kind = txt(required(g, "kind"))
        let inputs = arr(required(g, "inputs")).map(txt)
        if ["and", "or", "vote"].contains(kind) {
          let seen : Map[String, Bool] = Map([])
          for name in inputs {
            guard !seen.contains(name) else {
              raise Invalid("duplicate direct gate input")
            }
            seen[name] = true
          }
        }
        formula_op(g, kind, inputs.map(name => EventRef(name)))
      }
    }
    FormulaGate::{ id, formula, }
  })
  { events, houses, gates, top: txt(required(model, "top")), }
}

///|
fn run_request(o : Map[String, Json]) -> Json raise FaultError {
  let command = txt(o.get("command").unwrap_or(Json::string("analyze")))
  let order = arr(o.get("order").unwrap_or(Json::array([]))).map(txt)
  let tree = match o.get("xml") {
    Some(source) => {
      guard !o.contains("model") else {
        raise Invalid("provide one of xml and model")
      }
      let doc = import_mef(txt(source))
      if command == "mef_export" {
        return Json::string(doc.to_xml())
      }
      if command == "mef_inspect" {
        return jo([
          ("top_events", @json.to_json(doc.top_events())),
          ("missing_probabilities", @json.to_json(doc.missing_probabilities())),
        ])
      }
      doc.compile(
        txt(o.get("top").unwrap_or(Json::string(""))),
        prob_map(o.get("probabilities").unwrap_or(jo([]))),
        order,
      )
    }
    None => {
      let model = decode_model(obj(required(o, "model")))
      if command == "mef_export" {
        return Json::string(
          export_mef(
            model,
            txt(o.get("tree_name").unwrap_or(Json::string("MoonFault"))),
          ),
        )
      }
      compile_logic(model, order)
    }
  }
  let overrides = prob_map(o.get("overrides").unwrap_or(jo([])))
  let forced : Map[String, Bool] = Map([])
  for id, value in obj(o.get("forced").unwrap_or(jo([]))) {
    forced[id] = truth_value(value)
  }
  let budget = num(
    o
    .get("max_prime_implicants")
    .unwrap_or(o.get("max_cut_sets").unwrap_or(jn(5000))),
  )
  match command {
    "analyze" => tree.logic_report(overrides, forced, budget)
    "prime_implicants" => @json.to_json(tree.prime_implicants(budget))
    "importance" =>
      Json::array(tree.risk_importance(overrides, forced).map(x => x.json()))
    "probability" => Json::number(tree.probability(overrides, forced))
    _ => raise Invalid("unknown command")
  }
}

///|
pub fn run_json(request : String) -> String {
  try {
    guard request.length() <= 3000000 else {
      raise Limit("request exceeds 3000000 UTF-16 units")
    }
    let result = run_request(obj(@json.parse(request)))
    jo([("ok", Json::boolean(true)), ("result", result)]).stringify()
  } catch {
    e => {
      let (code, message) = match e {
        FaultError::Invalid(s) => ("invalid", s)
        FaultError::Limit(s) => ("limit", s)
        _ => ("json", "invalid JSON request")
      }
      jo([
        ("ok", Json::boolean(false)),
        ("code", Json::string(code)),
        ("error", Json::string(message)),
      ]).stringify()
    }
  }
}
