import desugaring as ds
import desugaring/core.{Desugarer}
import desugaring/desugarers as dl
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/string
import gleam/time/duration
import vxml
import vxml/blame

fn pipeline_ux_options() -> ds.PipelineUXOptions {
  ds.PipelineUXOptions(False, False, 0)
}

fn stopping_monitor() -> ds.Monitor {
  ds.new_monitor("test-monitor", 0, fn(_vxml, state, context) {
    case state, context {
      0, ds.PipelineStepContext(0, None, Some(next)) -> {
        assert next.name == "identity"
        Ok(#(1, ds.NoFeedback))
      }
      1, ds.PipelineStepContext(1, Some(previous), None) -> {
        assert previous.name == "identity"
        Error("requested stop")
      }
      _, _ -> panic as "unexpected monitor context"
    }
  })
}

pub fn main() {
  let options =
    ds.RendererOptions(..ds.vanilla_options(), monitors: [stopping_monitor()])
  assert list.length(options.monitors) == 1

  let input = vxml.V(blame.no_blame, "root", [], [])
  let result =
    ds.run_pipeline(
      input,
      [dl.identity()],
      [stopping_monitor()],
      pipeline_ux_options(),
    )
  let assert Error(ds.PipelineMonitorError(failure)) = result
  let ds.MonitorFailure(name, step_no, message) = failure
  assert name == "test-monitor"
  assert step_no == 1
  assert message == "requested stop"

  let invalid = vxml.V(blame.no_blame, "bad-tag", [], [])
  let result =
    ds.run_pipeline(
      invalid,
      [],
      [ds.vxml_validation_monitor(False)],
      pipeline_ux_options(),
    )
  let assert Error(ds.PipelineMonitorError(failure)) = result
  let ds.MonitorFailure(name, step_no, message) = failure
  assert name == "validate-vxml"
  assert step_no == 0
  assert string.contains(message, "invalid tag")
  assert string.contains(message, "bad-tag")

  let empty_text = vxml.T(blame.no_blame, [])
  let result =
    ds.run_pipeline(
      empty_text,
      [],
      [ds.empty_text_node_monitor()],
      pipeline_ux_options(),
    )
  let assert Error(ds.PipelineMonitorError(failure)) = result
  let ds.MonitorFailure(name, step_no, message) = failure
  assert name == "validate-vxml-lines"
  assert step_no == 0
  assert message == "empty text node (no blame)"

  let invalid_tag_with_nonempty_lines =
    vxml.V(blame.no_blame, "bad-tag", [], [
      vxml.T(blame.no_blame, [vxml.Line(blame.no_blame, "content")]),
    ])
  let assert Ok(_) =
    ds.run_pipeline(
      invalid_tag_with_nonempty_lines,
      [],
      [ds.empty_text_node_monitor()],
      pipeline_ux_options(),
    )

  let whitespace_is_valid =
    vxml.V(
      blame.no_blame,
      "root",
      [
        vxml.Attr(blame.no_blame, "class", " padded "),
      ],
      [],
    )
  let assert Ok(_) =
    ds.run_pipeline(
      whitespace_is_valid,
      [],
      [ds.vxml_validation_monitor(True)],
      pipeline_ux_options(),
    )

  pipeline_durations_follow_pipeline_order()
}

fn pipeline_durations_follow_pipeline_order() {
  let slow =
    Desugarer("slow", None, None, fn(vxml) {
      process.sleep(30)
      Ok(#(vxml, []))
    })
  let fast = Desugarer("fast", None, None, fn(vxml) { Ok(#(vxml, [])) })
  let input = vxml.V(blame.no_blame, "root", [], [])

  let assert Ok(#(_, _, [slow_duration, fast_duration])) =
    ds.run_pipeline(input, [slow, fast], [], pipeline_ux_options())

  assert duration.compare(slow_duration, fast_duration) == order.Gt
}
