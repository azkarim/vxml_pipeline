# Writerly starter project

This is a small, complete Writerly application adapted from the architecture
of `dr`. It renders the same source document as HTML, LaTeX, or formatted
Writerly and demonstrates metadata, counters, handles, local desugarers, and
the standard command-line maintenance workflow.

Run commands from this directory:

```sh
gleam run                 # HTML: public/main.html
gleam run -- --latex      # LaTeX: latex/Document.tex
gleam run -- --fmt        # Writerly: formatted/Document.wly
gleam run -- --desugarers # regenerate, renumber, and test local desugarers
```

Compile the LaTeX result with:

```sh
pdflatex -output-directory=latex latex/Document.tex
pdflatex -output-directory=latex latex/Document.tex
```

The second pass resolves the table of contents and cross-references.

## Project organization

- `document/` contains the Writerly source.
- `src/main.gleam` owns command-line control flow.
- `src/renderers.gleam` defines HTML, LaTeX, and Writerly renderers.
- `src/pipeline.gleam` composes reusable and local desugarers.
- `src/desugarers/` contains application-local desugarers.
- `src/local_desugarers.gleam` is generated from that directory.
- `src/local_desugarer_tests.gleam` runs only the local tests.
- `public/app.css` supplies the HTML presentation.

The path dependencies in `gleam.toml` let this example test the checkout that
contains it, with `vxml`, `writerly`, and `vxml_pipeline_cli` checked out as
siblings of `vxml_pipeline`. After copying the starter into a separate project,
replace them with appropriate released versions.
