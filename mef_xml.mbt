///|
priv struct XmlNode {
  tag : String
  attributes : Array[(String, String)]
  children : Array[XmlNode]
  text : StringBuilder
  line : Int32
}

///|
fn XmlNode::get(self : XmlNode, key : String) -> String? {
  for (k, v) in self.attributes {
    if k == key {
      return Some(v)
    }
  }
  None
}

///|
fn XmlNode::error(self : XmlNode, message : String) -> FaultError {
  Invalid(
    "MEF line " + self.line.to_string() + " <" + self.tag + ">: " + message,
  )
}

///|
fn XmlNode::require(self : XmlNode, key : String) -> String raise FaultError {
  guard self.get(key) is Some(value) else {
    raise self.error("missing attribute " + key)
  }
  value
}

///|
fn XmlNode::allow_attributes(
  self : XmlNode,
  allowed : Array[String],
) -> Unit raise FaultError {
  for (k, _) in self.attributes {
    guard allowed.contains(k) else {
      raise self.error("unsupported attribute " + k)
    }
  }
}

///|
fn XmlNode::structural(self : XmlNode) -> Unit raise FaultError {
  guard self.text.to_string().trim().is_empty() else {
    raise self.error("unexpected text")
  }
}

///|
fn XmlNode::leaf(
  self : XmlNode,
  attributes : Array[String],
) -> Unit raise FaultError {
  self.allow_attributes(attributes)
  self.structural()
  guard self.children.is_empty() else {
    raise self.error("expected an empty element")
  }
}

///|
fn xml_node(e : @xml.XmlElement, line : Int32) -> XmlNode {
  {
    tag: e.name,
    attributes: e.attributes.map(a => (a.name, a.value)),
    children: [],
    text: StringBuilder(),
    line,
  }
}

///|
fn parse_xml(source : String) -> XmlNode raise FaultError {
  guard source.length() <= 1000000 else {
    raise Limit("MEF XML exceeds 1000000 UTF-16 units")
  }
  // The XML reader supports internal entity declarations. Preclude all internal and external
  // subsets before invoking it. A bare DOCTYPE used in Open-PSA examples is harmless.
  let markers = source.split("<!DOCTYPE")
  ignore(markers.next())
  for tail in markers {
    guard tail.to_owned().split(">").next() is Some(value) &&
      value.to_owned().trim().to_owned() == "opsa-mef" else {
      raise Invalid(
        "MEF rejects DTD subsets, custom entities and external identifiers",
      )
    }
  }
  let stack : Array[XmlNode] = []
  let mut root : XmlNode? = None
  let mut nodes = 0
  let reader = @xml.Reader::from_string(source)
  fn attach(n : XmlNode) -> Unit raise FaultError {
    if stack.length() > 0 {
      stack[stack.length() - 1].children.push(n)
    } else {
      guard root is None else { raise n.error("multiple roots") }
      root = Some(n)
    }
  }
  while true {
    let event = reader.read_event() catch {
      e => raise Invalid("MEF XML: " + e.to_string())
    }
    match event.kind {
      Start(e) => {
        nodes = nodes + 1
        guard stack.length() < 128 else {
          raise Limit("MEF XML depth exceeds 128")
        }
        let n = xml_node(e, event.span.start.line)
        attach(n)
        stack.push(n)
      }
      Empty(e) => {
        nodes = nodes + 1
        attach(xml_node(e, event.span.start.line))
      }
      End(_) => ignore(stack.pop())
      Text(s) | CData(s) =>
        if stack.length() > 0 {
          stack[stack.length() - 1].text.write_string(s)
        } else {
          guard s.trim().is_empty() else {
            raise Invalid("text outside the MEF root")
          }
        }
      DocType(value) => {
        guard value.trim().to_owned() == "opsa-mef" else {
          raise Invalid("unsupported MEF DOCTYPE")
        }
      }
      Eof => break
      _ => ()
    }
    guard nodes <= 20000 else { raise Limit("MEF XML exceeds 20000 elements") }
  }
  guard stack.is_empty() && root is Some(root) else {
    raise Invalid("missing or unclosed MEF root")
  }
  root
}

///|
fn check_metadata(n : XmlNode) -> Unit raise FaultError {
  match n.tag {
    "label" => {
      n.allow_attributes([])
      guard n.children.is_empty() else {
        raise n.error("label must contain text only")
      }
    }
    "attributes" => {
      n.allow_attributes([])
      n.structural()
      guard !n.children.is_empty() else {
        raise n.error("attributes needs an attribute child")
      }
      for a in n.children {
        guard a.tag == "attribute" else {
          raise a.error("expected attribute metadata")
        }
        a.leaf(["name", "value", "type"])
        ignore(a.require("name"))
        ignore(a.require("value"))
      }
    }
    _ => raise n.error("unsupported metadata")
  }
}

///|
fn XmlNode::content(self : XmlNode) -> Array[XmlNode] raise FaultError {
  self.structural()
  let contents : Array[XmlNode] = []
  let mut label = false
  let mut attributes = false
  for n in self.children {
    if n.tag == "label" || n.tag == "attributes" {
      guard contents.is_empty() else {
        raise n.error("metadata must precede semantic children")
      }
      if n.tag == "label" {
        guard !label && !attributes else {
          raise n.error("duplicate or misplaced label")
        }
        label = true
      } else {
        guard !attributes else {
          raise n.error("duplicate attributes metadata")
        }
        attributes = true
      }
      check_metadata(n)
    } else {
      contents.push(n)
    }
  }
  contents
}

///|
fn XmlNode::write(
  self : XmlNode,
  w : @xml.Writer,
) -> Unit raise @xml.WriterError {
  let text = self.text.to_string()
  if self.children.is_empty() && text.is_empty() {
    w.empty_element(self.tag, self.attributes)
    return
  }
  w.start_element(self.tag, self.attributes)
  if !text.is_empty() {
    w.text(text)
  }
  for n in self.children {
    n.write(w)
  }
  w.end_element(self.tag)
}
