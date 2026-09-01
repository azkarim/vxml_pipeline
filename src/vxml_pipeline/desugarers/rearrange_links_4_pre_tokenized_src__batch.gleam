import gleam/string.{inspect as ins}
import vxml_pipeline/core.{type Desugarer}
import vxml_pipeline/rearrange_links_engine as engine
import vxml_pipeline/testing

pub const name = "rearrange_links_4_pre_tokenized_src__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Rearranges multiple link prefixes whose source
/// attributes are already tokenized.
pub fn constructor(param: engine.Param) -> Desugarer {
  engine.constructor_for(name, param, engine.PreTokenizedInput, ins(param))
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

pub fn assertive_tests() {
  testing.collection(name, [], constructor)
}
