import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import vxml.{type VXML, Attr, V}

pub const name = "append_attribute_if_preceded_by_same"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Appends an attribute when an element has the same tag as
/// its immediately preceding sibling.
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
    // Attribute value.
    String,
  )

type InnerParam {
  InnerParam(target_tag: String, key: String, value: String)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(InnerParam(param.0, param.1, param.2))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.FancyOneToOneNodemap = fn(node, _, prev_siblings, _, _) {
    nodemap(node, prev_siblings, inner)
  }
  nodemap
  |> n2t.fancy_one_to_one_nodemap_2_desugarer_transform
}

fn nodemap(
  vxml: VXML,
  previous_unmapped_siblings: List(VXML),
  inner: InnerParam,
) -> Result(VXML, DesugaringError) {
  case vxml, previous_unmapped_siblings {
    V(_, tag, attrs, _), [V(_, prev_tag, _, _), ..]
      if tag == inner.target_tag && prev_tag == inner.target_tag
    -> {
      let new_attr = Attr(authoring.blame(name, 61), inner.key, inner.value)
      Ok(V(..vxml, attrs: list.append(attrs, [new_attr])))
    }
    _, _ -> Ok(vxml)
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: #("A", "key1", "val1"),
      source: "
                <> root
                  <> A
                  <> A
                  <> B
                  <> A
                ",
      expected: "
                <> root
                  <> A
                  <> A
                    key1=val1
                  <> B
                  <> A
                ",
    ),
    testing.data(
      param: #("A", "key1", "val1"),
      source: "
                <> root
                  <> B
                  <> B
                  <> A
                  <> A
                  <> A
                ",
      expected: "
                <> root
                  <> B
                  <> B
                  <> A
                  <> A
                    key1=val1
                  <> A
                    key1=val1
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
