import gleam/string.{inspect as ins}
import vxml_pipeline/core.{type Desugarer}
import vxml_pipeline/rearrange_links_engine as engine

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
