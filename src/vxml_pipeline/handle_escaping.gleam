//// Shared backslash-parity rules for handle operators.

import gleam/int
import gleam/string

@internal
pub fn is_escaped(backslashes: String) -> Bool {
  string.length(backslashes) % 2 == 1
}

@internal
pub fn decode_backslashes(backslashes: String) -> String {
  let assert Ok(count) = int.floor_divide(string.length(backslashes), 2)
  string.repeat("\\", count)
}
