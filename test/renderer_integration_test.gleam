import desugaring as ds
import desugaring/core
import desugaring/desugarers as dl
import gleam/list
import gleam/string
import simplifile

const output_path = "build/renderer-integration-output/Book.tsx"

fn test_pipeline() -> core.Pipeline {
  [
    dl.identity(),
    dl.rename(#("Chapter", "section")),
    dl.append_attribute(#("section", "class", "smoke-section", core.GoBack)),
  ]
}

pub fn main() {
  let options = ds.vanilla_options()

  let parameters =
    ds.RendererParameters(
      input_dir: "samples/smoke.xml",
      output_dir: "build/renderer-integration-output",
      prettifier_behavior: ds.PrettifierOff,
    )

  let renderer =
    ds.Renderer(
      assembler: ds.default_file_assembler,
      filterer: ds.default_filterer(_, options, []),
      parser: ds.default_xml_parser,
      pipeline: test_pipeline(),
      splitter: ds.stub_splitter(".tsx"),
      emitter: ds.stub_jsx_emitter,
      writer: ds.default_writer,
      prettifier: ds.default_prettier_prettifier,
    )

  let assert Ok(written_paths) = ds.run_renderer(renderer, parameters, options)
  assert list.contains(written_paths, "Book.tsx")

  let assert Ok(output) = simplifile.read(output_path)
  assert string.contains(output, "<section class=\"smoke-section\">")
  assert string.contains(output, "Renderer smoke test")
}
