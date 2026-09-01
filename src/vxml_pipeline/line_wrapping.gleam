import gleam/list
import gleam/pair
import gleam/string
import vxml.{type Line, Line}
import vxml/blame.{type Blame} as bl

// line wrapping
// ************************************************************

type RewrapToken {
  RewrapToken(content: String, blame: Blame)
}

type RewrapState {
  RewrapState(
    wrapped_lines_rev: List(Line),
    current_tokens_rev: List(String),
    current_line_blame: Blame,
    current_content_width: Int,
    occupied_width_before_text: Int,
    max_line_width: Int,
  )
}

fn line_to_rewrap_tokens(line: Line) -> List(RewrapToken) {
  line.content
  |> string.split(" ")
  |> list.map_fold(line.blame, fn(token_blame, content) {
    #(
      bl.advance(token_blame, string.length(content) + 1),
      RewrapToken(content, token_blame),
    )
  })
  |> pair.second
}

fn current_line(state: RewrapState) -> Line {
  Line(
    state.current_line_blame,
    state.current_tokens_rev |> list.reverse |> string.join(" "),
  )
}

fn add_token_to_current_line(
  state: RewrapState,
  token: RewrapToken,
  separator_width: Int,
) -> RewrapState {
  RewrapState(
    ..state,
    current_tokens_rev: [token.content, ..state.current_tokens_rev],
    current_content_width: state.current_content_width
      + separator_width
      + string.length(token.content),
  )
}

fn start_new_line(state: RewrapState, token: RewrapToken) -> RewrapState {
  RewrapState(
    wrapped_lines_rev: [current_line(state), ..state.wrapped_lines_rev],
    current_tokens_rev: [token.content],
    current_line_blame: token.blame,
    current_content_width: string.length(token.content),
    occupied_width_before_text: 0,
    max_line_width: state.max_line_width,
  )
}

fn rewrap_tokens(
  remaining_tokens: List(RewrapToken),
  state: RewrapState,
) -> RewrapState {
  case remaining_tokens {
    [] -> state
    [token, ..rest] -> {
      let current_line_is_empty = list.is_empty(state.current_tokens_rev)
      let separator_width = case current_line_is_empty {
        True -> 0
        False -> 1
      }
      let width_with_token =
        state.occupied_width_before_text
        + state.current_content_width
        + separator_width
        + string.length(token.content)

      case current_line_is_empty || width_with_token <= state.max_line_width {
        True ->
          rewrap_tokens(
            rest,
            add_token_to_current_line(state, token, separator_width),
          )
        False -> rewrap_tokens(rest, start_new_line(state, token))
      }
    }
  }
}

pub fn rewrap_lines(
  lines: List(Line),
  occupied_width_before_text: Int,
  max_line_width: Int,
) -> #(List(Line), Int) {
  // 🚨
  // right now there is no option to protect empty first line
  // or to protect empty last line; these will be sucked in & create leading and
  // trailing spaces instead on the next & previous lines respectively;
  // we apparently don't need this protection functionality, so far
  // 🚨
  let tokens = lines |> list.flat_map(line_to_rewrap_tokens)
  case tokens {
    [] -> #([], occupied_width_before_text)
    [first, ..rest] -> {
      let initial_state =
        RewrapState(
          wrapped_lines_rev: [],
          current_tokens_rev: [first.content],
          current_line_blame: first.blame,
          current_content_width: string.length(first.content),
          occupied_width_before_text: occupied_width_before_text,
          max_line_width: max_line_width,
        )
      let final_state = rewrap_tokens(rest, initial_state)
      let wrapped_lines =
        [current_line(final_state), ..final_state.wrapped_lines_rev]
        |> list.reverse
      let final_width =
        final_state.occupied_width_before_text
        + final_state.current_content_width
      #(wrapped_lines, final_width)
    }
  }
}
