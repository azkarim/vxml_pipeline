import desugaring/tables

pub fn main() {
  assert tables.two_column_table([#("a", "bb"), #("ccc", "d")])
    == [
      "┌──────┬─────┐",
      "│ a    │ bb  │",
      "├──────┼─────┤",
      "│ ccc  │ d   │",
      "└──────┴─────┘",
    ]

  assert tables.table(
      [
        tables.Cells([
          tables.TableCell("left", " "),
          tables.TableCell("right", " "),
        ]),
        tables.SpanningRow(" section ", "-"),
      ],
      [tables.ColumnStyle(1), tables.ColumnStyle(1)],
    )
    == [
      "┌──────┬───────┐",
      "│ left │ right │",
      "├──────┼───────┤",
      "--- section ----",
      "└──────┴───────┘",
    ]

  assert tables.table([], []) == []
}
