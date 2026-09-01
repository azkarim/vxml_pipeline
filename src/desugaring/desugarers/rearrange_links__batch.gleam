import desugaring/core.{type Desugarer}
import desugaring/rearrange_links_engine as engine
import gleam/string.{inspect as ins}

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
