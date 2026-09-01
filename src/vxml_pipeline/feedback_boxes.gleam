import gleam/int
import gleam/list
import gleam/string
import on

fn wrap(message: String, max_line_length: Int) -> List(String) {
  let len = string.length(message)
  use <- on.true_false(len < max_line_length, on_true: fn() { [message] })
  let shortest = max_line_length * 3 / 5
  let #(current_start, current_end, remaining) = #(
    string.slice(message, 0, shortest),
    string.slice(message, shortest, max_line_length - shortest),
    string.slice(message, max_line_length, len),
  )
  case string.split_once(current_end |> string.reverse, " ") {
    Ok(#(before, after)) -> [
      current_start <> { after |> string.reverse },
      ..wrap({ before |> string.reverse } <> remaining, max_line_length)
    ]
    _ -> [current_start <> current_end, ..wrap(remaining, max_line_length)]
  }
}

fn dash_banner(title: String, width: Int) -> String {
  let side = { width - string.length(title) } / 2
  string.repeat("-", side)
  <> title
  <> string.repeat("-", width - string.length(title) - side)
}

pub fn error_announcement(
  fields: List(#(String, String)),
  first_column_min: Int,
  message_column_min: Int,
  emoji: String,
  margin: Int,
  banner: String,
) -> String {
  let longest_first =
    fields
    |> list.map(fn(field) { string.length(field.0) })
    |> list.fold(0, int.max)
  let first_column = int.max(first_column_min, longest_first + 1)
  let firsts =
    list.map(fields, fn(field) { string.pad_end(field.0, first_column, " ") })
  let #(longest_message, messages) =
    list.map_fold(fields, 0, fn(acc, field) {
      let lines = wrap(field.1, message_column_min)
      let assert Ok(longest) =
        list.map(lines, string.length) |> list.max(int.compare)
      #(int.max(longest, acc), lines)
    })
  let message_column = int.max(longest_message + 1, message_column_min + 1)
  let margin = string.repeat(" ", margin)
  let emojis = string.repeat(emoji, 2)
  let line_width = string.length(margin) + 2 + first_column + message_column
  let box_width = first_column + message_column - 2
  let opening =
    margin <> emojis <> " " <> dash_banner(banner, box_width) <> " " <> emojis
  let closing =
    margin <> emojis <> " " <> string.repeat("-", box_width) <> " " <> emojis
  let continuation_margin = string.repeat(" ", first_column)
  let content =
    list.map2(firsts, messages, fn(first, message_lines) {
      let assert [first_message, ..remaining_messages] = message_lines
      let first_line =
        string.pad_end(
          margin <> emojis <> first <> first_message,
          line_width,
          " ",
        )
        <> emojis
      let remaining_lines =
        list.map(remaining_messages, fn(message) {
          margin
          <> emojis
          <> continuation_margin
          <> string.pad_end(message, message_column, " ")
          <> emojis
        })
      [first_line, ..remaining_lines]
    })
    |> list.flatten
  [opening, ..content]
  |> list.append([closing])
  |> string.join("\n")
}

pub fn mushroom_error_announcement(
  title: String,
  fields: List(#(String, String)),
) -> String {
  error_announcement(fields, 0, 68, "🍄", 2, "/ " <> title <> " /")
}
