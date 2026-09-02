import gleam/list
import gleam/regexp
import on
import vxml.{type Attr, type VXML, Attr, V}
import vxml/blame as bl
import vxml_pipeline/authoring
import vxml_pipeline/core.{
  type ContextualVXMLCondition, type Desugarer, type DesugarerTransform,
  type DesugaringError, type TrafficLight, Continue, DesugaringError,
}
import vxml_pipeline/nodemaps_2_transform as n2t
import vxml_pipeline/testing

pub const name = "sigil_counters_prepend_incrementing_attribute_if_fancy"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Prepends a temporary counter-increment instruction attr when
/// a contextual condition is satisfied. The named counter must
/// already be in scope. Run `sigil_counters_substitute__outside` afterward, then
/// delete the temporary `_` attr when it is no longer useful.
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
    // Counter name.
    String,
    // Contextual condition.
    ContextualVXMLCondition,
    // Whether to traverse matching descendants.
    TrafficLight,
  )

type InnerParam {
  InnerParam(
    target_tag: String,
    attribute: Attr,
    condition: ContextualVXMLCondition,
    traffic_light: TrafficLight,
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let #(target_tag, counter_name, condition, traffic_light) = param
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
  Ok(InnerParam(
    target_tag,
    Attr(desugarer_blame(73), "_", counter_name <> " ::++" <> counter_name),
    condition,
    traffic_light,
  ))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.EarlyReturnFancyOneToOneNoErrorNodemap = fn(
    vxml,
    ancestors,
    previous_siblings_before_mapping,
    previous_siblings_after_mapping,
    following_siblings_before_mapping,
  ) {
    nodemap(
      vxml,
      ancestors,
      previous_siblings_before_mapping,
      previous_siblings_after_mapping,
      following_siblings_before_mapping,
      inner,
    )
  }
  nodemap
  |> n2t.early_return_fancy_one_to_one_no_error_nodemap_2_desugarer_transform
}

fn nodemap(
  vxml: VXML,
  ancestors: List(VXML),
  previous_siblings_before_mapping: List(VXML),
  previous_siblings_after_mapping: List(VXML),
  following_siblings_before_mapping: List(VXML),
  inner: InnerParam,
) -> #(VXML, TrafficLight) {
  case vxml {
    V(_, tag, attrs, _) if tag == inner.target_tag -> {
      case
        inner.condition(
          vxml,
          ancestors,
          previous_siblings_before_mapping,
          previous_siblings_after_mapping,
          following_siblings_before_mapping,
        )
      {
        True -> #(
          V(..vxml, attrs: [inner.attribute, ..attrs]),
          inner.traffic_light,
        )
        False -> #(vxml, Continue)
      }
    }
    _ -> #(vxml, Continue)
  }
}

fn desugarer_blame(line_no: Int) {
  authoring.blame(name, line_no)
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: #(
        "Item",
        "ItemCounter",
        fn(_, _, previous_siblings, _, _) { !list.is_empty(previous_siblings) },
        core.GoBack,
      ),
      source: "
                <> root
                  <> Item
                  <> Item
                    <> Item
                ",
      expected: "
                <> root
                  <> Item
                  <> Item
                    _=ItemCounter ::++ItemCounter
                    <> Item
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
