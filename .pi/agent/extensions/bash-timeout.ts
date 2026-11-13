/**
 * Default timeout for the built-in `bash` tool.
 *
 * Pi's `bash` tool accepts an optional `timeout` (seconds) but applies none by
 * default, so a hung command can easily blocks the agent.
 *
 * This extension fills in `DEFAULT_TIMEOUT_SEC` whenever the model omits
 * `timeout`; an explicit `timeout` in the call still wins.
 */

import {
  type ExtensionAPI,
  isToolCallEventType,
} from "@earendil-works/pi-coding-agent";

/** Default `bash` timeout, in seconds, when the model names none. */
export const DEFAULT_TIMEOUT_SEC = 120;

const TIMEOUT_GUIDLINE =
  `bash commands without \`timeout\` are killed after ${DEFAULT_TIMEOUT_SEC} seconds. ` +
  "Pass a larger `timeout` for commands expected to run longer; remember that " +
  "a longer timeout can block the agent loop unnecessarily.";

export default function (pi: ExtensionAPI) {
  // The bash schema says "no default timeout"; tell the model the new contract.
  pi.on("before_agent_start", (event) => {
    const { toolGuidelines } = event.systemPromptOptions;
    const guidelines = toolGuidelines.bash ?? [];
    toolGuidelines.bash = guidelines;
    if (!guidelines.includes(TIMEOUT_GUIDLINE)) {
      guidelines.push(TIMEOUT_GUIDLINE);
    }
  });

  pi.on("tool_call", (event) => {
    if (!isToolCallEventType("bash", event)) return;
    event.input.timeout ??= DEFAULT_TIMEOUT_SEC;
  });
}
