import desugaring
import gleam/option

fn assert_parses(arguments: List(String)) -> Nil {
  let assert Ok(_) = desugaring.process_command_line_arguments(arguments, [])
  Nil
}

fn assert_does_not_parse(arguments: List(String)) -> Nil {
  let assert Error(_) = desugaring.process_command_line_arguments(arguments, [])
  Nil
}

pub fn main() {
  assert_parses(["--track", "needle", "+-5", "-+2", "10-20"])
  assert_parses(["--track", "needle", "-1"])
  assert_parses(["--track", "needle", "+5-0"])
  assert_parses([
    "--track",
    "needle",
    "-with-ancestors",
    "-track+-1",
    "-print+-5",
  ])
  assert_parses(["--track", "needle", "-track+0", "+5-5"])
  assert_parses(["--track", "needle", "+0-0", "-print+5-5"])
  assert_parses(["--track", "needle", "-print+5-5"])
  assert_parses(["--track", "needle", "+5-5", "rename-5"])
  assert_parses(["--track", "needle", "+5-5", "rename+5"])
  assert_parses(["--track", "needle", "+5-5", "rename+5+10"])
  assert_parses(["--track", "needle", "+5-5", "rename-10-5"])
  assert_parses(["--track", "needle", "+5-5", "!rename-2+2"])
  assert_parses(["--track", "needle", "-verbatim", "+-5"])
  assert_parses(["--track", "needle", "-bc0", "-cc0", "+-5"])
  assert_parses(["--track", "needle", "+-5", "-bc10", "-cc20"])
  assert_parses(["--track", "needle", "-no-ellipses", "+-5"])
  assert_parses(["--dump", "120-"])
  assert_parses(["--dump", "-5--1"])
  assert_parses(["--dump", "!120-130"])
  assert_parses(["--dump", "-verbatim", "120-"])
  assert_parses(["--dump", "-i", "120-"])
  assert_parses(["--dump", "120-", "-i"])
  let assert Ok(interactive_dump) =
    desugaring.process_command_line_arguments(["--dump", "-i", "120-"], [])
  assert interactive_dump.monitor_interactive_mode
  assert_parses(["--dump", "-bc0", "-cc0", "!120-130"])
  assert_parses(["--dump", "10", "--dump", "20"])
  assert_parses(["--dump", "-cc10", "10", "--dump", "-bc20", "20"])
  assert_parses(["--dump", "-verbatim", "10", "--dump", "-verbatim", "20"])
  assert_parses(["--validate-vxml"])
  assert_parses(["--validate-vxml", "-warn-attribute-whitespace"])
  assert_parses(["--validate-vxml", "-lines-only"])
  assert_does_not_parse(["--validate-vxml", "-unknown"])
  assert_does_not_parse(["--validate-vxml", "--validate-vxml"])
  let assert Error(desugaring.CommandLineArgumentError(desugaring.ConflictingOptionArguments(
    "--validate-vxml",
  ))) =
    desugaring.process_command_line_arguments(
      ["--validate-vxml", "-lines-only", "-warn-attribute-whitespace"],
      [],
    )
  let assert Error(desugaring.CommandLineArgumentError(desugaring.ConflictingOptionArguments(
    "--dump",
  ))) =
    desugaring.process_command_line_arguments(
      ["--dump", "-cc10", "10", "--dump", "-cc20", "20"],
      [],
    )
  let assert Error(desugaring.CommandLineArgumentError(desugaring.ConflictingOptionArguments(
    "--dump",
  ))) =
    desugaring.process_command_line_arguments(
      ["--dump", "-verbatim", "10", "--dump", "20"],
      [],
    )
  let assert Error(desugaring.CommandLineArgumentError(desugaring.DuplicateOption(
    "--input-dir",
  ))) =
    desugaring.process_command_line_arguments(
      ["--input-dir", "one", "--input-dir", "two"],
      [],
    )
  let assert Error(desugaring.CommandLineArgumentError(desugaring.DuplicateOption(
    "--output-dir",
  ))) =
    desugaring.process_command_line_arguments(
      ["--output-dir", "one", "--output-dir", "two"],
      [],
    )
  let assert Error(desugaring.CommandLineArgumentError(desugaring.DuplicateOption(
    "--times",
  ))) =
    desugaring.process_command_line_arguments(
      ["--times", "80", "--times", "100"],
      [],
    )
  assert_parses(["--dump-assembled"])
  assert_parses(["--dump-parsed"])
  assert_parses(["--dump-filtered"])
  assert_parses(["--dump-splitter"])
  assert_parses(["--dump-splitter", "chapter", "appendix"])
  assert_parses(["--dump-emitter"])
  assert_parses(["--dump-emitter", "lecture-notes/05"])
  assert_parses([
    "--dump-splitter",
    "chapter",
    "--dump-splitter",
    "appendix",
    "--dump-emitter",
  ])
  assert_does_not_parse(["--dump-assembled", "unexpected"])
  assert_does_not_parse(["--dump-parsed", "unexpected"])
  assert_does_not_parse(["--dump-filtered", "unexpected"])
  assert_does_not_parse(["--echo-assembled"])
  assert_does_not_parse(["--echo-vxml-fragments"])
  assert_parses(["--only", "chapter&language=en"])
  assert_does_not_parse(["--only", "chapter&language"])
  assert_does_not_parse(["--only", "chapter&language=en=extra"])
  assert_parses(["--help"])
  assert_parses(["-h"])
  assert_parses(["-help"])
  assert_parses(["--esoteric"])
  assert_parses(["--track-help"])
  assert_parses(["--renumber"])
  assert_parses(["--generate"])
  assert_parses(["--regenerate"])
  assert_parses(["--desugarers"])
  assert_parses(["--desugarer-tests"])
  assert_parses(["--desugarer-tests", "one", "two"])
  assert_parses(["--test-desugarers", "one"])
  assert_does_not_parse(["--last-command"])
  assert_does_not_parse(["--last-command", "--help"])
  assert_does_not_parse(["--last-command", "unexpected"])
  let assert Ok(requests) =
    desugaring.process_command_line_arguments(
      [
        "-h", "--esoteric", "--track-help", "--renumber", "--regenerate",
        "--desugarers", "--test-desugarers", "one", "two",
      ],
      [],
    )
  assert requests.help
  assert requests.esoteric
  assert requests.track_help
  assert requests.renumber
  assert requests.generate
  assert requests.desugarers
  assert requests.desugarer_tests == option.Some(["one", "two"])
  assert_does_not_parse([
    "--track",
    "needle",
    "+5-5",
    "+2-2",
    "+20-30",
  ])
  assert_does_not_parse(["--track", "needle", "+5"])
  assert_does_not_parse([
    "--track",
    "needle",
    "+0-0",
    "+1-1",
    "+2-2",
  ])
  assert_does_not_parse([
    "--track",
    "needle",
    "-track+0",
    "-track+1-1",
  ])
  assert_parses(["--track", "needle", "-verbatim", "-cc10", "-bc10"])
  assert_does_not_parse(["--track", "needle", "-bc-1"])
  assert_does_not_parse(["--track", "needle", "-cc"])
  assert_does_not_parse(["--track", "needle", "-bc10", "-bc20"])
  assert_does_not_parse([
    "--track",
    "needle",
    "-no-ellipses",
    "-no-ellipses",
  ])
  assert_does_not_parse(["--dump", "-no-ellipses"])
  assert_does_not_parse(["--dump", "-bc-1"])
  assert_does_not_parse(["--dump", "-cc"])
  assert_does_not_parse(["--dump", "-cc10", "-cc20"])
}
