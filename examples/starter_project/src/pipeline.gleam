import gleam/list
import local_desugarers as local
import vxml_pipeline/core.{type Pipeline}
import vxml_pipeline/desugarers as ds

const metadata_keys = [
  "title",
  "subtitle",
  "author",
  "date",
  "course",
  "institution",
  "language",
  "description",
  "version",
]

fn publishing_pipeline() -> Pipeline {
  [
    local.require_document_metadata(metadata_keys),
    ds.append_attribute__batch([
      #("Document", "counter", "SectionCounter"),
      #("Document", "counter", "AppendixCounter"),
    ]),
    ds.sigil_counters_prepend_incrementing_attribute__batch([
      #("Section", "SectionCounter"),
      #("Appendix", "AppendixCounter"),
    ]),
    ds.prepend_text_node__batch([
      #("SectionTitle", "::øøSectionCounter. "),
      #("AppendixTitle", "Appendix ::øøAppendixCounter. "),
    ]),
    ds.sigil_counters_substitute__outside(["WriterlyCodeBlock"]),
    ds.delete_attribute("_"),
    ds.writerly_handles_generate_v_definitions_from_t_definitions(),
    ds.writerly_handles_add_ids(),
  ]
}

pub fn html_pipeline() -> Pipeline {
  list.append(publishing_pipeline(), [
    ds.writerly_handles_grand_wrapper_generate_dictionary("path"),
    ds.writerly_handles_grand_wrapper_substitute(
      #("path", "a", "a", [], [], ["a"], ["MathBlock"]),
    ),
    ds.writerly_handles_grand_wrapper_warn_unused(["MathBlock"]),
    ds.writerly_handles_grand_wrapper_unwrap(),
    local.rename_tags_matching(#("^Callout.*$", "aside")),
    ds.rename__batch([
      #("Document", "main"),
      #("Section", "section"),
      #("SectionTitle", "h2"),
      #("Appendix", "section"),
      #("AppendixTitle", "h2"),
      #("MathBlock", "div"),
      #("WriterlyCodeBlock", "pre"),
      #("Definition", "article"),
    ]),
    ds.append_attribute__batch([
      #("section", "class", "document-section"),
      #("aside", "class", "callout"),
      #("div", "class", "math-block"),
      #("pre", "class", "code-block"),
      #("article", "class", "definition"),
    ]),
    ds.delete_attribute("WriterlyCodeBlockInfoStringPrefix"),
    ds.delete__batch(["WriterlyBlankLine", "WriterlyComment"]),
  ])
}

pub fn latex_pipeline() -> Pipeline {
  list.append(publishing_pipeline(), [
    ds.delete__batch(["WriterlyBlankLine", "WriterlyComment"]),
  ])
}

pub fn formatter_pipeline() -> Pipeline {
  []
}
