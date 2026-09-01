import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import vxml.{type VXML, Attr, T, V}

pub const name = "add_class_to_next_sibling"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// For each marker element, adds the requested class to its
/// immediately following sibling and removes the marker.
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
    // Tag of the marker element.
    String,
    // Class added to the marker's next sibling.
    String,
  )

type InnerParam {
  InnerParam(marker_tag: String, class_name: String)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(InnerParam(param.0, param.1))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  nodemap
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    V(_, _, _, children) -> V(..vxml, children: rewrite(children, inner))
    _ -> vxml
  }
}

fn rewrite(children: List(VXML), inner: InnerParam) -> List(VXML) {
  case children {
    [] -> []
    [V(_, tag, _, _), next, ..rest] if tag == inner.marker_tag -> [
      add_class(next, inner.class_name),
      ..rewrite(rest, inner)
    ]
    // a marker with no following sibling is simply dropped
    [V(_, tag, _, _)] if tag == inner.marker_tag -> []
    [first, ..rest] -> [first, ..rewrite(rest, inner)]
  }
}

// add `class_name` to a node's `class` attribute (appending, or creating it)
fn add_class(vxml: VXML, class_name: String) -> VXML {
  case vxml {
    T(_, _) -> vxml
    V(b, tag, attrs, children) ->
      case list.any(attrs, fn(a) { a.key == "class" }) {
        True ->
          V(
            b,
            tag,
            list.map(attrs, fn(a) {
              case a.key == "class" {
                True -> Attr(..a, val: a.val <> " " <> class_name)
                False -> a
              }
            }),
            children,
          )
        False -> V(b, tag, [Attr(b, "class", class_name), ..attrs], children)
      }
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: #("Indent", "indent"),
      source: "
                <> Root
                  <> Indent
                  <> p
                    <>
                      'hello'
              ",
      expected: "
                <> Root
                  <> p
                    class=indent
                    <>
                      'hello'
              ",
    ),
    testing.data(
      param: #("Indent", "indent"),
      source: "
                <> Root
                  <> p
                    class=existing
                  <> Indent
                  <> p
              ",
      expected: "
                <> Root
                  <> p
                    class=existing
                  <> p
                    class=indent
              ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
