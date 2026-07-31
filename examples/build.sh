#!/bin/sh
# Build examples/demo.html.
#
# The deck is assembled from two Org files: parts/history.org is exported
# body-only, so that it contributes content without repeating the main
# file's frontmatter, and demo.org pulls the result in with
# #+SLIPSHOW_INCLUDE:.  Slipshow does that splicing at compile time, which
# is why the part has to be exported first.

set -eu

root=$(cd "$(dirname "$0")/.." && pwd)

# Output paths must be absolute: `find-file' moves `default-directory' to
# the Org file's own directory, so a relative one would be resolved from
# there rather than from where the build was started.
export_org() {
    # $1 org file, $2 output .slp, $3 t for a body-only export
    emacs --batch -L "$root" \
          --eval "(progn
                    (require 'ox-rlr-slipshow)
                    (find-file \"$root/$1\")
                    (org-export-to-file 'rlr-slipshow
                        \"$root/$2\" nil nil nil ${3:-nil}))"
}

export_org examples/parts/history.org examples/parts/history.slp t
export_org examples/demo.org examples/demo.slp

cd "$root"
slipshow compile examples/demo.slp -o examples/demo.html

echo "Built examples/demo.html"
