///|
fn expression_finite(n : XmlNode, value : Double) -> Double raise FaultError {
  guard !value.is_inf() && !value.is_nan() else {
    raise n.error("nonfinite expression result or intermediate")
  }
  value
}

///|
fn expression_number(n : XmlNode) -> Double raise FaultError {
  n.leaf(["value"])
  let literal = n.require("value").trim().to_owned()
  if n.tag == "int" {
    let chars = literal.iter().to_array()
    guard !chars.is_empty() else { raise n.error("empty integer") }
    let mut digits = 0
    for i, c in chars {
      if i == 0 && (c == '+' || c == '-') {
        continue
      }
      guard c.is_ascii_digit() else { raise n.error("invalid integer literal") }
      digits = digits + 1
    }
    guard digits > 0 else { raise n.error("invalid integer literal") }
  }
  let value = @string.parse_double(literal.trim()) catch {
    _ => raise n.error("invalid numerical literal")
  }
  ignore(expression_finite(n, value))
  if n.tag == "int" && value.abs() > 9007199254740991.0 {
    raise n.error("integer exceeds exact binary64 range")
  }
  value
}

///|
fn expression_arity(n : XmlNode) -> Unit raise FaultError {
  n.allow_attributes([])
  n.structural()
  let (minimum, maximum) = match n.tag {
    "pi" => (0, 0)
    "neg"
    | "abs"
    | "acos"
    | "asin"
    | "atan"
    | "cos"
    | "cosh"
    | "exp"
    | "log"
    | "log10"
    | "sin"
    | "sinh"
    | "tan"
    | "tanh"
    | "sqrt"
    | "ceil"
    | "floor"
    | "not" => (1, 1)
    "pow" | "mod" | "eq" | "df" | "lt" | "gt" | "leq" | "geq" | "exponential" =>
      (2, 2)
    "ite" => (3, 3)
    "GLM" | "Weibull" => (4, 4)
    "add" | "sub" | "mul" | "div" | "min" | "max" | "mean" | "and" | "or" =>
      (2, 20000)
    _ => raise n.error("unsupported MEF expression " + n.tag)
  }
  guard n.children.length() >= minimum && n.children.length() <= maximum else {
    raise n.error("wrong operand count for " + n.tag)
  }
}

///|
// Validate all branches before evaluating any branch. An unselected branch may
// contain a domain error, but not unknown operators, names, cycles or bad syntax.
fn MefTable::check_expression(
  self : MefTable,
  n : XmlNode,
  scope : String,
  checked : Map[String, Bool],
  active : Map[String, Bool],
  depth : Int32,
) -> Unit raise FaultError {
  guard depth <= 128 else { raise Limit("MEF expression depth exceeds 128") }
  match n.tag {
    "float" | "int" => ignore(expression_number(n))
    "bool" => ignore(boolean_value(n))
    "parameter" => {
      n.leaf(["name"])
      self.check_parameter(
        self.read_reference(n, scope, "parameter"),
        checked,
        active,
        depth + 1,
      )
    }
    "switch" => {
      n.allow_attributes([])
      n.structural()
      guard !n.children.is_empty() else {
        raise n.error("switch needs a default expression")
      }
      for i, child in n.children {
        if i == n.children.length() - 1 {
          self.check_expression(child, scope, checked, active, depth + 1)
        } else {
          guard child.tag == "case" else {
            raise child.error("expected case before switch default")
          }
          child.allow_attributes([])
          child.structural()
          guard child.children.length() == 2 else {
            raise child.error("case needs condition and value")
          }
          for c in child.children {
            self.check_expression(c, scope, checked, active, depth + 1)
          }
        }
      }
    }
    _ => {
      expression_arity(n)
      for c in n.children {
        self.check_expression(c, scope, checked, active, depth + 1)
      }
    }
  }
}

///|
fn MefTable::check_parameter(
  self : MefTable,
  d : Declaration,
  checked : Map[String, Bool],
  active : Map[String, Bool],
  depth : Int32,
) -> Unit raise FaultError {
  guard !active.contains(d.path) else {
    raise d.source.error("cyclic parameter " + d.path)
  }
  if checked.contains(d.path) {
    return
  }
  guard d.body.length() == 1 else {
    raise d.source.error("parameter needs one expression")
  }
  active[d.path] = true
  self.check_expression(d.body[0], d.scope, checked, active, depth + 1)
  active.remove(d.path)
  checked[d.path] = true
}

///|
fn expression_bool(n : XmlNode, x : Double) -> Bool raise FaultError {
  guard x == 0.0 || x == 1.0 else {
    raise n.error("Boolean operand must be 0 or 1")
  }
  x == 1.0
}

///|
fn MefTable::expression(
  self : MefTable,
  n : XmlNode,
  scope : String,
  values : Map[String, Double],
  active : Map[String, Bool],
  depth : Int32,
) -> Double raise FaultError {
  guard depth <= 128 else { raise Limit("MEF expression depth exceeds 128") }
  let eval = c => self.expression(c, scope, values, active, depth + 1)
  let value = match n.tag {
    "float" | "int" => expression_number(n)
    "bool" => if boolean_value(n) { 1.0 } else { 0.0 }
    "parameter" =>
      self.parameter(
        self.read_reference(n, scope, "parameter"),
        values,
        active,
        depth,
      )
    "ite" => {
      let index = if expression_bool(n, eval(n.children[0])) { 1 } else { 2 }
      eval(n.children[index])
    }
    "switch" => {
      let mut chosen = n.children[n.children.length() - 1]
      for i = 0; i < n.children.length() - 1; i = i + 1 {
        let c = n.children[i]
        if expression_bool(c, eval(c.children[0])) {
          chosen = c.children[1]
          break
        }
      }
      eval(chosen)
    }
    "and" | "or" => {
      let mut result = n.tag == "and"
      for c in n.children {
        let b = expression_bool(c, eval(c))
        if n.tag == "and" && !b {
          result = false
          break
        }
        if n.tag == "or" && b {
          result = true
          break
        }
      }
      if result {
        1.0
      } else {
        0.0
      }
    }
    _ => {
      let xs = n.children.map(eval)
      match n.tag {
        "pi" => @math.PI
        "neg" => -xs[0]
        "abs" => xs[0].abs()
        "acos" => @math.acos(xs[0])
        "asin" => @math.asin(xs[0])
        "atan" => @math.atan(xs[0])
        "cos" => @math.cos(xs[0])
        "cosh" => @math.cosh(xs[0])
        "exp" => @math.exp(xs[0])
        "log" => @math.ln(xs[0])
        "log10" => @math.log10(xs[0])
        "sin" => @math.sin(xs[0])
        "sinh" => @math.sinh(xs[0])
        "tan" => @math.tan(xs[0])
        "tanh" => @math.tanh(xs[0])
        "sqrt" => xs[0].sqrt()
        "ceil" => @math.ceil(xs[0])
        "floor" => @math.floor(xs[0])
        "pow" => @math.pow(xs[0], xs[1])
        "mod" => {
          guard xs[1] != 0.0 else { raise n.error("modulo by zero") }
          xs[0] % xs[1]
        }
        "not" => if expression_bool(n, xs[0]) { 0.0 } else { 1.0 }
        "eq" | "df" | "lt" | "gt" | "leq" | "geq" => {
          let result = match n.tag {
            "eq" => xs[0] == xs[1]
            "df" => xs[0] != xs[1]
            "lt" => xs[0] < xs[1]
            "gt" => xs[0] > xs[1]
            "leq" => xs[0] <= xs[1]
            _ => xs[0] >= xs[1]
          }
          if result {
            1.0
          } else {
            0.0
          }
        }
        "exponential" | "GLM" | "Weibull" => lifetime_probability(n, xs)
        "mean" => {
          // Scale first: mean(1e308,1e308) is finite despite the naive sum.
          let mut scale = 0.0
          for x in xs {
            if x.abs() > scale {
              scale = x.abs()
            }
          }
          if scale == 0.0 {
            0.0
          } else {
            let mut sum = 0.0
            for x in xs {
              sum = sum + x / scale
            }
            sum / xs.length().to_double() * scale
          }
        }
        _ => {
          let mut result = xs[0]
          for i = 1; i < xs.length(); i = i + 1 {
            let x = xs[i]
            result = match n.tag {
              "add" => result + x
              "sub" => result - x
              "mul" => result * x
              "div" => {
                guard x != 0.0 else { raise n.error("division by zero") }
                result / x
              }
              "min" => if result < x { result } else { x }
              "max" => if result > x { result } else { x }
              _ => raise n.error("unsupported expression")
            }
            ignore(expression_finite(n, result))
          }
          result
        }
      }
    }
  }
  expression_finite(n, value)
}

///|
fn lifetime_probability(
  n : XmlNode,
  xs : Array[Double],
) -> Double raise FaultError {
  match n.tag {
    "exponential" => {
      guard xs[0] >= 0.0 && xs[1] >= 0.0 else {
        raise n.error("rate and time must be nonnegative")
      }
      // expm1 avoids cancellation for small rate*time. Infinite exposure
      // from finite operands is the well-defined saturated probability 1.
      -@math.expm1(-(xs[0] * xs[1]))
    }
    "GLM" => {
      let gamma = xs[0]
      let lambda = xs[1]
      let mu = xs[2]
      let time = xs[3]
      guard gamma >= 0.0 &&
        gamma <= 1.0 &&
        lambda >= 0.0 &&
        mu >= 0.0 &&
        time >= 0.0 else {
        raise n.error("GLM needs gamma in [0,1] and nonnegative rates/time")
      }
      if time == 0.0 || (lambda == 0.0 && mu == 0.0) {
        gamma
      } else {
        // Ratio avoids overflowing lambda+mu; exposure may safely saturate.
        let scale = if lambda > mu { lambda } else { mu }
        let equilibrium = lambda / scale / (lambda / scale + mu / scale)
        let exposure = lambda * time + mu * time
        let changed = -@math.expm1(-exposure)
        gamma * @math.exp(-exposure) + equilibrium * changed
      }
    }
    _ => {
      let scale = xs[0]
      let shape = xs[1]
      let shift = xs[2]
      let time = xs[3]
      guard scale > 0.0 && shape > 0.0 && shift >= 0.0 && time >= 0.0 else {
        raise n.error(
          "Weibull needs positive scale/shape and nonnegative shift/time",
        )
      }
      if time <= shift {
        0.0
      } else {
        let delta = time - shift
        let ratio = delta / scale
        let hazard = if ratio < 2.2250738585072014e-308 || ratio.is_inf() {
          @math.exp(shape * (@math.ln(delta) - @math.ln(scale)))
        } else {
          @math.pow(ratio, shape)
        }
        -@math.expm1(-hazard)
      }
    }
  }
}
