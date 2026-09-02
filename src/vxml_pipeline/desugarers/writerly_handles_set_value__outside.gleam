import gleam/list
import gleam/option.{Some}
import gleam/regexp.{type Regexp, Match}
import gleam/result
import vxml.{type Attr, type VXML, Attr, V}
import vxml_pipeline/authoring
import vxml_pipeline/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type TrafficLight, Continue, DesugaringError, GoBack,
}
import vxml_pipeline/handle_syntax
import vxml_pipeline/nodemaps_2_transform as n2t
import vxml_pipeline/testing

pub const name = "writerly_handles_set_value__outside"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Appends handle values outside configured subtrees,
/// with configurable traversal.
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
    // Handle value to append.
    String,
    // Whether to traverse matching descendants.
    TrafficLight,
  )

type InnerParam {
  InnerParam(
    target_tag: String,
    value: String,
    traffic_light: TrafficLight,
    handle_regexp: Regexp,
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let assert Ok(handle_regexp) =
    regexp.from_string(
      "^(" <> handle_syntax.decorated_name_pattern <> ")(?: <<(.*)>>)?$",
    )
  Ok(InnerParam(param.0, param.1, param.2, handle_regexp))
}

fn inner_param_to_transform(
  inner: InnerParam,
  outside: List(String),
) -> DesugarerTransform {
  let nodemap: n2t.EarlyReturnOneToOneNodemap = nodemap(_, inner, outside)
  nodemap
  |> n2t.early_return_one_to_one_nodemap_2_desugarer_transform
}

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
  outside: List(String),
) -> Result(#(VXML, TrafficLight), DesugaringError) {
  case vxml {
    V(_, tag, attrs, _) ->
      case list.contains(outside, tag) {
        True -> Ok(#(vxml, GoBack))
        False ->
          case tag == inner.target_tag {
            True -> {
              use attrs <- result.try(list.try_map(attrs, map_attr(_, inner)))
              Ok(#(V(..vxml, attrs: attrs), inner.traffic_light))
            }
            False -> Ok(#(vxml, Continue))
          }
      }
    _ -> Ok(#(vxml, Continue))
  }
}

fn map_attr(attr: Attr, inner: InnerParam) -> Result(Attr, DesugaringError) {
  case attr.key {
    "handle" ->
      case regexp.scan(inner.handle_regexp, attr.val) {
        [Match(_, [Some(_)]), ..] ->
          Ok(
            Attr(
              ..attr,
              val: attr.val <> " " <> handle_syntax.encode_value(inner.value),
            ),
          )
        [Match(_, [Some(_), _]), ..] -> Ok(attr)
        _ -> Error(malformed_handle_error(attr))
      }
    _ -> Ok(attr)
  }
}

fn malformed_handle_error(attr: Attr) -> DesugaringError {
  DesugaringError(
    attr.blame,
    "handle attr must have form <name> or <name> <<value>>; found: “"
      <> attr.val
      <> "”",
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestDataWithOutside(Param)) {
  [
    testing.data_with_outside(
      param: #("Section", "generated value", Continue),
      outside: ["Code"],
      source: "
        <> root
          <> Section
            handle=first#page
          <> Section
            handle=second <<existing>>
          <> Code
            <> Section
              handle=not/validated
      ",
      expected: "
        <> root
          <> Section
            handle=first#page <<generated value>>
          <> Section
            handle=second <<existing>>
          <> Code
            <> Section
              handle=not/validated
      ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection_with_outside(name, assertive_tests_data(), constructor)
}
