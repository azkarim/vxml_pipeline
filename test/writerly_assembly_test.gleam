import gleam/list
import simplifile
import vxml_pipeline as ds
import vxml_pipeline/writerly_defaults

const fixture = "build/writerly-selection-test"

fn selected(filters: List(String)) -> List(String) {
  let options = ds.vanilla_options()
  let options = ds.RendererOptions(..options, only_paths: filters)
  let assert Ok(#(lines, _)) =
    writerly_defaults.default_writerly_assembler(fixture, options)
  list.map(lines, fn(line) { line.suffix })
}

pub fn main() {
  let assert Ok(_) = simplifile.create_directory_all(fixture)
  let assert Ok(_) = simplifile.write(fixture <> "/__parent.wly", "|> Book")
  let assert Ok(_) = simplifile.write(fixture <> "/chapter-1.wly", "one")
  let assert Ok(_) = simplifile.write(fixture <> "/chapter-10.wly", "ten")
  let assert Ok(_) =
    simplifile.write(fixture <> "/chapter-1-draft.wly", "draft")
  let assert Ok(_) = simplifile.write(fixture <> "/chapter-2.wly", "two")

  // Selection uses substrings; required parent files survive filtering.
  assert selected([]) == ["|> Book", "draft", "one", "ten", "two"]
  assert selected(["chapter-1"]) == ["|> Book", "draft", "one", "ten"]
  assert selected(["!draft"]) == ["|> Book", "one", "ten", "two"]
  assert selected(["chapter-1", "!draft"]) == ["|> Book", "one", "ten"]
  assert selected(["chapter-1.wly", "chapter-2"]) == ["|> Book", "one", "two"]
}
