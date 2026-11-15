/**
 * Tests for the cross-extension wake contract.
 *
 * Pi marks a run active only after a prompt's async preflight, so two wakes in
 * that gap make the second throw. The contract with pi-intercom and
 * pi-subagents is a `globalThis` WeakMap under one symbol, holding
 * `{ sessionId, sentAt }`; a reservation blocks other wakes until a run starts
 * or it ages out. These tests pin the key, the shape and the expiry, which is
 * what a second implementation has to agree on.
 */

import assert from "node:assert/strict";
import { describe, test } from "node:test";
import {
  isIdleWakePending,
  releaseIdleWake,
  reserveIdleWake,
} from "../../extensions/utils/idle-wake.ts";

/** A stand-in for Pi's session manager, which is only asked for its id. */
const sessionOf = (id = "session-1") => ({ getSessionId: () => id });

describe("idle wake contract", () => {
  test("reserving makes the session pending and releasing clears it", () => {
    const session = sessionOf();
    assert.equal(isIdleWakePending(session), false);
    reserveIdleWake(session);
    assert.equal(isIdleWakePending(session), true);
    releaseIdleWake(session);
    assert.equal(isIdleWakePending(session), false);
  });

  test("a reservation is visible to a second extension through the shared key", () => {
    const session = sessionOf("shared");
    reserveIdleWake(session);

    // Another extension's copy of the contract reads the same global entry.
    const shared = globalThis[Symbol.for("pi.idle-wake.v1")];
    assert.ok(shared instanceof WeakMap);
    const reservation = shared.get(session);
    assert.equal(reservation.sessionId, "shared");
    assert.equal(typeof reservation.sentAt, "number");

    // And a reservation written by that other extension blocks this one.
    shared.set(session, { sessionId: "shared", sentAt: Date.now() });
    assert.equal(isIdleWakePending(session), true);
  });

  test("an abandoned reservation expires instead of latching", (t) => {
    const session = sessionOf();
    reserveIdleWake(session);
    const now = Date.now();
    // Pi emits no agent_start for a preflight it handled or that failed.
    t.mock.method(Date, "now", () => now + 10_001);
    assert.equal(isIdleWakePending(session), false);
  });

  test("a session replaced under the same manager starts unpending", () => {
    let id = "before";
    const session = { getSessionId: () => id };
    reserveIdleWake(session);
    assert.equal(isIdleWakePending(session), true);
    id = "after";
    assert.equal(isIdleWakePending(session), false);
  });
});
