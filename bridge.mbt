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
pub fn run_json(request : String) -> String {
  try {
    guard request.length() <= 1000000 else {
      raise Limit("request exceeds 1000000 UTF-16 units")
    }
    let o = obj(@json.parse(request))
    let model = obj(required(o, "model"))
    let events = arr(required(model, "events")).map(v => {
      let e = obj(v)
      {
        id: txt(required(e, "id")),
        probability: probability_value(required(e, "probability")),
      }
    })
    let gates = arr(required(model, "gates")).map(v => {
      let g = obj(v)
      let kind = match txt(required(g, "kind")) {
        "and" => And
        "or" => Or
        "vote" => Vote(num(required(g, "threshold")))
        _ => raise Invalid("gate kind must be and/or/vote")
      }
      {
        id: txt(required(g, "id")),
        kind,
        inputs: arr(required(g, "inputs")).map(txt),
      }
    })
    let tree = compile(
      events,
      gates,
      txt(required(model, "top")),
      arr(o.get("order").unwrap_or(Json::array([]))).map(txt),
    )
    let overrides : Map[String, Double] = Map([])
    for k, v in obj(o.get("overrides").unwrap_or(jo([]))) {
      overrides[k] = probability_value(v)
    }
    let forced : Map[String, Bool] = Map([])
    for k, v in obj(o.get("forced").unwrap_or(jo([]))) {
      forced[k] = match v {
        True => true
        False => false
        _ => raise Invalid("forced event state must be boolean")
      }
    }
    let command = txt(o.get("command").unwrap_or(Json::string("analyze")))
    let result = match command {
      "analyze" =>
        @json.to_json(
          tree.analyze(
            overrides,
            forced,
            num(o.get("max_cut_sets").unwrap_or(jn(5000))),
          ),
        )
      "probability" => Json::number(tree.probability(overrides, forced))
      _ => raise Invalid("unknown command")
    }
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
