//// Reusable selectors for pipeline tracking output.

import vxml_pipeline/selectors/all
import vxml_pipeline/selectors/verbatim

/// Selects every serialized VXML line.
pub const all = all.selector

/// Selects lines without adding contextual selection markers.
pub const verbatim = verbatim.selector
