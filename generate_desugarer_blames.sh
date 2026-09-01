#!/usr/bin/env bash
set -euo pipefail

# Renumber desugarer-created blame references in src/desugaring/desugarers/*.gleam.
#
# Rewrites:
#   desugarer_blame(123)      -> desugarer_blame(current_line)
#   authoring.blame(name, 123) -> authoring.blame(name, current_line)
#   bl.Des([], name, 123)     -> bl.Des([], name, current_line)
#   Des([], name, 123)        -> Des([], name, current_line)
#
# The raw Des rewrite is intentionally narrow: it only touches numeric literals
# in the standard desugarer-name shape, so helper bodies using `line_no` are left
# unchanged.

target_dir="${1:-src/desugaring/desugarers}"

if [ ! -d "$target_dir" ]; then
  echo "Error: directory '$target_dir' does not exist." >&2
  exit 1
fi

echo "Renumbering desugarer blame references in $target_dir"

changed=0

for file in "$target_dir"/*.gleam; do
  [ -e "$file" ] || continue

  before_hash="$(cksum "$file")"

  perl -0pi -e '
    my $line_no = 1;

    s{^([^\n]*)(\n?)}{
      my ($line, $newline) = ($1, $2);

      $line =~ s/desugarer_blame\(\d+\)/"desugarer_blame($line_no)"/ge;
      $line =~ s/authoring\.blame\(name,\s*\d+\)/"authoring.blame(name, $line_no)"/ge;
      $line =~ s/\b((?:bl\.)?Des\(\[\],\s*name,\s*)\d+(\s*\))/$1 . $line_no . $2/ge;

      $line_no++;
      $line . $newline;
    }gme;
  ' "$file"

  after_hash="$(cksum "$file")"
  if [ "$before_hash" != "$after_hash" ]; then
    changed=$((changed + 1))
    echo "Processed: $(basename "$file")"
  fi
done

echo "Done. Files changed: $changed"
