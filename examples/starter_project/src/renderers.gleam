import gleam/list
import gleam/option.{Some}
import gleam/regexp
import gleam/result
import gleam/string
import pipeline
import vxml.{type Attr, type VXML, Attr, T, V}
import vxml/blame.{Ext}
import vxml/io_lines.{OutputLine}
import vxml_pipeline as vp
import vxml_pipeline/writerly_defaults

fn options(arguments: vp.ParsedCLIArguments) {
  vp.RendererOptions(..vp.vanilla_options(), artifacts: True, warnings: True)
  |> vp.amend_renderer_options_by_arguments(arguments)
}

fn parameters(output_dir: String, arguments: vp.ParsedCLIArguments) {
  vp.RendererParameters(
    input_dir: "document",
    output_dir: output_dir,
    prettifier_behavior: vp.PrettifierOff,
  )
  |> vp.amend_renderer_parameters_by_arguments(arguments)
}

fn metadata(attrs: List(Attr), key: String) -> String {
  attrs
  |> list.find_map(fn(attr) {
    case attr {
      Attr(_, found, value) if found == key -> Ok(value)
      _ -> Error(Nil)
    }
  })
  |> result.unwrap("")
}

fn html_emitter(fragment: vp.OutputFragment(Nil, VXML)) {
  let assert V(_, _, attrs, children) = fragment.payload
  let blame = Ext([], "starter_html_emitter")
  let title = metadata(attrs, "title")
  let lines =
    list.flatten([
      [
        OutputLine(blame, 0, "<!doctype html>"),
        OutputLine(
          blame,
          0,
          "<html lang=\"" <> metadata(attrs, "language") <> "\">",
        ),
        OutputLine(blame, 0, "<head>"),
        OutputLine(blame, 2, "<meta charset=\"utf-8\">"),
        OutputLine(
          blame,
          2,
          "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
        ),
        OutputLine(
          blame,
          2,
          "<meta name=\"author\" content=\""
            <> metadata(attrs, "author")
            <> "\">",
        ),
        OutputLine(
          blame,
          2,
          "<meta name=\"description\" content=\""
            <> metadata(attrs, "description")
            <> "\">",
        ),
        OutputLine(blame, 2, "<title>" <> title <> "</title>"),
        OutputLine(blame, 2, "<link rel=\"stylesheet\" href=\"app.css\">"),
        OutputLine(
          blame,
          2,
          "<script>MathJax = { tex: { tags: 'ams' } };</script>",
        ),
        OutputLine(
          blame,
          2,
          "<script defer src=\"https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-svg.js\"></script>",
        ),
        OutputLine(blame, 0, "</head>"),
        OutputLine(blame, 0, "<body>"),
        OutputLine(blame, 2, "<header class=\"document-header\">"),
        OutputLine(
          blame,
          4,
          "<p class=\"eyebrow\">"
            <> metadata(attrs, "course")
            <> " · "
            <> metadata(attrs, "institution")
            <> "</p>",
        ),
        OutputLine(blame, 4, "<h1>" <> title <> "</h1>"),
        OutputLine(
          blame,
          4,
          "<p class=\"subtitle\">" <> metadata(attrs, "subtitle") <> "</p>",
        ),
        OutputLine(
          blame,
          4,
          "<p class=\"byline\">"
            <> metadata(attrs, "author")
            <> " · "
            <> metadata(attrs, "date")
            <> "</p>",
        ),
        OutputLine(blame, 2, "</header>"),
      ],
      vxml.vxmls_to_html_output_lines(children, 2, 2),
      [OutputLine(blame, 0, "</body>"), OutputLine(blame, 0, "</html>")],
    ])
  Ok(#(vp.OutputFragment(..fragment, payload: lines), vp.NoFeedback))
}

fn escape_latex(text: String) -> String {
  text
  |> string.replace("&", "\\&")
  |> string.replace("%", "\\%")
  |> string.replace("#", "\\#")
}

fn references_to_latex(text: String) -> String {
  let assert Ok(pattern) =
    regexp.from_string(">>([A-Za-z0-9_.:'^-]*[A-Za-z0-9_'^])")
  case regexp.scan(pattern, text) {
    [] -> text
    [found, ..] -> {
      let assert Ok(#(before, after)) = string.split_once(text, found.content)
      let replacement = case found.submatches {
        [Some(name)] -> "\\ref{" <> name <> "}"
        _ -> found.content
      }
      before <> replacement <> references_to_latex(after)
    }
  }
}

fn labels(attrs: List(Attr)) -> String {
  attrs
  |> list.filter_map(fn(attr) {
    case attr {
      Attr(_, "handle", value) -> {
        let name =
          value |> string.split(" ") |> list.first |> result.unwrap(value)
        Ok("\\label{" <> name <> "}")
      }
      _ -> Error(Nil)
    }
  })
  |> string.concat
}

fn unnumber_title(title: String) -> String {
  let assert Ok(numbered) = regexp.from_string("^[0-9]+\\. ")
  let assert Ok(appendix) = regexp.from_string("^Appendix [0-9]+\\. ")
  title
  |> fn(title) { regexp.replace(appendix, title, "") }
  |> fn(title) { regexp.replace(numbered, title, "") }
}

fn latex(vxml: VXML) -> String {
  case vxml {
    T(_, lines) ->
      lines
      |> list.map(fn(line) { line.content })
      |> string.join("\n")
      |> escape_latex
      |> references_to_latex
    V(_, tag, attrs, children) -> {
      let body = children |> list.map(latex) |> string.concat
      let label = labels(attrs)
      case tag {
        "Document" -> body
        "Section" -> body
        "SectionTitle" ->
          "\\section{" <> unnumber_title(body) <> "}" <> label <> "\n"
        "Appendix" -> "\\appendix\n" <> body
        "AppendixTitle" ->
          "\\section{" <> unnumber_title(body) <> "}" <> label <> "\n"
        "p" -> body <> "\n\n"
        "Definition" ->
          "\\begin{definition}"
          <> label
          <> "\n"
          <> body
          <> "\\end{definition}\n"
        "MathBlock" ->
          "\\begin{equation}\n" <> body <> label <> "\n\\end{equation}\n"
        "WriterlyCodeBlock" ->
          "\\begin{verbatim}\n" <> body <> "\n\\end{verbatim}\n"
        "CalloutNote" -> "\\begin{quote}\n" <> body <> "\\end{quote}\n"
        _ -> body
      }
    }
  }
}

fn latex_emitter(fragment: vp.OutputFragment(Nil, VXML)) {
  let assert V(_, _, attrs, _) = fragment.payload
  let blame = Ext([], "starter_latex_emitter")
  let source =
    string.join(
      [
        "\\documentclass[11pt]{article}",
        "\\usepackage[margin=1.15in]{geometry}",
        "\\usepackage{microtype}",
        "\\usepackage{xcolor}",
        "\\usepackage[colorlinks=true,linkcolor=blue!55!black]{hyperref}",
        "\\usepackage{amsthm}",
        "\\newtheorem{definition}{Definition}[section]",
        "\\title{" <> escape_latex(metadata(attrs, "title")) <> "}",
        "\\author{" <> escape_latex(metadata(attrs, "author")) <> "}",
        "\\date{" <> escape_latex(metadata(attrs, "date")) <> "}",
        "\\begin{document}",
        "\\maketitle",
        "\\begin{center}\\large "
          <> escape_latex(metadata(attrs, "subtitle"))
          <> "\\end{center}",
        "\\tableofcontents",
        latex(fragment.payload),
        "\\end{document}",
      ],
      "\n",
    )
  let lines =
    source
    |> string.split("\n")
    |> list.map(fn(line) { OutputLine(blame, 0, line) })
  Ok(#(vp.OutputFragment(..fragment, payload: lines), vp.NoFeedback))
}

fn renderer(arguments, pipeline, suffix, emitter) {
  let options = options(arguments)
  vp.Renderer(
    assembler: writerly_defaults.default_writerly_assembler(_, options),
    parser: writerly_defaults.default_writerly_parser,
    filterer: vp.default_filterer(_, options, []),
    pipeline: pipeline,
    splitter: vp.stub_splitter(suffix),
    emitter: emitter,
    writer: vp.default_writer,
    prettifier: vp.empty_prettifier,
  )
}

pub fn html(arguments: vp.ParsedCLIArguments) {
  let renderer =
    renderer(arguments, pipeline.html_pipeline(), ".html", html_emitter)
  vp.run_renderer(renderer, parameters("public", arguments), options(arguments))
}

pub fn latex_document(arguments: vp.ParsedCLIArguments) {
  let renderer =
    renderer(arguments, pipeline.latex_pipeline(), ".tex", latex_emitter)
  vp.run_renderer(renderer, parameters("latex", arguments), options(arguments))
}

pub fn format(arguments: vp.ParsedCLIArguments) {
  let options = options(arguments)
  let renderer =
    vp.Renderer(
      assembler: writerly_defaults.default_writerly_assembler(_, options),
      parser: writerly_defaults.default_writerly_parser,
      filterer: vp.default_filterer(_, options, []),
      pipeline: pipeline.formatter_pipeline(),
      splitter: vp.stub_splitter(".wly"),
      emitter: writerly_defaults.default_writerly_emitter,
      writer: vp.default_writer,
      prettifier: vp.empty_prettifier,
    )
  vp.run_renderer(renderer, parameters("formatted", arguments), options)
}
