import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/dict.{type Dict}
import gleam/list
import on
import vxml.{type VXML, Attr, V}

pub const name = "append_attribute_if_child_of__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Appends configured attributes to matching children of
/// specified parents without replacing existing attributes
/// of the same keys.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer_with_stringified_param(
    name: name,
    param: param,
    stringified_param: core.list_param_stringifier(param),
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  List(
    #(
      // Child tag.
      String,
      // Parent tag.
      String,
      // Attribute key.
      String,
      // Attribute value.
      String,
    ),
  )

type InnerParam =
  Dict(#(String, String), List(#(String, String)))

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  param
  |> core.quads_to_pair_pairs
  |> core.aggregate_on_first
  |> Ok
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.FancyOneToOneNoErrorNodemap = fn(vxml, ancestors, _, _, _) {
    nodemap(vxml, ancestors, inner)
  }
  nodemap
  |> n2t.fancy_one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn nodemap(vxml: VXML, ancestors: List(VXML), inner: InnerParam) -> VXML {
  use blame, tag, attrs, children <- core.on_t_on_v(vxml, fn(_, _) { vxml })

  use parent, _ <- on.empty_nonempty(ancestors, fn() { vxml })

  let assert V(_, parent_tag, _, _) = parent

  use attrs_to_add <- on.error_ok(dict.get(inner, #(tag, parent_tag)), fn(_) {
    vxml
  })

  let old_attr_keys = core.keys(attrs)

  let attrs_to_add =
    list.fold(over: attrs_to_add, from: [], with: fn(so_far, pair) {
      let #(key, value) = pair
      case list.contains(old_attr_keys, key) {
        True -> so_far
        False -> [Attr(blame, key, value), ..so_far]
      }
    })
    |> list.reverse

  V(blame, tag, list.append(attrs, attrs_to_add), children)
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: [#("B", "parent", "key1", "val1")],
      source: "
                <> root
                  <> B
                    <> parent
                  <> parent
                    <> B
                  <> parent
                    <> B
                      key1=val2
                ",
      expected: "
                <> root
                  <> B
                    <> parent
                  <> parent
                    <> B
                      key1=val1
                  <> parent
                    <> B
                      key1=val2
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
