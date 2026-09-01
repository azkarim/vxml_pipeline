import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import gleam/option
import on
import vxml.{type VXML, T, V}
import vxml/blame.{type Blame}

pub const name = "wrap_adjacent_non_whitespace_text_with"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// Wraps configured elements together with adjacent
/// non-whitespace text; leaves them unchanged when no
/// adjacent text is found.
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
    // Tags to wrap.
    List(String),
    // Wrapper tag.
    String,
  )

type InnerParam {
  InnerParam(to_be_wrapped: List(String), wrapper: String)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let #(to_be_wrapped, wrapper) = param
  Ok(InnerParam(to_be_wrapped, wrapper))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = fn(vxml) { nodemap(vxml, inner) }
  nodemap |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform
}

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    V(blame, _, _, children) ->
      V(..vxml, children: process_children(blame, children, inner))
    T(..) -> vxml
  }
}

fn process_children(
  blame: Blame,
  children: List(VXML),
  inner: InnerParam,
) -> List(VXML) {
  [V(blame, "Dummy", [], []), ..children]
  |> wrap_second_element_and_recurse(inner)
  |> list.drop(1)
}

fn wrap_second_element_and_recurse(
  children: List(VXML),
  inner: InnerParam,
) -> List(VXML) {
  use first, after_first <- on.eager_empty_nonempty(children, [])
  use second, after_second <- on.eager_empty_nonempty(after_first, children)
  use <- on.false_true(
    core.is_v_and_tag_is_one_of(second, inner.to_be_wrapped),
    fn() {
      [
        first,
        ..wrap_second_element_and_recurse([second, ..after_second], inner)
      ]
    },
  )

  let #(first, last_word_of_first) =
    core.extract_last_word_from_t_node_if_t(first)

  use third, after_third <- on.empty_nonempty(after_second, fn() {
    case last_word_of_first {
      option.None -> [
        first,
        ..wrap_second_element_and_recurse([second, ..after_second], inner)
      ]
      option.Some(t_node) -> [
        first,
        V(second.blame, inner.wrapper, [], [t_node, second]),
        ..wrap_second_element_and_recurse(after_second, inner)
      ]
    }
  })

  let #(first_word_of_third, third) =
    core.extract_first_word_from_t_node_if_t(third)

  case
    option.is_some(last_word_of_first) || option.is_some(first_word_of_third)
  {
    True -> [
      first,
      V(
        second.blame,
        inner.wrapper,
        [],
        [last_word_of_first, option.Some(second), first_word_of_third]
          |> option.values,
      ),
      ..wrap_second_element_and_recurse([third, ..after_third], inner)
    ]
    False -> [
      first,
      ..wrap_second_element_and_recurse([second, ..after_second], inner)
    ]
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: #(["Math"], "NoWrap"),
      source: "
                <> root
                  <>
                    'before —'
                  <> Math
                    <>
                      'x'
                  <>
                    ', after'
                ",
      expected: "
                <> root
                  <>
                    'before '
                  <> NoWrap
                    <>
                      '—'
                    <> Math
                      <>
                        'x'
                    <>
                      ','
                  <>
                    ' after'
                ",
    ),
    testing.data(
      param: #(["Math"], "NoWrap"),
      source: "
                <> root
                  <> Before
                  <> Math
                  <> After
                ",
      expected: "
                <> root
                  <> Before
                  <> Math
                  <> After
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
