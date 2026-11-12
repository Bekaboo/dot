/**
 * Recover from providers that fail a whole turn on malformed tool-call JSON,
 * aiming for autonomous long-horizon tasks.
 *
 * qoder reports such a turn as `stopReason: "error"` with `errorMessage:
 * "Invalid or incomplete tool-call JSON (characters=N)"`. Pi treats an error turn
 * as a hard exit and schedules no retry, because the text matches no transient
 * provider pattern, so the run stays stopped until the user types "Continue".
 *
 * The failure is stochastic -- a single very large `edit` payload tends to lose
 * its tail -- so one more attempt usually succeeds once the model splits the
 * payload. This extension rewrites the failed turn as a completed one, drops the
 * unusable tool calls (they have no results and would make the next request
 * invalid), and asks for smaller calls. The chain is capped so a model that
 * always emits broken JSON still ends the run.
 */

import type { AssistantMessage } from "@earendil-works/pi-ai";
import type {
  ExtensionAPI,
  MessageEndEvent,
  MessageEndEventResult,
  TurnEndEvent,
  TurnEndEventResult,
} from "@earendil-works/pi-coding-agent";

/** Custom message type that carries the retry instruction. */
const CUSTOM_TYPE = "toolcall-fail-recovery";

/** Failed turns in a row that may be re-issued before the run ends. */
const MAX_CONSECUTIVE_RECOVERIES = 2;

/**
 * Tool-call JSON failures Pi's retry classifier treats as permanent. A dropped
 * argument stream arrives as "Qoder server error: ...", which Pi retries itself.
 */
const MALFORMED_TOOL_CALL_JSON =
  /invalid or incomplete tool-call json|non-object tool-call arguments/i;

/** Recovery budget plus the failed turns still owed a retry instruction. */
class RecoveryChain {
  /** Failed turns recovered since the last healthy response. */
  private chain = 0;

  /** Messages this extension rewrote, awaiting their `turn_end`. */
  private recovered = new WeakSet<object>();

  /**
   * Rewrite a claimable tool-call JSON failure as a completed turn, so the run
   * continues instead of exiting.
   *
   * @param event - Assistant message that just ended.
   * @returns The replacement message, or undefined to leave the turn alone.
   */
  rewriteFailedTurn(event: MessageEndEvent): MessageEndEventResult | undefined {
    const message = event.message;
    if (message.role !== "assistant") return;
    if (message.stopReason !== "error") {
      this.chain = 0;
      return;
    }
    const errorMessage = message.errorMessage;
    if (!errorMessage || !MALFORMED_TOOL_CALL_JSON.test(errorMessage)) return;
    if (this.chain >= MAX_CONSECUTIVE_RECOVERIES) return;

    this.chain++;
    this.recovered.add(message);
    return { message: neutralize(message, errorMessage) };
  }

  /**
   * Append the retry instruction for a turn this chain rewrote.
   *
   * @param event - Ended turn, with the drafts proposed so far.
   * @returns The appended draft and continuation, or undefined to end the run.
   */
  continueTurn(event: TurnEndEvent): TurnEndEventResult | undefined {
    const message = event.message;
    if (message.role !== "assistant" || !this.recovered.has(message)) return;
    const errorMessage = message.errorMessage;
    if (!errorMessage) return;

    this.recovered.delete(message);
    return {
      entries: [
        ...event.entries,
        {
          type: "custom_message",
          customType: CUSTOM_TYPE,
          content: retryInstruction(errorMessage),
          display: false,
        },
      ],
      continue: true,
    };
  }
}

/**
 * Rewrite the failed response as a completed turn: a note for the user, and no
 * tool calls, since a call without a result would fail the next request. The
 * provider error stays on the message for the retry instruction.
 *
 * @param message - Failed assistant message.
 * @param errorMessage - Provider error that failed the turn.
 * @returns The message to persist in its place.
 */
function neutralize(
  message: AssistantMessage,
  errorMessage: string,
): AssistantMessage {
  const dropped = message.content.flatMap((block) =>
    block.type === "toolCall" ? [block.name] : [],
  );
  const note =
    `No tool ran: the provider rejected this response because its tool-call JSON ` +
    `did not parse (${errorMessage}).` +
    (dropped.length > 0 ? ` Dropped tool call(s): ${dropped.join(", ")}.` : "") +
    " Re-issuing the request in smaller steps.";
  return {
    ...message,
    stopReason: "stop",
    content: [{ type: "text", text: note }],
  };
}

/**
 * Hidden user-role message that asks for the work to be re-issued without
 * repeating the oversized payload.
 *
 * @param errorMessage - Provider error that failed the previous turn.
 * @returns The content of the retry instruction.
 */
function retryInstruction(errorMessage: string): string {
  return (
    "Your previous response was discarded before any tool ran: the provider " +
    `could not parse its tool-call arguments as JSON (${errorMessage}). ` +
    "Nothing from that response took effect. Re-issue the work now, and split " +
    "large payloads into several smaller `edit` or `write` calls with complete " +
    "arguments."
  );
}

/**
 * Register the extension with Pi.
 *
 * @param pi - Extension API used to hook the session lifecycle.
 */
export default function toolcallFailRecovery(pi: ExtensionAPI): void {
  const recovery = new RecoveryChain();

  pi.on("message_end", (event) => recovery.rewriteFailedTurn(event));
  pi.on("turn_end", (event) => recovery.continueTurn(event));
}
