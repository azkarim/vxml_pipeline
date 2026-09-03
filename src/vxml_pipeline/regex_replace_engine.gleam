//// Shared compiled-regexp implementation for regex-replacement desugarers.

import gleam/list
import gleam/regexp.{type Regexp}
import vxml.{type VXML, Line, T}
import vxml/blame as bl
import vxml_pipeline/core.{type DesugaringError, DesugaringError}

/// A compiled regular expression and its replacement text.
@internal
pub type Rule =
  #(Regexp, String)

/// Compiles one `(pattern, replacement)` parameter pair.
@internal
pub fn prepare(param: #(String, String)) -> Result(Rule, DesugaringError) {
  let #(pattern, replacement) = param
  case regexp.from_string(pattern) {
    Ok(compiled) -> Ok(#(compiled, replacement))
    Error(_) ->
      Error(DesugaringError(bl.no_blame, "Invalid regex: " <> pattern))
  }
}

/// Compiles a batch of `(pattern, replacement)` parameter pairs.
@internal
pub fn prepare_batch(
  param: List(#(String, String)),
) -> Result(List(Rule), DesugaringError) {
  list.try_map(param, prepare)
}

/// Applies one compiled replacement rule to a text node.
///
/// V-nodes are returned unchanged.
@internal
pub fn nodemap(vxml: VXML, rule: Rule) -> VXML {
  nodemap_batch(vxml, [rule])
}

/// Applies compiled replacement rules in order to a text node.
///
/// V-nodes are returned unchanged.
@internal
pub fn nodemap_batch(vxml: VXML, rules: List(Rule)) -> VXML {
  case vxml {
    T(_, lines) ->
      T(
        ..vxml,
        lines: list.map(lines, fn(line) {
          Line(
            ..line,
            content: list.fold(rules, line.content, fn(content, rule) {
              regexp.replace(rule.0, content, rule.1)
            }),
          )
        }),
      )
    _ -> vxml
  }
}
