# Changelog

## 0.5.0 — Unreleased

- **Breaking:** Remove all file access, process spawning, shell commands, and
  stdin reads so the package compiles for the JavaScript target and runs in
  the browser. `simplifile`, `shellout`, `input`, and `gleam_erlang` are no
  longer dependencies. Requires `vxml` 3.0.0 and `writerly` 0.7.0.
- **Breaking:** Move the host-bound API to the new Erlang-only
  `vxml_pipeline_cli` package, with unchanged signatures:
  `default_file_assembler`, `default_writer`, `default_prettier_prettifier`,
  `read_from_dot_last_command`, `write_to_dot_last_command`,
  `handle_maintenance_requests`, the `generate_local_desugarers_dot_gleam` and
  `renumber_local_desugarer_blames` modules (now under `vxml_pipeline_cli/`),
  and `writerly_defaults.default_writerly_assembler` (now
  `vxml_pipeline_cli/writerly.default_writerly_assembler`, whose error type is
  `WriterlyAssemblerError`).
- **Behavior:** `run_pipeline` and `run_renderer` keep their signatures but run
  the pipeline synchronously in the calling process. They ignore
  `monitor_interactive_mode` and `report_long_running_desugarers`;
  `vxml_pipeline_cli.run_pipeline` and `vxml_pipeline_cli.run_renderer` keep
  the previous interactive behavior and output.
- Add `run_pipeline_fold`, which folds every `PipelineEvent` into caller state
  without I/O, and `run_pipeline_with_events`, its side-effecting variant.
- Add `PipelineResult`, `PipelineRunner`, `run_renderer_with_pipeline_runner`,
  and a public `print_feedback_block`.
- Add `writerly_defaults.assemble_writerly_sources(root, sources, options)`,
  which assembles in-memory `writerly.SourceFile`s.
- Fix JavaScript-target bugs, found by running the test suite on JavaScript for
  the first time:
  - The `\begin{…}` / `\end{…}` math delimiter patterns and the annotated
    backtick pattern used bare `{`/`}`, which JavaScript rejects; the braces are
    now escaped.
  - `writerly_handles_generate_v_definitions_from_t_definitions` and
    `writerly_handles_materialize_mathjax_tags` missed `##name<<…>>##` handles
    without decorators, because `gleam_regexp` on JavaScript drops trailing
    empty capture groups. The new `handle_syntax.padded_submatches` gives both
    targets the same submatch list.
- `test/monitor_test` no longer uses `process.sleep`, so the whole suite runs
  on both targets.

**Migration** for a command-line renderer: add `vxml_pipeline_cli`, then
replace `vp.run_renderer`, `vp.default_writer`, `vp.default_file_assembler`,
`vp.default_prettier_prettifier`, `vp.read_from_dot_last_command`,
`vp.write_to_dot_last_command`, and `vp.handle_maintenance_requests` with the
`vxml_pipeline_cli` functions of the same names, and
`writerly_defaults.default_writerly_assembler` with
`vxml_pipeline_cli/writerly.default_writerly_assembler`.
