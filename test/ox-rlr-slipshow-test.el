;;; ox-rlr-slipshow-test.el --- Tests for ox-rlr-slipshow -*- lexical-binding: t; -*-

;; Run with:
;;   emacs --batch -L . -l test/ox-rlr-slipshow-test.el \
;;         -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'ox-rlr-slipshow)

(defun ox-rlr-slipshow-test--export (source &optional body-only)
  "Export Org SOURCE with this back-end and return the result.
BODY-ONLY is passed through to `org-export-as'."
  (with-temp-buffer
    (insert source)
    (org-mode)
    (org-export-as 'rlr-slipshow nil nil body-only)))

(defun ox-rlr-slipshow-test--count (needle haystack)
  "Return the number of times literal NEEDLE occurs in HAYSTACK."
  (let ((start 0) (n 0))
    (while (string-match (regexp-quote needle) haystack start)
      (setq n (1+ n)
            start (match-end 0)))
    n))


;;; Export dispatcher contract

(ert-deftest ox-rlr-slipshow-menu-actions-accept-four-arguments ()
  "`org-export-dispatch' funcalls each menu action with four arguments.
A three-argument command signals \"Wrong number of arguments\" only when
invoked through the dispatcher, which is easy to miss when testing
`org-export-to-file' directly."
  (dolist (entry (nth 2 (org-export-backend-menu
                         (org-export-get-backend 'rlr-slipshow))))
    (let* ((fn (nth 2 entry))
           (arity (func-arity fn)))
      (should (<= (car arity) 4))
      (should (or (eq (cdr arity) 'many) (>= (cdr arity) 4))))))

(ert-deftest ox-rlr-slipshow-body-only-drops-frontmatter ()
  (let ((source "#+SLIPSHOW_THEME: vanier\n#+OPTIONS: toc:nil\n\n* One\n\ntext\n"))
    (should (string-prefix-p "---" (ox-rlr-slipshow-test--export source)))
    (should-not (string-prefix-p "---" (ox-rlr-slipshow-test--export source t)))))


;;; The server

(ert-deftest ox-rlr-slipshow-stop-without-a-server-is-harmless ()
  "Stopping when nothing is running should report, not signal."
  (should-not (org-rlr-slipshow--server))
  (org-rlr-slipshow-stop))

(ert-deftest ox-rlr-slipshow-server-and-compile-buffers-differ ()
  "`get-buffer-process' returns one process per buffer, so sharing a
buffer between the server and compile runs left the server unreachable."
  (should-not (equal org-rlr-slipshow--compile-buffer
                     org-rlr-slipshow--serve-buffer)))


;;; Slipshow's divergences from CommonMark

(ert-deftest ox-rlr-slipshow-escapes-literal-braces ()
  "An unescaped brace is read as an attribute set and eats the text inside."
  (let ((out (ox-rlr-slipshow-test--export "Braces {this one} here.\n")))
    (should (string-match-p (regexp-quote "\\{this one\\}") out))))

(ert-deftest ox-rlr-slipshow-quote-block-is-marked ()
  "A bare `>' group is not a quote in Slipshow."
  (let ((out (ox-rlr-slipshow-test--export
              "#+begin_quote\nQuoted.\n#+end_quote\n")))
    (should (string-match-p "{blockquote}" out))
    (should (string-match-p "^> Quoted\\." out))))

(ert-deftest ox-rlr-slipshow-horizontal-rule-is-html ()
  "A literal dash run would be parsed as a group separator."
  (let ((out (ox-rlr-slipshow-test--export "text\n\n-----\n\nmore\n")))
    (should (string-match-p "<hr>" out))))

(ert-deftest ox-rlr-slipshow-math-uses-dollar-delimiters ()
  (let ((out (ox-rlr-slipshow-test--export "Inline \\(x + y\\) and \\[z\\].\n")))
    (should (string-match-p (regexp-quote "$x + y$") out))
    (should (string-match-p (regexp-quote "$$z$$") out))))


;;; Structure

(ert-deftest ox-rlr-slipshow-slip-mode-groups-headlines ()
  (let ((out (ox-rlr-slipshow-test--export "#+OPTIONS: title:nil\n\n* One\n\ntext\n")))
    (should (string-match-p "{slip}" out))
    (should (string-match-p "^-----$" out))))

(ert-deftest ox-rlr-slipshow-slide-mode-has-no-empty-leading-slide ()
  "`children:slide' would turn a leading separator into a blank slide."
  (let* ((out (ox-rlr-slipshow-test--export
               "#+SLIPSHOW_STRUCTURE: slide\n#+OPTIONS: title:nil\n\n* One\n\ntext\n"))
         (close (string-match "\n---\n" out))
         (body (string-trim (substring out (+ close 5)))))
    (should (string-prefix-p "# One" body))))

(ert-deftest ox-rlr-slipshow-flat-mode-adds-no-groups ()
  (let ((out (ox-rlr-slipshow-test--export
              "#+SLIPSHOW_STRUCTURE: flat\n#+OPTIONS: title:nil\n\n* One\n\ntext\n")))
    (should (string-match-p "^# One$" out))
    (should-not (string-match-p "{slip}" out))))

(ert-deftest ox-rlr-slipshow-headline-property-attributes ()
  (let ((out (ox-rlr-slipshow-test--export
              (concat "#+OPTIONS: title:nil\n\n* One\n"
                      ":PROPERTIES:\n:ATTR_SLIPSHOW: #intro\n:END:\n\ntext\n"))))
    (should (string-match-p "{slip #intro}" out))))


;;; Attributes

(ert-deftest ox-rlr-slipshow-standalone-keyword ()
  (let ((out (ox-rlr-slipshow-test--export "a\n\n#+SLIPSHOW: pause\n\nb\n")))
    (should (string-match-p "^{pause}$" out))))

(ert-deftest ox-rlr-slipshow-inline-export-snippet ()
  "The inherited HTML transcoder fires only for the `html' back-end."
  (let ((out (ox-rlr-slipshow-test--export "text @@slipshow:{pause}@@ more\n")))
    (should (string-match-p (regexp-quote "{pause}") out))))

(ert-deftest ox-rlr-slipshow-element-attributes ()
  (let ((out (ox-rlr-slipshow-test--export
              "#+ATTR_SLIPSHOW: .definition title=\"Foo\"\nSome text.\n")))
    (should (string-match-p "{\\.definition title=\"Foo\"}" out))))

(ert-deftest ox-rlr-slipshow-pause-children-wraps-items ()
  "A trailing `{pause}' would bind to the last word alone."
  (let ((out (ox-rlr-slipshow-test--export
              "#+ATTR_SLIPSHOW: pause-children\n- first one\n- second one\n")))
    (should (string-match-p (regexp-quote "[second one]{pause}") out))
    ;; The first item stays visible, as Beamer's \pause does.
    (should-not (string-match-p (regexp-quote "[first one]{pause}") out))
    ;; The flag itself must not reach Slipshow, which would warn about it.
    (should-not (string-match-p "pause-children" out))))


;;; Blocks

(ert-deftest ox-rlr-slipshow-box-blocks-become-classes ()
  (let ((out (ox-rlr-slipshow-test--export
              "#+begin_theorem\nStatement.\n#+end_theorem\n")))
    (should (string-match-p "{\\.theorem}" out))))

(ert-deftest ox-rlr-slipshow-columns-carry-flexbox ()
  "Slipshow has no built-in column layout, so the styling is supplied."
  (let ((out (ox-rlr-slipshow-test--export
              (concat "#+begin_columns\n#+begin_group\nLeft\n#+end_group\n\n"
                      "#+begin_group\nRight\n#+end_group\n#+end_columns\n"))))
    (should (string-match-p "display:flex" out))
    (should (string-match-p (regexp-quote "children:style=\"flex:1\"") out))))

(ert-deftest ox-rlr-slipshow-explicit-style-wins-over-default ()
  (let ((out (ox-rlr-slipshow-test--export
              (concat "#+ATTR_SLIPSHOW: style=\"display:grid\"\n"
                      "#+begin_columns\nLeft\n#+end_columns\n"))))
    (should (string-match-p "display:grid" out))
    (should-not (string-match-p "display:flex" out))))


;;; Includes

(ert-deftest ox-rlr-slipshow-include-emits-an-include-element ()
  (let ((out (ox-rlr-slipshow-test--export
              "#+SLIPSHOW_INCLUDE: parts/one.slp\n")))
    (should (string-match-p
             (regexp-quote "{include src=\"parts/one.slp\"}") out))))

(ert-deftest ox-rlr-slipshow-include-carries-extra-attributes ()
  "Attributes on an include apply to the content it pulls in."
  (let ((out (ox-rlr-slipshow-test--export
              "#+SLIPSHOW_INCLUDE: parts/one.slp slip\n")))
    (should (string-match-p
             (regexp-quote "{include src=\"parts/one.slp\" slip}") out))))

(ert-deftest ox-rlr-slipshow-include-accepts-a-quoted-path ()
  "Quoting is the only way to name a path containing a space."
  (let ((out (ox-rlr-slipshow-test--export
              "#+SLIPSHOW_INCLUDE: \"my parts/one.slp\" slip\n")))
    (should (string-match-p
             (regexp-quote "{include src=\"my parts/one.slp\" slip}") out))))


;;; Images

(ert-deftest ox-rlr-slipshow-image-attributes-go-on-the-image ()
  "On its own line the attribute set lands on the paragraph, so sizing
an image that way silently does nothing."
  (let ((out (ox-rlr-slipshow-test--export
              "#+ATTR_SLIPSHOW: style=\"width:20%\"\n[[file:fig.svg]]\n")))
    (should (string-match-p
             (regexp-quote "](fig.svg){style=\"width:20%\"}") out))
    (should-not (string-match-p "^{style" out))))

(ert-deftest ox-rlr-slipshow-text-paragraph-keeps-its-attribute-line ()
  (let ((out (ox-rlr-slipshow-test--export
              "#+ATTR_SLIPSHOW: pause\nJust some words.\n")))
    (should (string-match-p "^{pause}$" out))))

(ert-deftest ox-rlr-slipshow-image-among-words-is-not-a-lone-image ()
  "Attaching the attributes to the image would move them off the
paragraph the author marked up."
  (let ((out (ox-rlr-slipshow-test--export
              "#+ATTR_SLIPSHOW: pause\nSee [[file:fig.svg]] here.\n")))
    (should (string-match-p "^{pause}$" out))))

(ert-deftest ox-rlr-slipshow-plain-image-is-untouched ()
  (let ((out (ox-rlr-slipshow-test--export "[[file:fig.svg]]\n")))
    (should (string-match-p (regexp-quote "](fig.svg)") out))
    (should-not (string-match-p "{" out))))


;;; Code blocks and math

(ert-deftest ox-rlr-slipshow-mermaid-gets-the-equals-prefix ()
  "Slipshow renders `=mermaid' as a diagram; plain `mermaid' is source.
A bare `mermaid' info string also makes Slipshow warn that highlightjs
does not know the language."
  (let ((out (ox-rlr-slipshow-test--export
              "#+begin_src mermaid\ngraph TD;\n  A-->B;\n#+end_src\n")))
    (should (string-match-p "^```=mermaid$" out))))

(ert-deftest ox-rlr-slipshow-other-languages-pass-through ()
  "#+begin_src html means show the markup, not inject it.
Injecting it is what #+begin_export html is for."
  (let ((out (ox-rlr-slipshow-test--export
              "#+begin_src html\n<p>source</p>\n#+end_src\n")))
    (should (string-match-p "^```html$" out))
    (should-not (string-match-p "=html" out))))

(ert-deftest ox-rlr-slipshow-language-mapping-can-be-disabled ()
  (let* ((org-rlr-slipshow-language-alist nil)
         (out (ox-rlr-slipshow-test--export
               "#+begin_src mermaid\ngraph TD;\n#+end_src\n")))
    (should (string-match-p "^```mermaid$" out))))

(ert-deftest ox-rlr-slipshow-math-frontmatter ()
  (let ((out (ox-rlr-slipshow-test--export
              (concat "#+SLIPSHOW_MATH_MODE: katex\n"
                      "#+SLIPSHOW_MATH_LINK: assets/katex\n\ntext\n"))))
    (should (string-match-p "^math-mode: katex$" out))
    (should (string-match-p "^math-link: assets/katex$" out))))

(ert-deftest ox-rlr-slipshow-math-mode-defaults-to-slipshow ()
  "Emitting a key Slipshow would have chosen anyway only adds noise."
  (let ((out (ox-rlr-slipshow-test--export "text\n")))
    (should-not (string-match-p "math-mode" out))))


;;; Speaker notes

(defconst ox-rlr-slipshow-test--notes-slip
  "#+OPTIONS: title:nil\n\n* One\n\n#+begin_notes\nRemember the funding.\n#+end_notes\n\nBody.\n")

(ert-deftest ox-rlr-slipshow-notes-ride-on-the-enclosing-slip ()
  "Every action attribute costs a step, so a bare `{speaker-note}' costs a
keypress per slip.  Referencing the note from the slip folds it into the
step that enters the slip instead."
  (let ((out (ox-rlr-slipshow-test--export ox-rlr-slipshow-test--notes-slip)))
    (should (string-match-p "{slip speaker-note=[^ }]+}" out))
    (should-not (string-match-p "{speaker-note" out))))

(ert-deftest ox-rlr-slipshow-notes-reference-resolves ()
  "The slip and the note derive the identifier separately.
Slipshow warns about a dangling reference rather than failing, so a
mismatch would compile cleanly and silently lose the note."
  (let ((out (ox-rlr-slipshow-test--export ox-rlr-slipshow-test--notes-slip)))
    (should (string-match "speaker-note=\\([^ }]+\\)" out))
    (let ((id (match-string 1 out)))
      (should (string-match-p (regexp-quote (concat "{#" id "}")) out)))))

(ert-deftest ox-rlr-slipshow-notes-are-grouped ()
  "A note is a `>' group, so multi-paragraph notes stay one element."
  (let ((out (ox-rlr-slipshow-test--export ox-rlr-slipshow-test--notes-slip)))
    (should (string-match-p "^> Remember the funding\\.$" out))))

(ert-deftest ox-rlr-slipshow-notes-with-attributes-stay-inline ()
  "Attributes on the block mean the author wants a step of their own."
  (let ((out (ox-rlr-slipshow-test--export
              (concat "#+OPTIONS: title:nil\n\n* One\n\n"
                      "#+ATTR_SLIPSHOW: pause\n#+begin_notes\nLater.\n#+end_notes\n"))))
    (should (string-match-p "{speaker-note pause}" out))
    (should-not (string-match-p "speaker-note=" out))))

(ert-deftest ox-rlr-slipshow-only-one-note-rides-per-slip ()
  "A repeated `speaker-note' attribute would collide on one element."
  (let ((out (ox-rlr-slipshow-test--export
              (concat "#+OPTIONS: title:nil\n\n* One\n\n"
                      "#+begin_notes\nFirst.\n#+end_notes\n\n"
                      "#+begin_notes\nSecond.\n#+end_notes\n"))))
    (should (string-match-p "{slip speaker-note=[^ }]+}" out))
    (should (string-match-p "{speaker-note}" out))
    ;; Exactly one note is hoisted; the other is left where it stands.
    (should (= 1 (ox-rlr-slipshow-test--count "speaker-note=" out)))))

(ert-deftest ox-rlr-slipshow-notes-do-not-revive-the-empty-leading-slide ()
  "Slide mode suppresses the separator before the first group.
Hoisting a note onto it would force the separator back and manufacture
the empty leading slide that suppression exists to prevent, so the
first slide's note stays inline."
  (let* ((out (ox-rlr-slipshow-test--export
               (concat "#+SLIPSHOW_STRUCTURE: slide\n#+OPTIONS: title:nil\n\n"
                       "* One\n#+begin_notes\nNote.\n#+end_notes\nBody.\n\n"
                       "* Two\nBody two.\n")))
         (close (string-match "\n---\n" out))
         (body (string-trim (substring out (+ close 5)))))
    (should (string-prefix-p "# One" body))
    (should (string-match-p "{speaker-note}" out))
    (should-not (string-match-p "speaker-note=" out))))

(ert-deftest ox-rlr-slipshow-slide-mode-notes-ride-on-the-slide ()
  "Every slide but a suppressed first one can carry the reference."
  (let ((out (ox-rlr-slipshow-test--export
              (concat "#+SLIPSHOW_STRUCTURE: slide\n#+OPTIONS: title:nil\n\n"
                      "* One\nBody.\n\n"
                      "* Two\n#+begin_notes\nNote.\n#+end_notes\nBody two.\n"))))
    (should (string-match-p "{speaker-note=[^ }]+}" out))
    (should-not (string-match-p "{speaker-note}" out))))

(ert-deftest ox-rlr-slipshow-notes-can-be-dropped ()
  (let ((out (ox-rlr-slipshow-test--export
              (concat "#+OPTIONS: title:nil notes:nil\n\n* One\n\n"
                      "#+begin_notes\nSecret.\n#+end_notes\n\nBody.\n"))))
    (should-not (string-match-p "Secret" out))
    (should-not (string-match-p "speaker-note" out))
    (should (string-match-p "Body\\." out))))

(ert-deftest ox-rlr-slipshow-flat-mode-notes-are-inline ()
  "Flat mode has no slip to hang the reference on."
  (let ((out (ox-rlr-slipshow-test--export
              (concat "#+SLIPSHOW_STRUCTURE: flat\n#+OPTIONS: title:nil\n\n* One\n\n"
                      "#+begin_notes\nInline.\n#+end_notes\n"))))
    (should (string-match-p "{speaker-note}" out))
    (should-not (string-match-p "speaker-note=" out))))

(ert-deftest ox-rlr-slipshow-notes-block-is-not-a-class ()
  "The fallback for an unknown block name would emit `{.notes}'."
  (let ((out (ox-rlr-slipshow-test--export ox-rlr-slipshow-test--notes-slip)))
    (should-not (string-match-p (regexp-quote "{.notes}") out))))


;;; Tables

(defconst ox-rlr-slipshow-test--rule-re
  "^| :?---:? | :?---:? |$"
  "Match a two-column GFM delimiter row under any alignment.
Org infers alignment from cell contents, so the markers vary.")

(ert-deftest ox-rlr-slipshow-table-is-gfm ()
  (let ((out (ox-rlr-slipshow-test--export
              "| a | b |\n|---+---|\n| 1 | 2 |\n")))
    (should (string-match-p "^| a | b |$" out))
    (should (string-match-p ox-rlr-slipshow-test--rule-re out))))

(ert-deftest ox-rlr-slipshow-headerless-table-gets-a-rule ()
  "GFM requires a delimiter row even when Org has no header."
  (let ((out (ox-rlr-slipshow-test--export "| 1 | 2 |\n| 3 | 4 |\n")))
    (should (string-match-p ox-rlr-slipshow-test--rule-re out))))

(provide 'ox-rlr-slipshow-test)

;;; ox-rlr-slipshow-test.el ends here
