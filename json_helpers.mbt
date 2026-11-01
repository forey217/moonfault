///|
fn obj(v : Json) -> Map[String, Json] raise FaultError {
  match v {
    Object(o) => o
    _ => raise Invalid("expected object")
  }
}

///|
fn required(o : Map[String, Json], k : String) -> Json raise FaultError {
  match o.get(k) {
    Some(v) => v
    None => raise Invalid("missing field: " + k)
  }
}

///|
fn txt(v : Json) -> String raise FaultError {
  match v {
    String(s) => s
    _ => raise Invalid("expected string")
  }
}

///|
fn num(v : Json) -> Int32 raise FaultError {
  match v {
    Number(n, ..) => {
      guard n >= -1000000000.0 &&
        n <= 1000000000.0 &&
        n.to_int().to_double() == n else {
        raise Invalid("expected bounded integer")
      }
      n.to_int()
    }
    _ => raise Invalid("expected integer")
  }
}

///|
fn arr(v : Json) -> Array[Json] raise FaultError {
  match v {
    Array(a) => a
    _ => raise Invalid("expected array")
  }
}

///|
fn jn(n : Int32) -> Json {
  Json::number(n.to_double())
}

///|
fn jo(fields : Array[(String, Json)]) -> Json {
  Json::object(Map(fields))
}
