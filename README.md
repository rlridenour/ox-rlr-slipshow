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
| `w` | Serve, and re-export on every save |
| `k` | Stop the server |
| `K` | Stop watching and serving |

### Writing with the presentation open

`org-rlr-slipshow-watch` (`w`) is the one to use while you write. Slipshow's
server already watches the exported `.slp` and reloads the browser when it
changes, so the only missing piece is rewriting that file — this adds an
`after-save-hook` that re-exports the buffer, and every `C-x C-s` reaches the
browser.

Only one buffer is watched at a time, because only one server runs. Calling it
again — in the same buffer or another one — releases the previous watcher first
rather than accumulating hooks or servers. `org-rlr-slipshow-unwatch` (`K`)
stops both the watching and the server, and killing the watched buffer does the
same.

Two things it deliberately does not do. Re-exports are always synchronous, since
an async export spawns a fresh Emacs and that is far too much for every save. And
if the server has gone away, the next save stops the watch and says so, rather
than quietly rewriting a file nothing is serving. A failed export is reported
without aborting the save or the rest of `after-save-hook`.

### Server buffers

The server runs in its own `*Slipshow Serve*` buffer, separate from the
`*Slipshow*` buffer compile runs use, so compiling never disturbs it. Stop it
with `k` in the dispatcher or `M-x org-rlr-slipshow-stop`, which sends SIGINT
and waits for the port to be released before insisting. Serving again stops any
running server first, rather than leaving one behind holding the port.

Org's table of contents is **off by default** here: a Markdown TOC is emitted
before the first slip separator, where it renders as stray content in the
top-level slip. Re-enable it per file with `#+OPTIONS: toc:t`.

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
| `#+begin_notes` (also `note`, `speaker_note`, `speaker_notes`) | a speaker note — see below |
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

## Images

An `#+ATTR_SLIPSHOW:` line before a paragraph applies to the *paragraph*, which
for a paragraph holding nothing but an image is the wrong target — sizing the
paragraph does not size the picture. So attributes on a lone image are attached
to the image inline:

```org
#+ATTR_SLIPSHOW: style="width:20%"
[[file:diagram.svg]]
```

becomes `![img](diagram.svg){style="width:20%"}`, which Slipshow puts on the
image's own container. A paragraph with anything else in it keeps the ordinary
attribute line, so marking up a sentence that happens to contain an image still
marks up the sentence.

Slipshow decides between image, video, audio, PDF and SVG from the file
extension, so plain Org links to any of those work. An SVG's internal ids are
addressable too, which is how you reveal a figure piece by piece:

```org
[[file:figure.svg]]

#+SLIPSHOW: reveal=my-square
```

## Multi-file presentations

Org's own `#+INCLUDE:` splices files together *before* export, and works here
unchanged — use it when you just want to split a long source file.

Slipshow's `{include}` is a different thing: it keeps the parts as separate
`.slp` files and assembles them at compile time, which is what you want for
incremental compilation and for pulling in HTML or SVG files. Emit one with:

```org
#+SLIPSHOW_INCLUDE: parts/introduction.slp slip
#+SLIPSHOW_INCLUDE: "parts/main results.slp" slip
```

Anything after the path is an attribute set applied to the included content, so
`slip` makes the included file a slip of its own. Quote the path if it contains
a space.

Paths resolve relative to the including file, and are passed through exactly as
you write them — this back-end cannot know where you export the other parts to.
Note that you reference the compiled `.slp`, not the `.org`; Slipshow names the
offending path if it cannot read one.

Export the parts themselves with **body-only** (`C-c C-e` then `C-b` before
choosing the output), which suppresses the frontmatter that only belongs in the
main file.

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

## Speaker notes

Slipshow has a speaker view, opened by pressing `s` during a presentation.
Write notes for it with `#+begin_notes`, the same block name Org's Beamer and
Reveal back-ends use:

```org
* What is a prime number?

#+begin_notes
Open by asking who remembers the sieve of Eratosthenes.

Do *not* get drawn into the twin prime conjecture here.
#+end_notes

Some motivating text.
```

Notes are hidden from the presentation itself, and the block body is exported
normally, so lists, math and emphasis all work inside one.

### Notes cost a step, unless they ride on a slip

Slipshow treats **every** action attribute as a step, and `speaker-note` is an
action. So the obvious translation — a `{speaker-note}` group sitting where you
wrote it — adds a keypress to the deck for every note you write.

This back-end avoids that. A section's first notes block is emitted as a plain
identified group, and the `speaker-note` attribute that points at it rides on
the enclosing slip:

```markdown
{slip speaker-note=org-slipshow-note-209}
-----
# What is a prime number?

{#org-slipshow-note-209}
> Open by asking who remembers the sieve of Eratosthenes.
```

The slip already spends a step being entered, and an element's actions all fire
together, so the note arrives as you reach the slip and costs nothing extra.

A note is left where you wrote it — taking its own step — when it can't ride
along:

- It isn't the first notes block in its section. Only one `speaker-note`
  attribute fits on an element, and a note that changes partway through a slip
  wants its own step anyway.
- It carries its own `#+ATTR_SLIPSHOW:` line. Attributes are how you ask for a
  step, so `#+ATTR_SLIPSHOW: pause` is the way to force this deliberately.
- The structure mode is `flat`, which has no slip to hang the reference on.
- It is on the first slide of a `slide`-mode deck that has no title. That
  separator is suppressed to avoid an empty leading slide, which leaves nothing
  to attach to.

Set `org-rlr-slipshow-notes-attach` to `nil` to switch this off and always emit
notes inline.

### Leaving notes out

Notes are hidden in the presentation but still readable in the generated `.slp`
and HTML. To drop them entirely:

```org
#+OPTIONS: notes:nil
```

or set `org-rlr-slipshow-with-notes` to `nil`.

## The title slip

`#+TITLE:` opens the deck with a title slip. Org has `#+AUTHOR:` and `#+DATE:`
and nothing in between, so an affiliation has a keyword of its own, and a logo
can be placed alongside:

```org
#+TITLE: Presentation Title
#+AUTHOR: Dr. Ridenour
#+SLIPSHOW_AFFILIATION: Department of Philosophy
#+DATE: 2026-08-02
#+SLIPSHOW_TITLE_LOGO: school.png
```

Each line is emitted with a class — `.author`, `.affiliation`, `.date` — so a
stylesheet can reach them by name rather than by `:nth-of-type`, which breaks
as soon as one is absent. The logo carries `.title-logo` on the image itself
rather than on the paragraph around it, so that width applies to the image.
Anything unset is omitted entirely, and `#+OPTIONS: title:nil` drops the slip.

Slipshow resolves the logo relative to the exported file and inlines it as a
data URI, so a path relative to the Org file works and the compiled deck stays
self-contained. `org-rlr-slipshow-affiliation` and
`org-rlr-slipshow-title-logo` supply defaults, which is usually what you want:
both are the same on every deck you give.

`css/title-slide.css` lays this out as two columns — text left, logo right,
both centred — and `css/helvetica.css` sets the face. `logos/` holds the
images. Use them together:

```org
#+SLIPSHOW_DIMENSION: 16:9
#+SLIPSHOW_TITLE_LOGO: logos/school.png
#+SLIPSHOW_CSS: css/helvetica.css css/title-slide.css
```

Both paths are relative to the Org file, so adjust them to wherever the deck
sits — or give absolute paths, which is what `org-rlr-slipshow-title-logo` is
for. The layout sheet assumes slip structure, the default; under
`#+SLIPSHOW_STRUCTURE: slide` the title goes into the slide's own title bar
instead of the body.

## Frontmatter

| Org keyword | Frontmatter key |
|---|---|
| `#+SLIPSHOW_THEME:` | `theme` |
| `#+SLIPSHOW_DIMENSION:` | `dimension` |
| `#+SLIPSHOW_CSS:` | `css` |
| `#+SLIPSHOW_JS:` | `js` |
| `#+SLIPSHOW_HIGHLIGHTJS_THEME:` | `highlightjs-theme` |
| `#+SLIPSHOW_MATH_MODE:` | `math-mode` — `mathjax` (Slipshow's default) or `katex` |
| `#+SLIPSHOW_MATH_LINK:` | `math-link` — a self-hosted math library |
| `#+SLIPSHOW_ATTRIBUTES:` | `attributes` |
| `#+SLIPSHOW_TOPLEVEL_ATTRIBUTES:` | `toplevel-attributes` |
| `#+SLIPSHOW_EXTERNAL_IDS:` | `external-ids` |

`#+SLIPSHOW_AFFILIATION:` and `#+SLIPSHOW_TITLE_LOGO:` are not frontmatter —
they feed the title slip, described above.

`org-rlr-slipshow-theme`, `org-rlr-slipshow-dimension`,
`org-rlr-slipshow-math-mode` and `org-rlr-slipshow-math-link` supply defaults.
Keys you leave unset are omitted rather than written out with Slipshow's own
default, so the frontmatter stays as small as the deck needs.

## Styling

Put your rules in a stylesheet next to the deck and name it:

```org
#+SLIPSHOW_THEME: vanier
#+SLIPSHOW_CSS: style.css
```

Slipshow loads `css` *after* the theme, so ordinary selectors override it
without `!important`. Several stylesheets are allowed, on one line or on
several `#+SLIPSHOW_CSS:` lines. Local files are inlined into the compiled
HTML, which stays self-contained; only `http(s)://` values remain as links.

Paths resolve against the *source file*, not the working directory, so a
relative path works however the export was invoked. Paths in `theme`, `css`,
`js` and `math-link` may begin with `~`, which this back-end expands — Slipshow
does not, and would otherwise warn that the file is unreadable and then compile
the deck without it.

`#+SLIPSHOW_THEME:` also accepts a path, but a CSS file *replaces* the built-in
theme rather than adding to it: you lose both the base rules and the embedded
fonts. Prefer naming a built-in theme (`default`, `vanier`, `none`) and
layering your own rules through `#+SLIPSHOW_CSS:`. For a house style shared
across decks, point `org-rlr-slipshow-theme` at an absolute path, or keep the
keywords in a `#+SETUPFILE:`.

A missing stylesheet is only a warning, not an error, so a typo yields an
unstyled deck that compiled "successfully" — worth a glance at the compile
output the first time you wire one up.

`css/` holds the sheets these decks use: `helvetica.css` sets the face,
`title-slide.css` lays out the title slip, and `arg.css` renders a numbered
list as a logical argument in standard form — premises, a rule, then the
conclusion:

```org
#+ATTR_SLIPSHOW: .arg
1. If it is raining, the streets are wet.
2. It is raining.
3. The streets are wet.
```

Each is a starting point to copy and adjust rather than a supported theme.

## Math and tables

Org LaTeX fragments are normalised to Slipshow's delimiters: `\(x\)` becomes
`$x$`, `\[x\]` becomes `$$x$$`, and LaTeX environments are wrapped in `$$`.
Rendering is MathJax unless you ask for KaTeX with `#+SLIPSHOW_MATH_MODE:`.

Org tables are emitted as GFM tables with alignment preserved; a delimiter row
is synthesised for tables that have no header, since GFM requires one.

## Code blocks and diagrams

Src blocks become fenced blocks, and the language passes through — except
where Slipshow gives an info string a meaning of its own:

| Org | Emitted | Result |
|---|---|---|
| `#+begin_src mermaid` | ` ```=mermaid ` | a rendered diagram |
| `#+begin_src slip-script` | ` ```slip-script ` | a script that runs |
| `#+begin_src html` | ` ```html ` | HTML shown as source |
| `#+begin_export html` | the markup itself | HTML injected into the page |

Mermaid needs the `=` prefix to render; a plain ` ```mermaid ` fence is
highlighted as source *and* makes Slipshow warn that it doesn't know the
language. `html` is deliberately left alone, since `#+begin_src html` means
you want to show the markup — `#+begin_export html` is how you inject it.

The mapping lives in `org-rlr-slipshow-language-alist`; set it to `nil` to emit
every language verbatim, as a presentation about Mermaid itself would want.

Actions work on code blocks like anything else, so `#+ATTR_SLIPSHOW: exec` on
a `js` block runs it on that step.

## Known limitations

- An `#+ATTR_SLIPSHOW:` line on a paragraph **inside a list item** is indented
  along with the item body, and Slipshow then ignores it. Use
  `pause-children` on the list, or an inline `@@slipshow:...@@` snippet.
- Org's `[[link][description]]` inside a paused list item works, but item text
  containing an unbalanced `]` may confuse the `[...]{pause}` wrapper.
- A `{pause}` or other action **inside** a notes block still consumes a step,
  even though the note it lives in is hidden.
- Image alt text is always the literal `img`, which is what ox-md emits; write
  the image as raw HTML if the alt text matters.
- Targeting an id **inside an SVG** works at runtime, but Slipshow's
  compile-time check does not look into SVG assets, so it warns that the id was
  not found. The warning is safe to ignore.

## Example

`examples/demo.org` exercises every feature above. Build it with:

```sh
./examples/build.sh
```

The deck is assembled from two Org files, which is the point of the
`#+SLIPSHOW_INCLUDE:` slip: `examples/parts/history.org` is exported body-only
and spliced in by Slipshow at compile time. `examples/figures/number-line.svg`
carries ids on its own groups, so the *Figures* slip sizes the image and then
reveals the primes on it as a separate step.

One caveat if you run the build: it prints

```
warning: No element with id 'primes' was found
```

That is a false positive. Slipshow's compile-time id check does not look inside
SVG assets, but the id is present in the compiled page — you can see it in
`examples/demo.html` — and the reveal works.

If you write the export by hand rather than using the script, note that
`find-file` moves `default-directory` to the Org file's own directory, so give
`org-export-to-file` an absolute path.

## Tests

```sh
emacs --batch -L . -l test/ox-rlr-slipshow-test.el -f ert-run-tests-batch-and-exit
```

The suite covers Slipshow's divergences from CommonMark (brace escaping,
`{blockquote}`, `<hr>`, math delimiters), the three structure modes, all four
attribute mechanisms, speaker notes, and — importantly — that each export
command accepts the four arguments `org-export-dispatch` passes it. Testing
`org-export-to-file` directly does not exercise that path.

## License

GPL-3.0-or-later.
