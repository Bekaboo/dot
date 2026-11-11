/**
 * Make pi-intercom's inline message box squared
 *
 * pi-intercom hardcodes rounded frame glyphs, so this overlay re-registers its
 * `intercom_message` renderer. Discovered extensions load before packages and
 * Pi's renderer lookup takes the first match, which makes the override work
 * without patching the installed package. The corner swap and renderer live in
 * `lib/intercom-frame.ts`; the class is passed in from here so that module stays
 * loadable by `node --test`, which cannot type-strip node_modules (see the
 * workaround note there).
 *
 * The import walks into the managed install because the package is not
 * resolvable from this directory. It is the personal install path; a
 * project-local pi-intercom would need the path adjusted.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { InlineMessageComponent } from "../npm/node_modules/pi-intercom/ui/inline-message.ts";
import { createRenderer } from "./lib/intercom-frame.ts";

export default function (pi: ExtensionAPI) {
  pi.registerMessageRenderer(
    "intercom_message",
    createRenderer(InlineMessageComponent),
  );
}
