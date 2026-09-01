import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import vxml.{type Line, type VXML, Line, T, V}

pub const name = "delete_empty_lines_before_after"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Removes boundary empty lines from text nodes adjacent to
/// the configured element tags or list boundaries.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  List(String)

type InnerParam =
  Param

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  nodemap |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    T(..) -> vxml
    V(_, _, _, children) ->
      V(..vxml, children: delete_in_list(True, children, inner))
  }
}

fn delete_in_list(
  prev_in_list: Bool,
  remaining: List(VXML),
  inner: InnerParam,
) -> List(VXML) {
  case remaining {
    [T(blame, lines), V(_, tag, _, _) as second, ..rest] -> {
      let lines = case prev_in_list {
        True -> remove_first_line_while_empty(lines)
        False -> lines
      }
      let lines = case list.contains(inner, tag) {
        False -> lines
        True -> remove_last_line_while_empty(lines)
      }
      case lines {
        [] -> delete_in_list(False, [second, ..rest], inner)
        _ -> [T(blame, lines), ..delete_in_list(False, [second, ..rest], inner)]
      }
    }
    [T(blame, lines), T(..) as second, ..rest] -> {
      let lines = case prev_in_list {
        True -> remove_first_line_while_empty(lines)
        False -> lines
      }
      case lines {
        [] -> delete_in_list(False, [second, ..rest], inner)
        _ -> [T(blame, lines), ..delete_in_list(False, [second, ..rest], inner)]
      }
    }
    [T(blame, lines)] -> {
      let lines =
        case prev_in_list {
          True -> remove_first_line_while_empty(lines)
          False -> lines
        }
        |> remove_last_line_while_empty
      case lines {
        [] -> []
        _ -> [T(blame, lines)]
      }
    }
    [V(_, tag, _, _) as first, ..rest] -> [
      first,
      ..delete_in_list(list.contains(inner, tag), rest, inner)
    ]
    [] -> []
  }
}

fn remove_first_line_while_empty(lines: List(Line)) -> List(Line) {
  case lines {
    [Line(_, ""), ..rest] -> remove_first_line_while_empty(rest)
    _ -> lines
  }
}

fn remove_last_line_while_empty(lines: List(Line)) -> List(Line) {
  lines |> list.reverse |> remove_first_line_while_empty |> list.reverse
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  []
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
