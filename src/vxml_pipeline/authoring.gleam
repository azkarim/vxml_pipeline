//// Constructors and blame helpers for client-authored desugarers.
////
//// A parameterized desugarer normally has two construction phases. `prepare`
//// validates its public parameter and performs reusable work such as compiling
//// regular expressions or building dictionaries. It returns an inner
//// parameter, which `transform` captures in the VXML transformation function.
//// Preparation occurs once when the pipeline is constructed, not once per
//// visited VXML node.

import gleam/option
import gleam/string
import vxml/blame.{type Blame, Des}
import vxml_pipeline/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, Desugarer,
}

/// Constructs a parameterized desugarer with fallible parameter preparation.
///
/// The parameter is represented in diagnostic pipeline tables with
/// `string.inspect`. If `prepare` fails, the resulting desugarer returns that
/// error whenever the pipeline attempts to run it.
pub fn desugarer(
  name name: String,
  param param: a,
  prepare prepare: fn(a) -> Result(b, DesugaringError),
  transform transform: fn(b) -> DesugarerTransform,
) -> Desugarer {
  desugarer_with_stringified_param(
    name: name,
    param: param,
    stringified_param: string.inspect(param),
    prepare: prepare,
    transform: transform,
  )
}

/// Constructs a parameterized desugarer with a caller-supplied diagnostic
/// representation of its parameter.
pub fn desugarer_with_stringified_param(
  name name: String,
  param param: a,
  stringified_param stringified_param: String,
  prepare prepare: fn(a) -> Result(b, DesugaringError),
  transform transform: fn(b) -> DesugarerTransform,
) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(stringified_param),
    stringified_outside: option.None,
    transform: case prepare(param) {
      Ok(prepared) -> transform(prepared)
      Error(error) -> fn(_) { Error(error) }
    },
  )
}

/// Constructs a parameterized `__outside` desugarer.
///
/// `outside` is recorded separately in diagnostic pipeline tables and passed
/// unchanged to `transform`. The constructor validates and prepares only
/// `param`.
pub fn desugarer_with_outside(
  name name: String,
  param param: a,
  outside outside: b,
  prepare prepare: fn(a) -> Result(c, DesugaringError),
  transform transform: fn(c, b) -> DesugarerTransform,
) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(string.inspect(param)),
    stringified_outside: option.Some(string.inspect(outside)),
    transform: case prepare(param) {
      Ok(prepared) -> transform(prepared, outside)
      Error(error) -> fn(_) { Error(error) }
    },
  )
}

/// Constructs a parameterized desugarer that requires no fallible preparation.
///
/// Use this when the public parameter can be captured directly by the
/// transform factory.
pub fn infallible_desugarer(
  name name: String,
  param param: a,
  transform transform: fn(a) -> DesugarerTransform,
) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(string.inspect(param)),
    stringified_outside: option.None,
    transform: transform(param),
  )
}

/// Constructs a desugarer that has no public parameter.
pub fn no_param_desugarer(
  name name: String,
  transform transform: DesugarerTransform,
) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.None,
    stringified_outside: option.None,
    transform: transform,
  )
}

/// Constructs a parameterless `__outside` desugarer.
///
/// The outside-tag list is the desugarer's only constructor input and is shown
/// in the outside column of diagnostic pipeline tables.
pub fn no_param_desugarer_with_outside(
  name name: String,
  outside outside: a,
  transform transform: fn(a) -> DesugarerTransform,
) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.None,
    stringified_outside: option.Some(string.inspect(outside)),
    transform: transform(outside),
  )
}

/// Creates desugarer blame for a value introduced at `line_no` in the named
/// desugarer module.
pub fn blame(name: String, line_no: Int) -> Blame {
  Des([], name, line_no)
}
