/**
 * One wake per idle session, shared by every extension that wakes Pi.
 *
 * Pi marks a run active only after a prompt's async preflight, so a second wake
 * sent in that gap makes `agent.prompt()` throw "Agent is already processing".
 * Extensions therefore agree, through one `globalThis` entry, that a wake is in
 * flight for a session: whoever wakes first reserves it, `agent_start` releases
 * it, and any other extension that finds it held appends its message without
 * starting a run of its own.
 *
 * The symbol and the `{ sessionId, sentAt }` shape are a cross-extension
 * contract with pi-intercom and pi-subagents, which keep their own copy of this
 * file; change the key and the shape in all of them or not at all.
 */

/** The part of Pi's session manager this contract needs. */
export interface WakeSession {
  getSessionId(): string;
}

/** One session's wake, held until a run starts or the reservation expires. */
interface WakeReservation {
  sessionId: string;
  sentAt?: number;
}

/**
 * How long a reservation blocks other wakes.
 *
 * Pi emits no `agent_start` for a preflight that was handled by an extension or
 * that failed, so the reservation has to expire rather than latch.
 */
const WAKE_PENDING_MS = 10_000;

const RESERVATIONS_KEY = Symbol.for("pi.idle-wake.v1");

/** How often a held wake re-checks whether the session is free. */
const WAKE_RETRY_MS = 250;

/** `globalThis` seen through the shared key. */
type WakeGlobal = typeof globalThis &
  Record<symbol, WeakMap<object, WakeReservation> | undefined>;

const wakeGlobal = globalThis as WakeGlobal;
const reservations: WeakMap<object, WakeReservation> =
  wakeGlobal[RESERVATIONS_KEY] ?? new WeakMap<object, WakeReservation>();
wakeGlobal[RESERVATIONS_KEY] = reservations;

/**
 * The reservation of one session, replaced when the session changes under a
 * reused manager object.
 *
 * @param session - Session manager shared with the other extensions.
 * @returns Its reservation record.
 */
function reservationFor(session: WakeSession): WakeReservation {
  const sessionId = session.getSessionId();
  const current = reservations.get(session);
  if (current?.sessionId === sessionId) return current;
  const next: WakeReservation = { sessionId };
  reservations.set(session, next);
  return next;
}

/**
 * Whether another wake is already in flight for this session.
 *
 * @param session - Session manager shared with the other extensions.
 * @returns True while a wake is pending, false once it started a run or aged out.
 */
export function isIdleWakePending(session: WakeSession): boolean {
  const { sentAt } = reservationFor(session);
  return sentAt !== undefined && Date.now() - sentAt < WAKE_PENDING_MS;
}

/**
 * Claim the next wake for this session.
 *
 * @param session - Session manager shared with the other extensions.
 */
export function reserveIdleWake(session: WakeSession): void {
  reservationFor(session).sentAt = Date.now();
}

/**
 * Release this session after a run started.
 *
 * @param session - Session manager shared with the other extensions.
 */
export function releaseIdleWake(session: WakeSession): void {
  reservationFor(session).sentAt = undefined;
}

/**
 * Send a wake, waiting out another extension's wake instead of racing it.
 *
 * A message appended without `triggerTurn` starts no run, so it can sit
 * unread forever when the wake that held the reservation never did start one.
 * This therefore never downgrades: it claims the session and sends when nothing
 * is in flight, and otherwise re-checks until the reservation clears, so the
 * message is always delivered exactly once.
 *
 * `send` may run later than this call and must stay valid until it does.
 *
 * @param session - Session manager shared with the other extensions.
 * @param send - Sends the message with `triggerTurn` set.
 */
export function deliverWake(session: WakeSession, send: () => void): void {
  if (!isIdleWakePending(session)) {
    reserveIdleWake(session);
    send();
    return;
  }
  // Unref'd: a held wake must not be the reason the process stays alive.
  setTimeout(() => deliverWake(session, send), WAKE_RETRY_MS).unref();
}
