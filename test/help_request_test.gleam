import desugaring

pub fn main() {
  let assert Ok(arguments) =
    desugaring.process_command_line_arguments(
      ["--which", "course", "--verbose"],
      ["--which"],
    )
  assert desugaring.handle_help_requests(arguments, fn() {
      panic as "local usage must not be evaluated without --help"
    })
    == Ok(False)

  let assert Ok(arguments) =
    desugaring.process_command_line_arguments(
      [
        "--which", "course", "--track-help", "--help", "--verbose", "--esoteric",
        "--help",
      ],
      ["--which"],
    )
  assert desugaring.handle_help_requests(arguments, fn() { "local usage" })
    == Ok(True)

  let assert Ok(arguments) =
    desugaring.process_command_line_arguments(
      ["--which", "course", "-h", "-help"],
      ["--which"],
    )
  assert desugaring.handle_help_requests(arguments, fn() { "local usage" })
    == Ok(True)
}
