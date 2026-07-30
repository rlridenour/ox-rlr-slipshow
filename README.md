# ox-rlr-slipshow

An Org mode export back-end that produces source for
[Slipshow](https://github.com/panglesd/slipshow), a presentation engine whose
input is an extension of CommonMark.

## Why not just export Markdown?

Slipshow's dialect looks like Markdown but diverges in ways that make a plain
Markdown exporter produce silently wrong output:

| Slipshow | Consequence |
|---|---|
| `>` introduces a **group**, not a block quote | Real quotes need an explicit `{blockquote}` attribute |
| Setext headings are rejected | Headings must be ATX (`#`) |
| `{...}` is attribute syntax | A literal `{` in prose is parsed as an attribute and **swallows the text inside it** |
| `---` separates sibling groups | An Org horizontal rule would silently split your presentation |

This back-end handles all four: braces in prose are escaped, quote blocks get
their `{blockquote}` attribute, headings are always ATX, and horizontal rules
are emitted as `<hr>` so they never collide with the group separators.

## Installation

Put `ox-rlr-slipshow.el` on your `load-path` and:

```elisp
(require 'ox-rlr-slipshow)
```

Or with `use-package` and a local checkout:

```elisp
(use-package ox-rlr-slipshow
  :load-path "~/github/ox-rlr-slipshow"
  :after org)
```

The export-to-HTML and serve commands shell out to the
[`slipshow`](https://github.com/panglesd/slipshow) CLI, which must be on your
`PATH` (or named by `org-rlr-slipshow-command`).

## Exporting

From the Org export dispatcher (`C-c C-e`), press `y`:

| Key | Command |
|---|---|
| `Y` | Export to a `*Org Slipshow Export*` buffer |
| `y` | Export to a `.slp` file |
| `h` | Export and compile to standalone HTML |
| `o` | Export, compile, and open in a browser |
| `s` | Export and `slipshow serve` with live reload |

## Document structure

`org-rlr-slipshow-structure` (or `#+SLIPSHOW_STRUCTURE:` per file) picks how
headlines map onto Slipshow:

- **`slip`** (default) — headlines at `org-rlr-slipshow-slip-level` become
  `{slip}` groups. This is Slipshow's native style: one continuous surface that
  is scrolled and zoomed rather than paged.
- **`slide`** — headlines become fixed-height slides separated by `---`, with
  the `children:slide` frontmatter emitted for you.
- **`flat`** — no grouping at all; headlines are plain headings and you build
  structure by hand.

Set `org-rlr-slipshow-nest-subslips` to `t` to make deeper headlines into
nested sub-slips (emitted as `>` groups carrying a `slip` attribute) rather
than plain headings.

## Attributes

Four complementary mechanisms, each reaching a position the others cannot:

| Syntax | Reaches |
|---|---|
| `#+ATTR_SLIPSHOW: .definition title="Foo"` | the next element |
| `#+SLIPSHOW: pause` | *between* elements, attached to nothing |
| `:ATTR_SLIPSHOW: slip .dark` (property drawer) | a headline's own slip |
| `@@slipshow:{pause}@@` | inline, mid-sentence |

```org
* What is a prime number?
:PROPERTIES:
:ATTR_SLIPSHOW: #intro
:END:

Some motivating text.

#+SLIPSHOW: pause

#+ATTR_SLIPSHOW: .definition title="Prime number"
A *prime number* is an integer divisible by exactly two integers.
```

becomes

```markdown
{slip #intro}
-----
# What is a prime number?

Some motivating text.

{pause}

{.definition title="Prime number"}
A **prime number** is an integer divisible by exactly two integers.
```

Inline snippets are raw passthrough and are **not** validated — a typo'd
`{pasue}` compiles to a silently dead attribute. That is the cost of an escape
hatch, and it is what lets the other three mechanisms stay strict.

## Blocks

Any Org special block becomes an attributed Slipshow group. The block name is
the attribute:

| Org | Slipshow |
|---|---|
| `#+begin_theorem` (also `definition`, `proof`, `lemma`, `example`, `remark`, `corollary`, `block`) | `{.theorem}` |
| `#+begin_slip`, `#+begin_slide`, `#+begin_carousel`, `#+begin_blockquote` | `{slip}` |
| `#+begin_group` | a bare `>` group |
| `#+begin_anything_else` | `{.anything_else}` |

Columns are groups nested inside a `columns` block:

```org
#+begin_columns
#+begin_group
*Left column*
#+end_group

#+begin_group
*Right column*
#+end_group
#+end_columns
```

Slipshow has **no built-in column layout** — the `columns` class in its
documentation is illustrative, and the reader is expected to supply flexbox
CSS. So this back-end supplies it, emitting

```markdown
{.columns style="display:flex; gap:2em" children:style="flex:1"}
```

which lays the columns out evenly however many there are. `#+begin_columns-3`
and similar names work the same way. To take over the styling yourself, either
set `org-rlr-slipshow-columns-style` and `org-rlr-slipshow-column-style` to
`nil`, or just give the block your own `style=`, which takes precedence:

```org
#+ATTR_SLIPSHOW: style="display:grid; grid-template-columns:2fr 1fr"
#+begin_columns
...
#+end_columns
```

## Progressive lists

Off by default. Enable per list:

```org
#+ATTR_SLIPSHOW: pause-children
- Every integer greater than 1 has a prime factor.
- There are infinitely many primes.
- Primes thin out, but they never stop.
```

The first item stays visible and each subsequent one appears on its own step,
matching Beamer's `\pause`. Set `org-rlr-slipshow-pause-lists` to `t` to make
this the default for every list.

Each item is emitted as `[item text]{pause}`. The bracket grouping matters: a
bare trailing `{pause}` binds only to the inline element it touches, which on a
multi-word item would pause the last word alone.

## Frontmatter

| Org keyword | Frontmatter key |
|---|---|
| `#+SLIPSHOW_THEME:` | `theme` |
| `#+SLIPSHOW_DIMENSION:` | `dimension` |
| `#+SLIPSHOW_CSS:` | `css` |
| `#+SLIPSHOW_JS:` | `js` |
| `#+SLIPSHOW_HIGHLIGHTJS_THEME:` | `highlightjs-theme` |
| `#+SLIPSHOW_ATTRIBUTES:` | `attributes` |
| `#+SLIPSHOW_TOPLEVEL_ATTRIBUTES:` | `toplevel-attributes` |
| `#+SLIPSHOW_EXTERNAL_IDS:` | `external-ids` |

`org-rlr-slipshow-theme` and `org-rlr-slipshow-dimension` supply defaults.

## Math and tables

Org LaTeX fragments are normalised to Slipshow's delimiters: `\(x\)` becomes
`$x$`, `\[x\]` becomes `$$x$$`, and LaTeX environments are wrapped in `$$`.
Org tables are emitted as GFM tables with alignment preserved; a delimiter row
is synthesised for tables that have no header, since GFM requires one.

## Known limitations

- An `#+ATTR_SLIPSHOW:` line on a paragraph **inside a list item** is indented
  along with the item body, and Slipshow then ignores it. Use
  `pause-children` on the list, or an inline `@@slipshow:...@@` snippet.
- Org's `[[link][description]]` inside a paused list item works, but item text
  containing an unbalanced `]` may confuse the `[...]{pause}` wrapper.

## Example

`examples/demo.org` exercises every feature above. To build it:

```sh
emacs --batch -L . --eval '(progn (require (quote ox-rlr-slipshow)) \
  (find-file "examples/demo.org") \
  (org-export-to-file (quote rlr-slipshow) (expand-file-name "examples/demo.slp")))'
slipshow compile examples/demo.slp -o examples/demo.html
```

## License

GPL-3.0-or-later.
