import gleam/list
import gleam/string
import splitter.{type Splitter}

/// Shared boundaries for link source text and literal rewrite patterns.
/// Every ASCII punctuation mark, plus common typographic punctuation, is a
/// separate token. Spaces remain explicit so reconstruction preserves spacing.
@internal
pub fn new_splitter() -> Splitter {
  " !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~¡¿«»‘’‚‛“”„‟‐‑‒–—―…‹›、。〈〉《》「」『』【】〔〕（）［］｛｝，．：；！？"
  |> string.to_graphemes
  |> splitter.new
}

@internal
pub fn literal_tokens(text: String) -> List(String) {
  split(new_splitter(), text, [])
}

fn split(
  boundaries: Splitter,
  text: String,
  acc: List(String),
) -> List(String) {
  case splitter.split(boundaries, text) {
    #(_, "", _) -> {
      case text {
        "" -> list.reverse(acc)
        _ -> list.reverse([text, ..acc])
      }
    }
    #("", separator, after) -> split(boundaries, after, [separator, ..acc])
    #(before, separator, after) ->
      split(boundaries, after, [separator, before, ..acc])
  }
}
