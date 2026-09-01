import filepath
import gleam/int
import gleam/io
import gleam/list
import gleam/regexp.{type Regexp}
import gleam/result
import gleam/string
import simplifile

const desugarer_dir = "src/desugarers"

type Patterns {
  Patterns(desugarer_blame: Regexp, authoring_blame: Regexp, des_blame: Regexp)
}

pub fn main() -> Nil {
  io.println("")
  case run() {
    Ok(Nil) -> Nil
    Error(message) -> panic as message
  }
}

pub fn run() -> Result(Nil, String) {
  case perform() {
    Ok(Nil) -> {
      io.println("")
      Ok(Nil)
    }
    Error(message) -> Error(message)
  }
}

/// Renumber local desugarer blames without closing its output block.
pub fn perform() -> Result(Nil, String) {
  case renumber_all() {
    Ok(#(changed, changed_files)) -> {
      list.each(changed_files, fn(file) { io.println("Processed: " <> file) })
      io.println(
        "Renumbered local desugarer blames. Files changed: "
        <> int.to_string(changed),
      )
      Ok(Nil)
    }
    Error(message) -> Error(message)
  }
}

fn renumber_all() -> Result(#(Int, List(String)), String) {
  use entries <- result.try(
    simplifile.read_directory(desugarer_dir)
    |> result.map_error(fn(_) { "Could not read " <> desugarer_dir <> "." }),
  )

  let files =
    entries
    |> list.filter(fn(entry) { string.ends_with(entry, ".gleam") })
    |> list.sort(string.compare)

  let patterns = patterns()

  list.try_fold(files, #(0, []), fn(state, file) {
    let path = filepath.join(desugarer_dir, file)
    use changed <- result.try(renumber_file(path, patterns))

    case changed {
      True -> {
        Ok(#(state.0 + 1, [file, ..state.1]))
      }
      False -> Ok(state)
    }
  })
  |> result.map(fn(state) { #(state.0, list.reverse(state.1)) })
}

fn patterns() -> Patterns {
  let assert Ok(desugarer_blame) =
    regexp.from_string("desugarer_blame\\(\\d+\\)")
  let assert Ok(authoring_blame) =
    regexp.from_string("authoring\\.blame\\(name,\\s*\\d+\\)")
  let assert Ok(des_blame) =
    regexp.from_string("\\b(?:bl\\.)?Des\\(\\[\\],\\s*name,\\s*\\d+\\s*\\)")

  Patterns(desugarer_blame, authoring_blame, des_blame)
}

fn renumber_file(path: String, patterns: Patterns) -> Result(Bool, String) {
  use original <- result.try(
    simplifile.read(path)
    |> result.map_error(fn(_) { "Could not read " <> path <> "." }),
  )

  let updated =
    original
    |> string.split("\n")
    |> list.index_map(fn(line, index) {
      renumber_line(line, index + 1, patterns)
    })
    |> string.join("\n")

  case updated == original {
    True -> Ok(False)
    False -> {
      use _ <- result.try(
        simplifile.write(path, updated)
        |> result.map_error(fn(_) { "Could not write " <> path <> "." }),
      )
      Ok(True)
    }
  }
}

fn renumber_line(line: String, line_no: Int, patterns: Patterns) -> String {
  let line_no = int.to_string(line_no)

  line
  |> regexp.replace(
    patterns.desugarer_blame,
    _,
    "desugarer_blame(" <> line_no <> ")",
  )
  |> regexp.replace(
    patterns.authoring_blame,
    _,
    "authoring.blame(name, " <> line_no <> ")",
  )
  |> regexp.match_map(patterns.des_blame, _, fn(matched) {
    let prefix = case string.starts_with(matched.content, "bl.") {
      True -> "bl."
      False -> ""
    }
    prefix <> "Des([], name, " <> line_no <> ")"
  })
}
