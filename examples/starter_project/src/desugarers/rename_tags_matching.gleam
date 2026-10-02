import gleam/regexp.{type Regexp}
import vxml.{V}
import vxml/blame
import vxml_pipeline/authoring
import vxml_pipeline/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError,
}
import vxml_pipeline/nodemaps_2_transform as n2t
import vxml_pipeline/testing

pub const name = "rename_tags_matching"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// Compiles a regular expression once, then renames every matching tag.
pub fn constructor(param: #(String, String)) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type InnerParam {
  InnerParam(pattern: Regexp, replacement: String)
}

fn param_to_inner_param(
  param: #(String, String),
) -> Result(InnerParam, DesugaringError) {
  case regexp.from_string(param.0) {
    Ok(pattern) -> Ok(InnerParam(pattern, param.1))
    Error(_) ->
      Error(DesugaringError(blame.no_blame, "invalid tag regular expression"))
  }
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = fn(vxml) {
    case vxml {
      V(_, tag, _, _) ->
        case regexp.check(inner.pattern, tag) {
          True -> V(..vxml, tag: inner.replacement)
          False -> vxml
        }
      _ -> vxml
    }
  }
  n2t.one_to_one_no_error_nodemap_2_desugarer_transform(nodemap)
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

pub fn assertive_tests() {
  testing.collection(
    name,
    [
      testing.data(
        param: #("^Callout.*$", "aside"),
        source: "
                <> root
                  <> CalloutNote
                  <> Ordinary
                ",
        expected: "
                <> root
                  <> aside
                  <> Ordinary
                ",
      ),
    ],
    constructor,
  )
}
