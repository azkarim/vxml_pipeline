import gleam/option.{type Option, None, Some}
import gleam/regexp.{type Regexp, Match}
import gleam/string
import vxml_pipeline/handle_escaping

pub const decorated_name_pattern = "[\\p{L}\\p{N}\\p{M}_.:'\\-\\^]*[\\p{L}\\p{N}\\p{M}_'\\^](?:#[\\p{L}\\p{N}\\p{M}_:'\\-]+)*"

pub fn encode_value(value: String) -> String {
  "<<" <> value <> ">>"
}

pub fn decode_value(encoded: String) -> Result(String, Nil) {
  case string.starts_with(encoded, "<<") && string.ends_with(encoded, ">>") {
    True ->
      encoded
      |> string.drop_start(2)
      |> string.drop_end(2)
      |> Ok
    False -> Error(Nil)
  }
}

/// Finds the first unescaped `>>##` closer. Backslash runs immediately
/// before a candidate use odd/even parity and are decoded in the value.
/// If there is no active closer, returns `None` and the original input.
pub fn take_explicit_value(
  input: String,
  closer_regexp: Regexp,
) -> #(Option(String), String) {
  case do_take_explicit_value(input, "", closer_regexp) {
    Some(#(value, rest)) -> #(Some(value), rest)
    None -> #(None, input)
  }
}

fn do_take_explicit_value(
  remaining: String,
  done: String,
  closer_regexp: Regexp,
) -> Option(#(String, String)) {
  case regexp.scan(closer_regexp, remaining) {
    [] -> None
    [Match(content, submatches), ..] ->
      case submatches, string.split_once(remaining, content) {
        [backslashes, ..], Ok(#(before, after)) -> {
          let backslashes = option.unwrap(backslashes, "")
          let decoded = handle_escaping.decode_backslashes(backslashes)
          case handle_escaping.is_escaped(backslashes) {
            True ->
              do_take_explicit_value(
                after,
                done <> before <> decoded <> ">>##",
                closer_regexp,
              )
            False -> Some(#(done <> before <> decoded, after))
          }
        }
        _, _ -> None
      }
  }
}
