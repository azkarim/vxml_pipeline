import desugaring/core.{type Desugarer}
import either_or.{type EitherOr, Either, Or}
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/string.{inspect as ins}
import vxml/blame.{type Blame} as bl

pub fn dashes(num: Int) -> String {
  string.repeat("-", num)
}

pub fn solid_dashes(num: Int) -> String {
  string.repeat("─", num)
}

pub fn spaces(num: Int) -> String {
  string.repeat(" ", num)
}

pub fn dots(num: Int) -> String {
  string.repeat(".", num)
}

pub fn threedots(num: Int) -> String {
  string.repeat("…", num)
}

pub fn twodots(num: Int) -> String {
  string.repeat("‥", num)
}

pub fn underscores(num: Int) -> String {
  string.repeat("_", num)
}

pub fn blocks(num: Int) -> String {
  string.repeat("█", num)
}

pub fn how_many(singular: String, plural: String, count: Int) -> String {
  case count {
    1 -> "1 " <> singular
    _ -> ins(count) <> " " <> plural
  }
}

pub type TableCell {
  TableCell(content: String, fill: String)
}

pub type TableRow {
  Cells(List(TableCell))
  SpanningRow(content: String, fill: String)
}

pub type ColumnStyle {
  ColumnStyle(padding_right: Int)
}

fn table_column_widths(
  rows: List(TableRow),
  columns: List(ColumnStyle),
) -> List(Int) {
  list.fold(rows, list.map(columns, fn(_) { 0 }), fn(widths, row) {
    case row {
      SpanningRow(..) -> widths
      Cells(cells) -> {
        assert list.length(cells) == list.length(columns)
        list.map2(widths, cells, fn(width, cell) {
          int.max(width, string.length(cell.content))
        })
      }
    }
  })
}

fn table_border(
  left: String,
  join: String,
  right: String,
  widths: List(Int),
  columns: List(ColumnStyle),
) -> String {
  let segments =
    list.map2(widths, columns, fn(width, column) {
      solid_dashes(width + column.padding_right)
    })
  left <> string.join(segments, join) <> right
}

fn render_table_row(
  row: TableRow,
  widths: List(Int),
  columns: List(ColumnStyle),
  total_width: Int,
) -> String {
  case row {
    Cells(cells) -> {
      let cells =
        list.map2(list.zip(cells, widths), columns, fn(pair, column) {
          let #(cell, width) = pair
          "│ "
          <> cell.content
          <> string.repeat(
            cell.fill,
            width - string.length(cell.content) + column.padding_right,
          )
        })
      string.concat(cells) <> "│"
    }
    SpanningRow(content, fill) -> {
      let remaining = int.max(0, total_width - string.length(content))
      let left_width = remaining / 2
      let right_width = remaining - left_width
      string.repeat(fill, left_width)
      <> content
      <> string.repeat(fill, right_width)
    }
  }
}

/// Render a boxed table whose first row is its header.
pub fn table(rows: List(TableRow), columns: List(ColumnStyle)) -> List(String) {
  case rows {
    [] -> []
    [first, ..rest] -> {
      let widths = table_column_widths(rows, columns)
      let total_width =
        list.map2(widths, columns, fn(width, column) {
          width + column.padding_right + 2
        })
        |> list.fold(1, int.add)
      let render = render_table_row(_, widths, columns, total_width)
      [
        table_border("┌─", "┬─", "┐", widths, columns),
        render(first),
        table_border("├─", "┼─", "┤", widths, columns),
        ..list.append(list.map(rest, render), [
          table_border("└─", "┴─", "┘", widths, columns),
        ])
      ]
    }
  }
}

fn cell(content: String) -> TableCell {
  TableCell(content, " ")
}

pub fn two_column_maxes(lines: List(#(String, String))) -> #(Int, Int) {
  list.fold(lines, #(0, 0), fn(acc, pair) {
    #(
      int.max(acc.0, string.length(pair.0)),
      int.max(acc.1, string.length(pair.1)),
    )
  })
}

pub fn two_column_table(lines: List(#(String, String))) -> List(String) {
  lines
  |> list.map(fn(row) { Cells([cell(row.0), cell(row.1)]) })
  |> table([ColumnStyle(2), ColumnStyle(2)])
}

pub fn three_column_table(
  lines: List(EitherOr(#(String, String, String), String)),
) -> List(String) {
  lines
  |> list.map(fn(row) {
    case row {
      Either(row) -> Cells([cell(row.0), cell(row.1), cell(row.2)])
      Or(content) -> SpanningRow(content, string.slice(content, 0, 1))
    }
  })
  |> table([ColumnStyle(1), ColumnStyle(2), ColumnStyle(1)])
}

pub fn four_column_table(
  lines: List(EitherOr(#(String, String, String, String), String)),
) -> List(String) {
  lines
  |> list.index_map(fn(row, index) {
    case row {
      Either(row) ->
        Cells([
          cell(row.0),
          TableCell(row.1, case index {
            0 -> " "
            n if n % 2 == 0 -> "."
            _ -> "_"
          }),
          cell(row.2),
          cell(row.3),
        ])
      Or(content) -> SpanningRow(content, string.slice(content, 0, 1))
    }
  })
  |> table([ColumnStyle(1), ColumnStyle(2), ColumnStyle(1), ColumnStyle(1)])
}

pub fn print_lines_at_indent(lines: List(String), indent: Int) -> Nil {
  let margin = spaces(indent)
  list.each(lines, fn(l) { io.println(margin <> l) })
}

// ************************
// desugarer
// ************************

pub fn name_and_param_string_lines(
  desugarer: Desugarer,
  step_no: Int,
  margin: Int,
) -> List(String) {
  let #(first_line, batch_params) = {
    let start = ins(step_no) <> ". " <> desugarer.name
    let #(end, more) = {
      case desugarer.stringified_param {
        None -> #(
          case desugarer.stringified_outside {
            None -> ""
            _ -> " []"
          },
          [],
        )
        Some(desc) ->
          case string.split(desc, "\n") {
            [desc] -> {
              let end =
                " "
                <> {
                  ins(desc)
                  |> string.drop_start(1)
                  |> string.drop_end(1)
                  |> string.replace("\\\"", "\"")
                }
              #(end, [])
            }
            [first, ..rest] -> {
              // assert string.starts_with(first, "[ ")
              let first = string.drop_start(first, 2)
              let assert [last, ..rest] = [first, ..rest] |> list.reverse
              case string.ends_with(last, "]") {
                True -> Nil
                False -> {
                  io.println(
                    "bad stringified param at step_no: " <> ins(step_no),
                  )
                  io.println(
                    desugarer.stringified_param |> option.unwrap("None")
                    <> "[end]",
                  )
                  io.println(
                    desugarer.stringified_outside |> option.unwrap("None")
                    <> "[end]",
                  )
                  panic
                }
              }
              let last = string.drop_end(last, 2)
              let more = [last, ..rest] |> list.reverse
              #(" [", more)
            }
            _ ->
              panic as "not expecting the non-None stringified_param to be the empty string"
          }
      }
    }
    #(start <> end, more)
  }

  let so_far = case batch_params {
    [] -> [first_line]
    _ -> {
      [
        [first_line],
        list.index_map(batch_params, fn(b, i) {
          "  "
          <> string.drop_start(b, case i > 0 {
            True -> 2
            False -> 0
          })
          <> ","
        }),
        ["]"],
      ]
      |> list.flatten
    }
  }

  let spaces = spaces(margin)

  case desugarer.stringified_outside {
    None -> so_far
    Some(x) -> {
      let assert [last, ..rest] = list.reverse(so_far)
      [last <> " " <> x, ..rest] |> list.reverse
    }
  }
  |> list.map(fn(l) { spaces <> l })
}

pub fn strip_quotes(string: String) -> String {
  case
    {
      string.starts_with(string, "")
      && string.ends_with(string, "")
      && string != ""
    }
  {
    True -> string |> string.drop_start(1) |> string.drop_end(1)
    False -> string
  }
}

fn ddd_truncate(str: String, max_cols) -> String {
  case string.length(str) > max_cols {
    False -> str
    True -> {
      let excess = string.length(str) - max_cols
      string.drop_end(str, excess + 3) <> "..."
    }
  }
}

type PipelineEntryKind {
  OrdinaryPipelineEntry
  PipelineMarker
  PipelineSectionHeader(String)
}

fn pipeline_entry_kind(desugarer: Desugarer) -> PipelineEntryKind {
  case desugarer.name {
    "table_marker" -> PipelineMarker
    "table_section_header" -> {
      let assert Some(header) = desugarer.stringified_param
      PipelineSectionHeader(header)
    }
    _ -> OrdinaryPipelineEntry
  }
}

fn desugarer_to_list_lines(
  desugarer: Desugarer,
  index: Int,
  max_param_cols: Int,
  max_outside_cols: Int,
  none_string: String,
) -> List(EitherOr(#(String, String, String, String), String)) {
  case pipeline_entry_kind(desugarer) {
    PipelineMarker -> [" ", "% table_marker %", " "] |> list.map(Or)
    PipelineSectionHeader(header) -> {
      ["/", "/ " <> header <> " /", "/"] |> list.map(Or)
    }
    OrdinaryPipelineEntry -> {
      let number = ins(index + 1) <> "."
      let name = desugarer.name
      let param_lines = case desugarer.stringified_param {
        None -> [none_string]
        Some(thing) ->
          case string.split(thing, "\n") {
            [] -> panic as "stringified param is empty string?"
            lines -> lines |> list.map(ddd_truncate(_, max_param_cols))
          }
      }
      let outside = case desugarer.stringified_outside {
        None -> none_string
        Some(thing) -> thing |> ddd_truncate(max_outside_cols)
      }
      list.index_map(param_lines, fn(p, i) {
        case i == 0 {
          True -> Either(#(number, name, p, outside))
          False -> Either(#("", spaces(string.length(name)), p, "⋮"))
        }
      })
    }
  }
}

@internal
pub fn pipeline_timing_table(
  desugarers: List(Desugarer),
  bars: List(String),
  scale: String,
) -> List(String) {
  assert list.length(desugarers) == list.length(bars)
  let rows =
    list.index_map(list.zip(desugarers, bars), fn(pair, index) {
      let #(desugarer, bar) = pair
      case pipeline_entry_kind(desugarer) {
        PipelineMarker -> [" ", "% table_marker %", " "] |> list.map(Or)
        PipelineSectionHeader(header) ->
          ["/", "/ " <> header <> " /", "/"] |> list.map(Or)
        OrdinaryPipelineEntry -> [
          Either(#(ins(index + 1) <> ".", desugarer.name, bar)),
        ]
      }
    })
    |> list.flatten
  three_column_table([Either(#("#.", "name", scale)), ..rows])
}

pub fn print_pipeline(desugarers: List(Desugarer)) {
  let none_string = "--"
  let max_param_cols = 65
  let max_outside_cols = 45
  let lines =
    desugarers
    |> list.index_map(fn(d, i) {
      desugarer_to_list_lines(
        d,
        i,
        max_param_cols,
        max_outside_cols,
        none_string,
      )
    })
    |> list.flatten

  io.println("• pipeline:")

  [Either(#("#.", "name", "param", "outside")), ..lines]
  |> four_column_table
  |> print_lines_at_indent(2)
}

pub fn our_blame_digest(blame: Blame) -> String {
  case bl.blame_digest(blame) {
    "" -> "--"
    s -> s
  }
}
