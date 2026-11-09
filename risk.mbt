///|
pub(all) enum RiskRatio {
  Finite(Double)
  Unbounded
  Undefined
  Overflow
} derive(Eq, @debug.Debug)

///|
pub extend RiskRatio with Eq::{equal, not_equal}

///|
pub extend RiskRatio with @debug.Debug::{to_repr}

///|
pub fn RiskRatio::json(self : RiskRatio) -> Json {
  let (status, value) = match self {
    Finite(x) => ("finite", Json::number(x))
    Unbounded => ("infinite", Json::null())
    Undefined => ("undefined", Json::null())
    Overflow => ("overflow", Json::null())
  }
  jo([("status", Json::string(status)), ("value", value)])
}

///|
pub(all) struct RiskImportance {
  event : String
  effective_probability : Double
  if_failed : Double
  if_working : Double
  birnbaum : Double
  fussell_vesely : RiskRatio
  raw : RiskRatio
  rrw : RiskRatio
  scram_dif : RiskRatio
} derive(Eq, @debug.Debug)

///|
pub extend RiskImportance with Eq::{equal, not_equal}

///|
pub extend RiskImportance with @debug.Debug::{to_repr}

///|
pub fn RiskImportance::json(self : RiskImportance) -> Json {
  jo([
    ("event", Json::string(self.event)),
    ("effective_probability", Json::number(self.effective_probability)),
    ("if_failed", Json::number(self.if_failed)),
    ("if_working", Json::number(self.if_working)),
    ("birnbaum", Json::number(self.birnbaum)),
    ("fussell_vesely", self.fussell_vesely.json()),
    ("raw", self.raw.json()),
    ("rrw", self.rrw.json()),
    ("scram_dif", self.scram_dif.json()),
  ])
}

///|
fn divide(n : Double, d : Double, allow_unbounded : Bool) -> RiskRatio {
  if d == 0.0 {
    return if allow_unbounded && n > 0.0 { Unbounded } else { Undefined }
  }
  let value = n / d
  if value.is_inf() {
    Overflow
  } else {
    Finite(value)
  }
}

///|
pub fn Tree::risk_importance(
  self : Tree,
  overrides : Map[String, Double],
  forced : Map[String, Bool],
) -> Array[RiskImportance] raise FaultError {
  self.risk_with_weights(self.weights(overrides, forced))
}

///|
fn Tree::risk_with_weights(
  self : Tree,
  weights : Array[Double],
) -> Array[RiskImportance] {
  let baseline = self.evaluate(weights)
  let adjusted = weights.copy()
  let out : Array[RiskImportance] = []
  for i, e in self.events {
    let p = weights[i]
    adjusted[i] = 1.0
    let if_failed = self.evaluate(adjusted)
    adjusted[i] = 0.0
    let if_working = self.evaluate(adjusted)
    adjusted[i] = p
    let birnbaum = if_failed - if_working
    out.push({
      event: e.id,
      effective_probability: p,
      if_failed,
      if_working,
      birnbaum,
      fussell_vesely: divide(p * birnbaum, baseline, false),
      raw: divide(if_failed, baseline, true),
      rrw: divide(baseline, if_working, true),
      scram_dif: divide(p * if_failed, baseline, false),
    })
  }
  out
}

///|
fn Tree::logic_report(
  self : Tree,
  overrides : Map[String, Double],
  forced : Map[String, Bool],
  budget : Int32,
) -> Json raise FaultError {
  let weights = self.weights(overrides, forced)
  let cubes = self.prime_cubes(budget)
  let monotone = !cubes.any(c => c.negative != 0UL)
  let terms = cubes.map(c => self.literals(c))
  let mut bound = 0.0
  for cube in cubes {
    let mut product = 1.0
    for i, p in weights {
      let bit = 1UL << i
      if (cube.positive & bit) != 0UL {
        product = product * p
      }
      if (cube.negative & bit) != 0UL {
        product = product * (1.0 - p)
      }
    }
    bound = bound + product
  }
  jo([
    ("probability", Json::number(self.evaluate(weights))),
    (
      "logic_class",
      Json::string(if monotone { "monotone" } else { "nonmonotone" }),
    ),
    (
      "importance",
      Json::array(self.risk_with_weights(weights).map(x => x.json())),
    ),
    ("prime_implicants", @json.to_json(terms)),
    ("prime_union_bound", Json::number(bound.min(1.0))),
    (
      "minimal_cut_sets",
      if monotone {
        @json.to_json(terms.map(xs => xs.map(x => x.event)))
      } else {
        Json::null()
      },
    ),
    (
      "cut_union_bound",
      if monotone {
        Json::number(bound.min(1.0))
      } else {
        Json::null()
      },
    ),
    ("bdd_nodes", jn(self.nodes.length())),
    ("basic_events", jn(self.events.length())),
  ])
}
