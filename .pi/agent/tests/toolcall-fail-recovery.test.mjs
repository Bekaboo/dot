/**
 * Tests for the toolcall-fail-recovery extension.
 *
 * A provider that cannot parse its own tool-call JSON reports the turn as
 * `stopReason: "error"`, which Pi treats as a hard exit. The extension turns that
 * into a completed turn plus one more request, so these tests drive a real
 * `AgentSession` with a scripted faux model: only the real loop shows whether the
 * run continues or stops. Pinned contract: the failed turn is neutralized (no
 * dangling tool call, no error stop), exactly one request follows carrying the
 * retry instruction, the chain is bounded, a healthy response resets it, and
 * errors Pi retries on its own are left alone.
 */

import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import test from "node:test";

import { fauxAssistantMessage, fauxProvider, fauxToolCall } from "@earendil-works/pi-ai";
import {
  createAgentSession,
  DefaultResourceLoader,
  ModelRuntime,
  SessionManager,
  SettingsManager,
} from "@earendil-works/pi-coding-agent";

import toolcallFailRecovery from "../extensions/toolcall-fail-recovery.ts";

/** Provider text that fails a turn without being retryable by Pi. */
const MALFORMED_JSON = "Invalid or incomplete tool-call JSON (characters=4149)";

/** Deterministic model: every response is scripted per test. */
const faux = fauxProvider({ provider: "faux", models: [{ id: "faux-1" }] });
const modelRuntime = await ModelRuntime.create({
  modelsPath: null,
  refreshOnCreate: false,
  allowModelNetwork: false,
});
modelRuntime.registerNativeProvider(faux.provider);

/** A failed turn carrying one tool call whose arguments never parsed. */
function failedTurn(errorMessage) {
  return fauxAssistantMessage([fauxToolCall("bash", {})], {
    stopReason: "error",
    errorMessage,
  });
}

/**
 * Create a session with the extension installed, plus recorders for what the
 * model saw and what got persisted.
 *
 * @param t - Node test context, used for cleanup.
 */
async function createSession(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "pi-toolcall-fail-"));
  const resourceLoader = new DefaultResourceLoader({
    cwd: dir,
    agentDir: dir,
    noExtensions: true,
    noSkills: true,
    noPromptTemplates: true,
    noThemes: true,
    noContextFiles: true,
    systemPrompt: "You are a test assistant.",
    extensionFactories: [toolcallFailRecovery],
  });
  await resourceLoader.reload();
  const { session } = await createAgentSession({
    cwd: dir,
    agentDir: dir,
    modelRuntime,
    model: faux.getModel(),
    thinkingLevel: "off",
    resourceLoader,
    sessionManager: SessionManager.inMemory(),
    settingsManager: SettingsManager.inMemory({
      compaction: { enabled: false },
      retry: { enabled: false },
    }),
    noTools: "all",
    tools: [],
  });
  t.after(() => {
    session.dispose();
    fs.rmSync(dir, { recursive: true, force: true });
  });

  const requests = [];
  const assistantMessages = [];
  session.subscribe((event) => {
    if (event.type === "message_end" && event.message.role === "assistant") {
      assistantMessages.push(structuredClone(event.message));
    }
  });
  return { session, requests, assistantMessages };
}

/**
 * Script one response per request and record the context each request carried.
 *
 * @param responses - Responses or factories, one per request.
 * @param requests - Array that receives each request context.
 */
function scripted(responses, requests) {
  return responses.map(
    (response) =>
      (context) => {
        requests.push(context);
        return typeof response === "function" ? response() : response;
      },
  );
}

/** Concatenated text of one assistant message. */
function assistantText(message) {
  return message.content
    .filter((block) => block.type === "text")
    .map((block) => block.text)
    .join("\n");
}

test("re-asks once instead of ending the run", async (t) => {
  const { session, requests, assistantMessages } = await createSession(t);
  faux.setResponses(
    scripted([failedTurn(MALFORMED_JSON), fauxAssistantMessage("done")], requests),
  );

  await session.prompt("edit the file");

  assert.equal(requests.length, 2, "the run made one retry request");

  const failed = assistantMessages[0];
  assert.equal(failed.stopReason, "stop", "the failed turn is no longer an error");
  assert.equal(
    failed.errorMessage,
    MALFORMED_JSON,
    "the provider error is kept for the retry instruction",
  );
  assert.deepEqual(
    failed.content.map((block) => block.type),
    ["text"],
    "the unusable tool call is dropped",
  );
  assert.match(assistantText(failed), /No tool ran/);

  const retry = requests[1].messages;
  const instruction = retry.at(-1);
  assert.equal(instruction.role, "user");
  assert.match(instruction.content[0].text, /split large payloads/);
  assert.match(instruction.content[0].text, /Invalid or incomplete tool-call JSON/);

  const toolCalls = retry.flatMap((message) =>
    Array.isArray(message.content)
      ? message.content.filter((block) => block.type === "toolCall")
      : [],
  );
  assert.equal(toolCalls.length, 0, "no tool call is left without a result");

  assert.equal(assistantMessages.at(-1).stopReason, "stop");
  assert.equal(assistantText(assistantMessages.at(-1)), "done");
});

test("stops recovering after the chain budget", async (t) => {
  const { session, requests, assistantMessages } = await createSession(t);
  faux.setResponses(
    scripted(
      [
        failedTurn(MALFORMED_JSON),
        failedTurn(MALFORMED_JSON),
        failedTurn(MALFORMED_JSON),
      ],
      requests,
    ),
  );

  await session.prompt("keep trying");

  assert.equal(requests.length, 3, "one initial request plus two recoveries");
  assert.equal(assistantMessages.at(-1).stopReason, "error");
  assert.equal(assistantMessages.at(-1).errorMessage, MALFORMED_JSON);
});

test("leaves a permanent error alone", async (t) => {
  const { session, requests, assistantMessages } = await createSession(t);
  faux.setResponses(
    scripted([failedTurn("429 insufficient_quota: out of budget")], requests),
  );

  await session.prompt("run");

  assert.equal(requests.length, 1, "no retry is invented for a quota error");
  assert.equal(assistantMessages.at(-1).stopReason, "error");
});

test("a healthy response resets the chain", async (t) => {
  const { session, requests, assistantMessages } = await createSession(t);
  faux.setResponses(
    scripted(
      [
        failedTurn(MALFORMED_JSON),
        fauxAssistantMessage("first"),
        failedTurn(MALFORMED_JSON),
        fauxAssistantMessage("second"),
        failedTurn(MALFORMED_JSON),
        fauxAssistantMessage("third"),
      ],
      requests,
    ),
  );

  await session.prompt("one");
  await session.prompt("two");
  await session.prompt("three");

  assert.equal(requests.length, 6, "each run recovered once");
  assert.equal(assistantMessages.at(-1).stopReason, "stop");
  assert.equal(assistantText(assistantMessages.at(-1)), "third");
});
