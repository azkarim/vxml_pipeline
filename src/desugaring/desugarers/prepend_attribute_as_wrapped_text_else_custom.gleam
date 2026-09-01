import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/option.{Some}
import vxml.{type VXML, Attr, Line, T, V}
import vxml/blame as bl

pub const name = "prepend_attribute_as_wrapped_text_else_custom"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Prepends a wrapped attribute value, or a fallback node
/// when the value is absent.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  #(
    // Target tag.
    String,
    // Attribute key.
    String,
    // Wrapper node.
    VXML,
    // Fallback node.
    VXML,
  )

type InnerParam {
  InnerParam(
    target_tag: String,
    attribute_key: String,
    wrapper: VXML,
    fallback: VXML,
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(InnerParam(param.0, param.1, param.2, param.3))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  nodemap
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    V(_, tag, _, children) if tag == inner.target_tag -> {
      let node_to_prepend = case
        core.v_first_attr_with_key(vxml, inner.attribute_key)
      {
        Some(Attr(_, _, value)) if value != "" -> {
          let assert V(b, t, a, c) = inner.wrapper
          V(b, t, a, [
            T(desugarer_blame(59), [Line(desugarer_blame(59), value)]),
            ..c
          ])
        }
        _ -> inner.fallback
      }
      V(..vxml, children: [node_to_prepend, ..children])
    }
    _ -> vxml
  }
}

fn desugarer_blame(line_no: Int) {
  authoring.blame(name, line_no)
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  let wrapper =
    vxml.V(bl.no_blame, "span", [vxml.Attr(bl.no_blame, "class", "label")], [])
  let else_node =
    vxml.V(bl.no_blame, "span", [vxml.Attr(bl.no_blame, "class", "missing")], [
      vxml.T(bl.no_blame, [vxml.Line(bl.no_blame, "Default")]),
    ])
  [
    testing.data(
      param: #("div", "title", wrapper, else_node),
      source: "
                <> div
                  title='Hello World'
                  <> p
                    <>
                      'Content'
                ",
      expected: "
                <> div
                  title='Hello World'
                  <> span
                    class=label
                    <>
                      ''Hello World''
                  <> p
                    <>
                      'Content'
                ",
    ),
    testing.data(
      param: #("div", "missing", wrapper, else_node),
      source: "
                <> div
                  class='test'
                  <> p
                    <>
                      'Content'
                ",
      expected: "
                <> div
                  class='test'
                  <> span
                    class=missing
                    <>
                      'Default'
                  <> p
                    <>
                      'Content'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
