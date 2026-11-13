/**
 * Make pi-intercom's UI match Pi's
 *
 * pi-intercom hardcodes rounded frame glyphs and a `→` row cursor. Its inline
 * message box is a registered renderer, so this overlay re-registers
 * `intercom_message`:
 * discovered extensions load before packages and Pi's renderer lookup takes the
 * first match, which makes the override work without patching the installed
 * package. Its popups (session list, compose box, handover picker) are built
 * inside pi-intercom and cannot be re-registered, so their glyphs are rewritten
 * through the theme Pi hands them. Both mechanisms live in
 * `utils/intercom-frame.ts`.
 *
 * The import walks into the managed install because the package is not
 * resolvable from this directory. It is the personal install path; a
 * project-local pi-intercom would need the path adjusted.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { InlineMessageComponent } from "../npm/node_modules/pi-intercom/ui/inline-message.ts";
import { createRenderer, squareThemeFrames } from "./utils/intercom-frame.ts";

export default function (pi: ExtensionAPI) {
  pi.registerMessageRenderer(
    "intercom_message",
    createRenderer(InlineMessageComponent),
  );

  pi.on("session_start", (_event, ctx) => squareThemeFrames(ctx.ui.theme));
}
