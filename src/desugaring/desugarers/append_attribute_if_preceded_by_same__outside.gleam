import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import vxml.{type VXML, Attr, V}

pub const name = "append_attribute_if_preceded_by_same__outside"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Appends an attribute outside forbidden subtrees when an
/// element has the same tag as its immediately preceding
/// sibling.
pub fn constructor(param: Param, outside: List(String)) -> Desugarer {
  authoring.desugarer_with_outside(
    name: name,
    param: param,
    outside: outside,
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

fn inner_param_to_transform(
  inner: InnerParam,
  outside: List(String),
) -> DesugarerTransform {
  let nodemap: n2t.FancyOneToOneNodemap = fn(node, _, prev_siblings, _, _) {
    nodemap(node, prev_siblings, inner)
  }
  nodemap
  |> n2t.fancy_one_to_one_nodemap_2_desugarer_transform_with_forbidden(outside)
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
      let new_attr = Attr(authoring.blame(name, 66), inner.key, inner.value)
      Ok(V(..vxml, attrs: list.append(attrs, [new_attr])))
    }
    _, _ -> Ok(vxml)
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestDataWithOutside(Param)) {
  [
    testing.data_with_outside(
      param: #("A", "key1", "val1"),
      outside: [],
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
    testing.data_with_outside(
      param: #("A", "key1", "val1"),
      outside: [],
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
  testing.collection_with_outside(name, assertive_tests_data(), constructor)
}
