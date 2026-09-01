import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import gleam/string
import on
import vxml.{type VXML, T}

pub const name = "reassign_text_node_blame_to_blame_of_first_nonempty_line_in_text_node"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Reassigns each text node's blame to that of its first
/// nonempty line.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(Nil),
  )
}

type InnerParam =
  Nil

fn inner_param_to_transform(_inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNodemap = nodemap
  nodemap
  |> n2t.one_to_one_nodemap_2_desugarer_transform
}

fn nodemap(vxml: VXML) -> Result(VXML, DesugaringError) {
  case vxml {
    T(_, lines) -> {
      use first_nonempty <- on.error_ok(
        list.find(lines, fn(line) { !string.is_empty(line.content) }),
        on_error: fn(_) { Ok(vxml) },
      )
      Ok(T(first_nonempty.blame, lines))
    }
    _ -> Ok(vxml)
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestDataNoParam) {
  []
}

pub fn assertive_tests() {
  testing.collection_no_param(name, assertive_tests_data(), constructor)
}
