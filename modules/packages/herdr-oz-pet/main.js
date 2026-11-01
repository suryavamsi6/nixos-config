// A small procedural pixel pet for the 0oz design layout: a grid of colored
// divs, no image files. It breathes when nothing is happening, trots while an
// agent works, trembles and says "needs you!" when one is blocked, and hops
// with a "done!" bubble when one finishes while nobody was looking. Click it
// for hearts.
//
// A hidden layout block opens a frameless, freely draggable window for the pet.
import { View, div } from "gpui-kit";
import { h_flex, v_flex } from "gpui-base";
import { agents, closeOverlay, openOverlay, props, setShared, shared, theme } from "herdr";

const W = 16; // art width in cells; rows are padded to it
const PX = 4; // one cell in px, so the pet is 64x64
const TICK = 40; // ms between looks at the art

// '.' nothing. O outline, B body, E eye white, D pupil, N nose, H heart, S spark.
const BASE = [
  "....O......O....",
  "...OBO....OBO...",
  "..OBBO....OBBO..",
  "..OBBBOOOOBBBO..",
  ".OBBBBBBBBBBBBO.",
  ".OBBBBBBBBBBBBO.",
  ".OBBEEBBBBEEBBO.",
  ".OBBEDBBBBDEBBO.",
  ".OBBEEBBBBEEBBO.",
  ".OBDBBBBBBBBDBO.",
  ".OBBBBBNNBBBBBO.",
  ".OBBBBBBBBBBBBO.",
  ".OCBBBBBBBBBBCO.",
  "..OCBBBBBBBBCO..",
  "..OBBBOOOOBBBO..",
  "...OOO....OOO...",
];

// States are BASE with a few rows swapped, so the pet always stays itself.
const ART = {
  // idle: a slow blink.
  idle: [
    {},
    {
      6: ".OBBBBBBBBBBBBO.",
      7: ".OBBOOBBBBOOBBO.",
      8: ".OBBBBBBBBBBBBO.",
    },
  ],
  // working: paws step, and a spark of effort by the ear.
  working: [
    {
      0: "....O......O..S.",
      14: "..OBBBOOOOBBBO..",
      15: "...OOO....OOO...",
    },
    {
      14: "..OBBBBOOBBBBO..",
      15: "....OOO..OOO....",
    },
  ],
  // blocked: eyes wide, brows down, mouth a flat line, paws up.
  blocked: [
    {
      5: ".OBBOBBBBBBOBBO.",
      6: ".OBBEEBBBBEEBBO.",
      7: ".OBBEEBBBBEEBBO.",
      10: ".OBBBBOOOOBBBBO.",
      15: "..OOOO....OOOO..",
    },
    {
      5: ".OBBOBBBBBBOBBO.",
      6: ".OBBEEBBBBEEBBO.",
      7: ".OBBEEBBBBEEBBO.",
      10: ".OBBBBOOOOBBBBO.",
      15: ".OOOO......OOOO.",
    },
  ],
  // done: a hop, happy eyes, a spark.
  done: [
    {
      0: ".....S....S.....",
      6: ".OBBDBBBBBBDDBO.",
      7: ".OBBDBBBBBBDDBO.",
      8: ".OBBBBBBBBBBBBO.",
      10: ".OBBBBNNNNBBBBO.",
      15: ".OOOO......OOOO.",
    },
    {
      0: "........S.......",
      6: ".OBBDBBBBBBDDBO.",
      7: ".OBBDBBBBBBDDBO.",
      8: ".OBBBBBBBBBBBBO.",
      10: ".OBBBBNNNNBBBBO.",
      14: "..OBBBOOOOBBBO..",
      15: "...OOO....OOO...",
    },
  ],
  // pat: hearts instead of ears.
  pat: [
    {
      0: "....H......H....",
      1: "...HHH....HHH...",
      2: "...OBO....OBO...",
    },
    {
      0: ".....H....H.....",
      1: "....HHH..HHH....",
      2: "...OBO....OBO...",
    },
  ],
};

const FRAME_MS = { idle: 900, working: 150, blocked: 200, done: 220, pat: 190 };
const RANK = { blocked: 3, done: 2, working: 1, idle: 0 };

// Build one state's frames from BASE plus the overrides.
function frames(name) {
  return ART[name].map((over) => {
    const rows = BASE.slice();
    for (const [i, line] of Object.entries(over)) rows[Number(i)] = line;
    return rows.map((r) => r.padEnd(W, ".").slice(0, W));
  });
}
const READY = Object.fromEntries(Object.keys(ART).map((k) => [k, frames(k)]));

const COLORS = {
  theme: null,
  peach: ["#e89a65", "#b96749"],
  mint: ["#83c8b6", "#4f9b8f"],
  blue: ["#83b4ea", "#5083c2"],
  rose: ["#e6a1b2", "#bd718b"],
};

// The most urgent agent status, the way a space's status is computed.
function mood() {
  let best = "idle";
  for (const a of agents()) {
    if ((RANK[a.status] ?? 0) > (RANK[best] ?? 0)) best = a.status;
  }
  return best;
}

export default class OzPet extends View {
  init(_props, cx) {
    const p = props();
    this.panel = p?.panel === true;
    this.launcher = !this.panel && !p?.overlay;
    if (this.launcher) {
      this.open = false;
      const sync = () => {
        const enabled = shared("oz-pet.enabled") !== false;
        if (enabled && !this.open) {
          this.overlay = openOverlay({ mod: "oz-pet", kind: "window", frame: "none", key: "oz-pet", keep: true });
          this.open = true;
        } else if (!enabled && this.open) {
          closeOverlay(this.overlay);
          this.open = false;
        }
      };
      sync();
      cx.timer.every(500, sync);
      return;
    }
    if (this.panel) return;
    this.tick = 0;
    this.state = "idle";
    this.bubble = null; // { text, warning }
    this.patUntil = 0;
    this.seen = "idle";
    this.shown = ""; // what was last drawn, so a still pet costs no redraws
    this.bubbleUntil = 0;
    cx.timer.every(TICK, (cx) => {
      if (shared("oz-pet.enabled") === false) {
        closeOverlay(props()?.overlay);
        return;
      }
      this.tick++;
      const now = Date.now();
      const next = mood();
      if (next !== this.seen) {
        this.seen = next;
        if (next === "blocked") this.bubble = { text: "needs you!", warning: true };
        else if (next === "done") this.bubble = { text: "done!", warning: false };
        else this.bubble = null;
        // A bubble waits on the status it announced, not on a fixed clock.
        this.bubbleUntil = now + (next === "blocked" ? 8000 : 5000);
      }
      if (this.bubble && now > this.bubbleUntil) this.bubble = null;
      const see = now < this.patUntil ? "pat" : next;
      const key = this.paint(see, now);
      if (key !== this.shown) {
        this.shown = key;
        this.state = see;
        cx.notify();
      }
    });
  }

  // Where the animation is, as a string: only a change here needs a redraw.
  paint(state, now) {
    const ms = FRAME_MS[state] ?? 300;
    const index = Math.floor((this.tick * TICK) / ms) % READY[state].length;
    const jitter = state === "blocked" ? this.tick % 2 : 0;
    const hop = state === "done" ? (Math.floor(this.tick / 4) % 2) * 2 : 0;
    const bubble = this.bubble ? this.bubble.text : "";
    return `${state}/${index}/${jitter}/${hop}/${bubble}/${shared("oz-pet.color")}`;
  }

  // One art row: runs of one letter become a div, runs of dots a spacer.
  rowEl(text, t, color) {
    const colors = COLORS[color];
    const paint = {
      O: t.canvas,
      B: colors?.[0] ?? t.muted,
      C: colors?.[1] ?? t.accent,
      E: t.foreground,
      D: t.canvas,
      N: t.blocked,
      H: t.blocked,
      S: t.working,
    };
    const cells = [];
    for (let x = 0; x < W; ) {
      const c = text[x];
      let n = 1;
      while (x + n < W && text[x + n] === c) n++;
      cells.push(c === "." ? div().w(n * PX).h(PX) : div().w(n * PX).h(PX).bg(paint[c] ?? t.accent));
      x += n;
    }
    return h_flex().flex_none().children(cells);
  }

  render() {
    if (this.launcher) return div();
    const t = theme();
    const selected = shared("oz-pet.color");
    const color = Object.hasOwn(COLORS, selected) ? selected : "theme";
    if (this.panel) {
      const enabled = shared("oz-pet.enabled") !== false;
      const button = (id, label, active, action) => div().id(id).px(12).py(8).rounded(6)
        .bg(active ? t.selected : t.raised).text_color(active ? t.foreground : t.muted)
        .cursor_pointer().on_click(action).child(label);
      return v_flex().w_full().p(18).gap(14).bg(t.surface).text_color(t.foreground)
        .child(div().text_size(18).font_semibold().child("Pet settings"))
        .child(h_flex().items_center().justify_between().child("Show pet")
          .child(button("pet-enabled", enabled ? "On" : "Off", enabled, () => setShared("oz-pet.enabled", !enabled))))
        .child(div().text_size(12).text_color(t.muted).child("Pet color"))
        .child(h_flex().gap(10).children(Object.keys(COLORS).map(id =>
          div().id(`pet-color-${id}`).size(32).rounded_full().flex().items_center().justify_center()
            .border_2().border_color(color === id ? t.foreground : t.border)
            .bg(COLORS[id]?.[0] ?? t.muted).cursor_pointer()
            .tooltip(id === "theme" ? "Theme" : id[0].toUpperCase() + id.slice(1))
            .accessibility_label(`${id} pet color${color === id ? ", selected" : ""}`)
            .on_click(() => setShared("oz-pet.color", id))
            .when(color === id, el => el.child(div().size(8).rounded_full().bg(t.canvas)))
        )));
    }
    const state = READY[this.state] ? this.state : "idle";
    const ms = FRAME_MS[state] ?? 300;
    const index = Math.floor((this.tick * TICK) / ms) % READY[state].length;
    const frame = READY[state][index];
    const jitter = state === "blocked" ? this.tick % 2 : 0;
    const hop = state === "done" ? (Math.floor(this.tick / 4) % 2) * 2 : 0;

    return v_flex()
      .items_center()
      .gap(3)
      .when(Boolean(this.bubble), (el) =>
        el.child(
          div()
            .bg(t.raised)
            .border_1()
            .border_color(t.border)
            .rounded(6)
            .px(6)
            .py(2)
            .text_size(10.5)
            .text_color(this.bubble.warning ? t.blocked : t.done)
            .child(this.bubble.text),
        ),
      )
      .child(
        div()
          .id("oz-pet")
          .ml(jitter)
          .mt(hop)
          .on_click(() => {
            this.patUntil = Date.now() + 1400;
          })
          .child(v_flex().flex_none().children(frame.map((line) => this.rowEl(line, t, color)))),
      );
  }
}
