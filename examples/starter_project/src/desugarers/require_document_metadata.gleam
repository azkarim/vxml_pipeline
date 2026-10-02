import gleam/list
import vxml.{T, V}
import vxml_pipeline/authoring
import vxml_pipeline/core.{
  type Desugarer, type DesugarerTransform, DesugaringError,
}
import vxml_pipeline/nodemaps_2_transform as n2t
import vxml_pipeline/testing

pub const name = "require_document_metadata"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// Requires the document root to carry each named metadata key.
pub fn constructor(param: List(String)) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: fn(param) { Ok(param) },
    transform: inner_param_to_transform,
  )
}

fn inner_param_to_transform(required: List(String)) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNodemap = fn(vxml) {
    case vxml {
      T(_, _) -> Ok(vxml)
      V(blame, "Document", attrs, _) -> {
        let missing =
          required
          |> list.filter(fn(key) {
            !list.any(attrs, fn(attr) { attr.key == key })
          })
        case missing {
          [] -> Ok(vxml)
          [key, ..] ->
            Error(DesugaringError(
              blame,
              "Document is missing metadata key '" <> key <> "'",
            ))
        }
      }
      _ -> Ok(vxml)
    }
  }
  n2t.one_to_one_nodemap_2_desugarer_transform(nodemap)
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

pub fn assertive_tests() {
  testing.collection(
    name,
    [
      testing.data(
        param: ["title", "author"],
        source: "
                <> Document
                  title=Example
                  author=A. Writer
                ",
        expected: "
                <> Document
                  title=Example
                  author=A. Writer
                ",
      ),
    ],
    constructor,
  )
}
