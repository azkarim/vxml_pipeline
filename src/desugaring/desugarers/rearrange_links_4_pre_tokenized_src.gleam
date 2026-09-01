import desugaring/core.{type Desugarer}
import desugaring/rearrange_links_engine as engine
import desugaring/testing
import gleam/string.{inspect as ins}

pub const name = "rearrange_links_4_pre_tokenized_src"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Rearranges links whose source attributes are already
/// tokenized.
pub fn constructor(param: Param) -> Desugarer {
  engine.constructor_for(name, [param], engine.PreTokenizedInput, ins(param))
}

type Param =
  #(
    // Source prefix to replace.
    String,
    // Replacement prefix.
    String,
  )

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

pub fn assertive_tests() {
  testing.collection(name, [], constructor)
}
