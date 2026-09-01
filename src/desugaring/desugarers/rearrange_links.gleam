import desugaring/core.{type Desugarer}
import desugaring/rearrange_links_engine as engine
import gleam/string.{inspect as ins}

pub const name = "rearrange_links"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Rearranges links from one raw source prefix to another.
pub fn constructor(param: Param) -> Desugarer {
  engine.constructor_for(name, [param], engine.RawInput, ins(param))
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
  engine.single_assertive_tests(name, constructor)
}
