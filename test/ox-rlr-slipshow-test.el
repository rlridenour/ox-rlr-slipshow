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
