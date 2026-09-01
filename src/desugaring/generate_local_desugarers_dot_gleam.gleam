import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import simplifile

const desugarer_dir = "src/desugarers"

const module_prefix = "desugarers"

const output_path = "src/local_desugarers.gleam"

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

/// Generate the local desugarer registry without closing its output block.
pub fn perform() -> Result(Nil, String) {
  case generate() {
    Ok(#(output_path, count)) -> {
      io.println(
        "Generated "
        <> output_path
        <> " from "
        <> int.to_string(count)
        <> " local desugarer(s).",
      )
      Ok(Nil)
    }
    Error(message) -> Error(message)
  }
}

fn generate() -> Result(#(String, Int), String) {
  use module_names <- result.try(read_module_names(desugarer_dir))
  let contents = generate_contents(module_prefix, module_names)

  use _ <- result.try(
    simplifile.write(output_path, contents)
    |> result.map_error(fn(_) { "Could not write " <> output_path <> "." }),
  )

  Ok(#(output_path, list.length(module_names)))
}

fn read_module_names(desugarer_dir: String) -> Result(List(String), String) {
  use entries <- result.try(
    simplifile.read_directory(desugarer_dir)
    |> result.map_error(fn(_) { "Could not read " <> desugarer_dir <> "." }),
  )

  entries
  |> list.filter(fn(entry) {
    string.ends_with(entry, ".gleam") && !string.starts_with(entry, "__")
  })
  |> list.map(fn(entry) { string.drop_end(entry, 6) })
  |> list.sort(string.compare)
  |> Ok
}

fn generate_contents(
  module_prefix: String,
  module_names: List(String),
) -> String {
  let imports =
    [
      "desugaring/testing",
      ..list.map(module_names, fn(name) { module_prefix <> "/" <> name })
    ]
    |> list.sort(string.compare)
    |> list.map(fn(module) { "import " <> module })
    |> string.join("\n")

  let constructors =
    module_names
    |> list.map(fn(name) {
      "pub const " <> name <> " = " <> name <> ".constructor"
    })
    |> string.join("\n\n")

  let tests =
    module_names
    |> list.map(fn(name) { "  " <> name <> ".assertive_tests," })
    |> string.join("\n")

  imports
  <> "\n\n"
  <> constructors
  <> "\n\n"
  <> "pub const assertive_tests: List(fn() -> testing.AssertiveTestCollection) = [\n"
  <> tests
  <> "\n]\n"
}
