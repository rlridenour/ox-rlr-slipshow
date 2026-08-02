/* Restyle Slipshow's speaker notes window.
 *
 *     #+SLIPSHOW_JS: css/speaker-view.js
 *
 * This is JavaScript rather than CSS because the speaker view is not part
 * of the presentation document: pressing `s' opens a popup window whose
 * whole source the engine writes with document.write, carrying its own
 * inline <style>.  Nothing named in #+SLIPSHOW_CSS: reaches it, so the
 * rules have to be carried over by hand.
 *
 * What the engine's own stylesheet does, and why this is needed:
 * `#slswrapper { font-size: 2em }' doubles everything in the panel,
 * including the notes, which is what makes them hard to skim.  The two
 * paragraphs of prose explaining mirror view are dropped here; the
 * buttons say what they do.
 *
 * The engine's <style> is written at the end of <body>, so a rule of
 * equal specificity injected into <head> loses to it on document order.
 * Every selector below is therefore qualified with `body', which beats a
 * bare id and does not depend on where this ends up in the document. */

(function () {
  "use strict";

  var CSS = [
    /* The panel's base size: the engine sets 2em, which is 32px, and
     * everything in the panel inherits it.  This is the one number to
     * change if the notes want to be bigger or smaller. */
    "body #slswrapper { font-size: 1em; padding: 20px 24px; }",

    /* Still glanceable from a step away; 2em of the engine's doubled base
     * came to 64px. */
    "body #timer, body #clock { font-size: 1.75em; }",

    "body #notes_div { font-size: 1.25em; line-height: 1.45; }",
    "body #notes_div p { margin: 0 0 0.7em 0; }",

    /* The buttons are self-explanatory; the prose beside them is not
     * worth the space it takes on a presenter screen. */
    "body #mirror-button-div span, body #clone-button-div span { display: none; }",

    /* The engine pins these at 20px, which is large once the panel around
     * them is no longer doubled. */
    "body button, body input[type=button] { font-size: 1em; }"
  ].join("\n");

  var MARKER = "slipshow-speaker-view-restyle";

  function inject(win) {
    var tries = 0;
    var timer = setInterval(function () {
      var doc;
      try {
        doc = win.document;
      } catch (e) {
        clearInterval(timer);          /* not ours to touch */
        return;
      }
      /* Wait for the engine's document.write: injecting before it would
       * be discarded, because writing to a loaded document reopens it. */
      if (doc && doc.getElementById("slswrapper")) {
        if (!doc.getElementById(MARKER)) {
          var style = doc.createElement("style");
          style.id = MARKER;
          style.textContent = CSS;
          (doc.head || doc.body || doc.documentElement).appendChild(style);
        }
        clearInterval(timer);
      } else if (++tries > 100) {
        clearInterval(timer);          /* ~10s; the popup never appeared */
      }
    }, 100);
  }

  function patch(w) {
    try {
      var nativeOpen = w.open;
      w.open = function () {
        var win = nativeOpen.apply(this, arguments);
        if (win) inject(win);
        return win;
      };
    } catch (e) {
      /* Not same-origin; nothing to do. */
    }
  }

  /* The popup is opened by the previewer -- the outer document holding the
   * presentation in an iframe -- not by the presentation itself, where
   * this script runs.  Patching only our own window would never fire.  The
   * iframe is a srcdoc, so it shares the parent's origin. */
  var seen = [];
  [window.parent, window.top, window].forEach(function (w) {
    if (w && seen.indexOf(w) < 0) {
      seen.push(w);
      patch(w);
    }
  });
})();
