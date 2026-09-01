import vxml_pipeline

pub fn main() {
  let assert Ok(arguments) =
    vxml_pipeline.process_command_line_arguments(
      ["--which", "course", "--verbose"],
      ["--which"],
    )
  assert vxml_pipeline.handle_help_requests(arguments, fn() {
      panic as "local usage must not be evaluated without --help"
    })
    == Ok(False)

  let assert Ok(arguments) =
    vxml_pipeline.process_command_line_arguments(
      [
        "--which", "course", "--track-help", "--help", "--verbose", "--esoteric",
        "--help",
      ],
      ["--which"],
    )
  assert vxml_pipeline.handle_help_requests(arguments, fn() { "local usage" })
    == Ok(True)

  let assert Ok(arguments) =
    vxml_pipeline.process_command_line_arguments(
      ["--which", "course", "-h", "-help"],
      ["--which"],
    )
  assert vxml_pipeline.handle_help_requests(arguments, fn() { "local usage" })
    == Ok(True)
}
