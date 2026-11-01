///|
pub(all) suberror FaultError { Invalid(String); Limit(String) } derive(Eq, @debug.Debug)

///|
pub(all) struct Event { id : String; probability : Double } derive(Eq, @debug.Debug)

///|
pub(all) enum GateKind { And; Or; Vote(Int) } derive(Eq, @debug.Debug)

///|
pub(all) struct Gate { id : String; kind : GateKind; inputs : Array[String] } derive(Eq, @debug.Debug)

///|
priv struct Node { variable : Int; low : Int; high : Int }

///|
priv struct Manager {
  nodes : Array[Node]
  unique : Map[(Int, Int, Int), Int]
  cache : Map[(Int, Int, Int), Int]
  mut work : Int
}

///|
pub struct Tree {
  priv events : Array[Event]
  priv nodes : Array[Node]
  priv root : Int
}

///|
pub(all) struct Importance {
  event : String
  if_failed : Double
  if_working : Double
  birnbaum : Double
} derive(Eq, ToJson, @debug.Debug)

///|
pub(all) struct Analysis {
  probability : Double
  importance : Array[Importance]
  minimal_cut_sets : Array[Array[String]]
  cut_union_bound : Double
  bdd_nodes : Int
  basic_events : Int
} derive(Eq, ToJson, @debug.Debug)

///|
fn valid_probability(p : Double) -> Unit raise FaultError {
  guard p >= 0.0 && p <= 1.0 else { raise Invalid("event probability must be finite and in [0,1]") }
}

///|
fn valid_id(id : String) -> Unit raise FaultError {
  guard id.length() > 0 && id.length() <= 128 else { raise Invalid("identifier must contain 1..128 UTF-16 units") }
}
