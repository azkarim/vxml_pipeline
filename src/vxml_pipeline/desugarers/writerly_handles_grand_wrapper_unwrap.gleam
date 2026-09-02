import gleam/int
import gleam/list
import vxml.{V}
import vxml_pipeline/authoring
import vxml_pipeline/core.{
  type Desugarer, type DesugarerTransform, DesugaringError,
}
import vxml_pipeline/testing

pub const name = "writerly_handles_grand_wrapper_unwrap"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Removes a root 'GrandWrapper' and its 'Handle'
/// dictionary children, requiring exactly one other child.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(),
  )
}

fn inner_param_to_transform() -> DesugarerTransform {
  fn(vxml) {
    case vxml {
      V(_, "GrandWrapper", _, children) -> {
        let roots =
          list.filter(children, fn(child) {
            case child {
              V(_, "Handle", _, _) -> False
              _ -> True
            }
          })
        case roots {
          [root] -> Ok(#(root, []))
          [] ->
            Error(DesugaringError(
              vxml.blame,
              "GrandWrapper has no non-Handle root child",
            ))
          roots -> {
            let count = roots |> list.length |> int.to_string
            Error(DesugaringError(
              vxml.blame,
              "GrandWrapper has "
                <> count
                <> " non-Handle root children; expected exactly 1",
            ))
          }
        }
      }
      _ ->
        Error(DesugaringError(
          vxml.blame,
          "expected GrandWrapper at document root",
        ))
    }
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestDataNoParam) {
  [
    testing.data_no_param(
      source: "
        <> GrandWrapper
          <> Handle
            name=first
          <> Handle
            name=second
          <> root
            <> Chapter
      ",
      expected: "
        <> root
          <> Chapter
      ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection_no_param(name, assertive_tests_data(), constructor)
}
