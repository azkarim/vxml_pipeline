import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import vxml.{type Line, type VXML, Line, T, V}

pub const name = "concatenate_consecutive_lines_if"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Concatenates consecutive lines when the supplied
/// condition accepts their contents.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  fn(String, String) -> Bool

type InnerParam =
  Param

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  nodemap
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    T(blame, lines) -> {
      let assert [first, ..rest] = lines
      T(blame, lines_folder(inner, [], first, rest))
    }
    V(..) -> vxml
  }
}

fn lines_folder(
  condition: fn(String, String) -> Bool,
  bundled: List(Line),
  current: Line,
  remaining: List(Line),
) -> List(Line) {
  case remaining {
    [] -> [current, ..bundled] |> list.reverse
    [first, ..rest] ->
      case condition(current.content, first.content) {
        False -> lines_folder(condition, [current, ..bundled], first, rest)
        True ->
          lines_folder(
            condition,
            bundled,
            Line(current.blame, current.content <> first.content),
            rest,
          )
      }
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: fn(first, second) { first == "hello " && second == "world" },
      source: "
                <> root
                  <>
                    'hello '
                    'world'
                    'again'
      ",
      expected: "
                <> root
                  <>
                    'hello world'
                    'again'
      ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
