// Derived from the `workspace-chrome` mod shipped with Herdr (Apache-2.0, https://github.com/herdrdev/herdr-app).
// Modified by 0OZ: brand bar, solid sidebar footer with Settings, Add machine and an account chip.
import { View, div, image, svg } from "gpui-kit";
import { h_flex, v_flex } from "gpui-base";
import { theme, run, props, window, shared, setShared, updates, agents, home, openOverlay } from "herdr";

const SIDEBAR_W = 256;
const COLLAPSED_W = 44;
const basename = (path) => path.replace(/\/+$/, "").split("/").pop();

export default class WorkspaceChrome extends View {
  button(id, label, action) {
    const t = theme();
    return div().id(id).size(28).flex_none().flex().items_center().justify_center().rounded(8).text_color(t.muted).hover(s => s.bg(t.hover).text_color(t.foreground))
      .on_mouse_down("left", (_e, cx) => cx.stop_propagation()).on_click(action).child(label);
  }
  render() {
    const t = theme();
    const collapsed = shared("sidebar.collapsed") === true;
    const toggle = () => {
      setShared("sidebar.collapsed", !collapsed);
      run("layout.resize", { id: "sidebar", px: collapsed ? (shared("sidebar.width") ?? SIDEBAR_W) : COLLAPSED_W });
    };
    if (props()?.footer) {
      // Secondary nav (Settings, Add machine), then the account chip, as in shadcn's dashboard-01.
      const row = (id, icon, label, dim, action) => h_flex().id(id).h(32).px(10).gap(10).items_center().rounded(8)
        .text_color(dim ? t.dim : t.muted).hover(s => s.bg(t.hover).text_color(t.foreground)).cursor_pointer()
        .on_click(action).child(icon === "pet"
          ? v_flex().size(16).flex_none().children([
              "....O......O....", "...OBO....OBO...", "..OBBO....OBBO..", "..OBBBOOOOBBBO..",
              ".OBBBBBBBBBBBBO.", ".OBBBBBBBBBBBBO.", ".OBBEEBBBBEEBBO.", ".OBBEDBBBBDEBBO.",
              ".OBBEEBBBBEEBBO.", ".OBDBBBBBBBBDBO.", ".OBBBBBNNBBBBBO.", ".OBBBBBBBBBBBBO.",
              ".OCBBBBBBBBBBCO.", "..OCBBBBBBBBCO..", "..OBBBOOOOBBBO..", "...OOO....OOO...",
            ].map(line => h_flex().children([...line].map(pixel =>
              div().size(1).when(pixel !== ".", el => el.bg(({ O: t.canvas, B: t.muted, C: t.accent, E: t.foreground, D: t.canvas, N: t.blocked })[pixel]))))))
          : svg(`mods/oz-chrome/${icon}.svg`).size(15))
        .when(!collapsed, el => el.child(label));
      const who = basename(home()) || "me";
      const chip = h_flex().id("account").h(48).px(8).gap(10).items_center().rounded(8).cursor_pointer()
        .hover(s => s.bg(t.hover)).on_click(() => run("app.settings"))
        .child(div().size(32).flex_none().rounded(8).bg(t.selected).flex().items_center().justify_center().font_semibold().text_size(13).text_color(t.foreground).child(who[0].toUpperCase()))
        .when(!collapsed, el => el.child(v_flex().flex_1().min_w(0)
          .child(div().truncate().text_size(13).font_medium().text_color(t.foreground).child(who))
          .child(div().truncate().text_size(11.5).text_color(t.muted).child(`${agents().length} agents`))));
      return v_flex().size_full().bg(t.chrome).px(8).pt(4).pb(8).gap(2).text_size(13)
        .child(row("settings", "settings", "Settings", false, () => run("app.settings"))
          .when(Boolean(updates().app.ready), el => el.child(div().size(6).rounded_full().bg(t.accent))))
        .child(row("pet-settings", "pet", "Pet settings", false, () => openOverlay({ mod: "oz-pet", kind: "dialog", props: { panel: true } })))
        .child(row("machine", "plus", "Add machine", true, () => run("mod.open", { name: "machine-add" })))
        .child(div().h(1).my(4).bg(t.border))
        .child(chip);
    }
    return h_flex().size_full().bg(t.chrome).pl(collapsed ? 6 : 14).pr(10).gap(4).items_center().text_size(14)
      .when(window()?.platform === "macos" && !collapsed, el => el.pl(76))
      .when(!collapsed, el => el.child(h_flex().flex_1().gap(9).items_center().child(image("frame/welcome/herdr.png").size(22).rounded(6)).child(div().font_semibold().text_color(t.foreground).child("Herdr"))))
      .when(!collapsed, el => el.child(this.button("search", svg("mods/oz-chrome/search.svg").size(15), () => run("mod.open", { name: "picker" }))))
      .child(this.button("sidebar-toggle", svg("mods/oz-chrome/sidebar.svg").size(15), toggle));
  }
}
