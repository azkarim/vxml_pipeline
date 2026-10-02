import desugarers/rename_tags_matching
import desugarers/require_document_metadata
import vxml_pipeline/testing

pub const rename_tags_matching = rename_tags_matching.constructor

pub const require_document_metadata = require_document_metadata.constructor

pub const assertive_tests: List(fn() -> testing.AssertiveTestCollection) = [
  rename_tags_matching.assertive_tests,
  require_document_metadata.assertive_tests,
]
