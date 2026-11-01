import argv
import gleam/dict
import gleam/io
import gleam/string
import local_desugarers
import on
import renderers
import vxml_pipeline as vp
import vxml_pipeline_cli as cli

fn local_usage() -> String {
  "   --fmt\n"
  <> "     -> format Writerly into ./formatted\n"
  <> "   --latex\n"
  <> "     -> render LaTeX into ./latex\n"
}

fn cli_error(error: vp.CLIError) {
  io.println("command line error: " <> vp.cli_error_message(error))
  io.println("")
}

pub fn main() {
  io.println("")

  use args <- on.error_ok(
    cli.read_from_dot_last_command(argv.load().arguments),
    cli_error,
  )
  use arguments <- on.error_ok(
    vp.process_command_line_arguments(args, ["--fmt", "--latex"]),
    cli_error,
  )
  use help_requested <- on.error_ok(
    vp.handle_help_requests(arguments, local_usage),
    cli_error,
  )
  use maintenance_requested <- on.error_ok(
    cli.handle_maintenance_requests(arguments, local_desugarers.assertive_tests),
    cli_error,
  )
  use _ <- on.stay(case help_requested || maintenance_requested {
    True -> on.Return(Nil)
    False -> on.Stay(Nil)
  })
  use _ <- on.error_ok(cli.write_to_dot_last_command(args), cli_error)

  let result = case
    dict.has_key(arguments.user_args, "--fmt"),
    dict.has_key(arguments.user_args, "--latex")
  {
    True, _ -> renderers.format(arguments)
    _, True -> renderers.latex_document(arguments)
    False, False -> renderers.html(arguments)
  }

  case result {
    Ok(_) -> Nil
    Error(error) -> io.println("renderer error: " <> string.inspect(error))
  }
}
