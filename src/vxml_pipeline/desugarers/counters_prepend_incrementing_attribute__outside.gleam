import gleam/list
import gleam/regexp
import on
import vxml.{type Attr, type VXML, Attr, V}
import vxml/blame as bl
import vxml_pipeline/authoring
import vxml_pipeline/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type TrafficLight, Continue, DesugaringError,
}
import vxml_pipeline/nodemaps_2_transform as n2t
import vxml_pipeline/testing

pub const name = "counters_prepend_incrementing_attribute__outside"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Prepends a temporary counter-increment instruction attr
/// outside configured subtrees. The named counter must already
/// be in scope. Run `counters_substitute` afterward, then delete
/// the temporary `_` attr when it is no longer useful.
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
    // Counter name.
    String,
    // Whether to traverse matching descendants.
    TrafficLight,
  )

type InnerParam =
  #(String, Attr, TrafficLight)

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let #(target_tag, counter_name, traffic_light) = param
  use <- on.false_true(core.valid_tag(target_tag), fn() {
    Error(DesugaringError(
      bl.no_blame,
      "invalid target tag name '" <> target_tag <> "'",
    ))
  })
  let assert Ok(counter_name_regexp) = regexp.from_string("^[A-Za-z]+$")
  use <- on.false_true(regexp.check(counter_name_regexp, counter_name), fn() {
    Error(DesugaringError(
      bl.no_blame,
      "counter name must contain only ASCII letters; found '"
        <> counter_name
        <> "'",
    ))
  })
  Ok(#(
    target_tag,
    Attr(desugarer_blame(43), "_", counter_name <> " ::++" <> counter_name),
    traffic_light,
  ))
}

fn inner_param_to_transform(
  inner: InnerParam,
  outside: List(String),
) -> DesugarerTransform {
  case list.find(outside, fn(tag) { !core.valid_tag(tag) }) {
    Ok(invalid_tag) -> fn(_) {
      Error(DesugaringError(
        bl.no_blame,
        "invalid outside tag name '" <> invalid_tag <> "'",
      ))
    }
    Error(_) -> {
      let nodemap: n2t.EarlyReturnOneToOneNoErrorNodemap = nodemap(_, inner)
      nodemap
      |> n2t.early_return_one_to_one_no_error_nodemap_2_desugarer_transform_with_forbidden(
        outside,
      )
    }
  }
}

fn nodemap(vxml: VXML, inner: InnerParam) -> #(VXML, TrafficLight) {
  case vxml {
    V(_, tag, attrs, _) if tag == inner.0 -> #(
      V(..vxml, attrs: [inner.1, ..attrs]),
      inner.2,
    )
    _ -> #(vxml, Continue)
  }
}

fn desugarer_blame(line_no: Int) {
  authoring.blame(name, line_no)
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestDataWithOutside(Param)) {
  [
    testing.data_with_outside(
      param: #("Item", "ItemCounter", Continue),
      outside: ["Excluded"],
      source: "
                <> root
                  <> Item
                  <> Excluded
                    <> Item
                  <> Included
                    <> Item
                ",
      expected: "
                <> root
                  <> Item
                    _=ItemCounter ::++ItemCounter
                  <> Excluded
                    <> Item
                  <> Included
                    <> Item
                      _=ItemCounter ::++ItemCounter
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection_with_outside(name, assertive_tests_data(), constructor)
}
