import gleam/string.{inspect as ins}
import vxml_pipeline/core.{type Desugarer}
import vxml_pipeline/rearrange_links_engine as engine

pub const name = "rearrange_links__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Rearranges multiple link prefixes from raw source
/// attributes.
pub fn constructor(param: engine.Param) -> Desugarer {
  engine.constructor_for(name, param, engine.RawInput, ins(param))
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

pub fn assertive_tests() {
  engine.assertive_tests()
}
