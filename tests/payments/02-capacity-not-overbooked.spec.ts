import { afterAll, expect, test } from "vitest";
import pg from "pg";
import { createUser, stackConfig } from "../access/_harness";
import { createPricedEvent, registrationCount } from "./_fixtures";

/**
 * Defect 2 (9 September): register_for_event counted confirmed registrations
 * and then inserted, holding no lock on the event in between, so two callers
 * could both read "0 of 1 taken" and both take the seat.
 *
 * Build Spec scenario 15: "10 concurrent threads register for 5 available
 * event seats -> exactly 5 registrations". 0011 takes the event row FOR
 * UPDATE, serialising the count-then-insert per event.
 *
 * Fanning N requests out over HTTP does NOT test this: PostgREST and the JS
 * event loop serialise them enough that the unfixed function still passes.
 * (Confirmed — an earlier Promise.all version of this file went green against
 * a build with the lock removed.) So the race is forced deterministically:
 * transaction A registers and holds its lock open while transaction B tries
 * the same seat. Under the fix B must BLOCK; without it B sails through.
 */
const LOCK_WAIT_MS = 1500;

const clients: pg.Client[] = [];
async function conn(): Promise<pg.Client> {
  const c = new pg.Client({ connectionString: stackConfig().dbUrl });
  await c.connect();
  clients.push(c);
  return c;
}
afterAll(async () => {
  await Promise.all(clients.map((c) => c.end().catch(() => {})));
});

/** Runs register_for_event inside an open transaction as the given member. */
async function registerInTxn(c: pg.Client, memberId: string, eventId: string): Promise<void> {
  await c.query("begin");
  await c.query(`select set_config('request.jwt.claims', $1, true)`, [
    JSON.stringify({ sub: memberId, role: "authenticated" }),
  ]);
  await c.query("set local role authenticated");
  await c.query(`select public.register_for_event($1)`, [eventId]);
}

test("a second caller cannot take the last seat while the first holds it", async () => {
  const host = await createUser("cap-host");
  const first = await createUser("cap-first");
  const second = await createUser("cap-second");
  const eventId = await createPricedEvent(host, "Single Seat", 0, 1);

  const a = await conn();
  const b = await conn();

  // A takes the only seat and deliberately does not commit yet.
  await registerInTxn(a, first.userId, eventId);

  // B must queue behind A's row lock. Bounded so a missing lock is a failure,
  // not a hang.
  await b.query("begin");
  await b.query(`select set_config('request.jwt.claims', $1, true)`, [
    JSON.stringify({ sub: second.userId, role: "authenticated" }),
  ]);
  await b.query("set local role authenticated");
  await b.query(`set local statement_timeout = ${LOCK_WAIT_MS}`);

  let blocked = false;
  try {
    await b.query(`select public.register_for_event($1)`, [eventId]);
  } catch (err) {
    // 57014 = query_canceled: B waited on A's lock until the timeout.
    blocked = (err as { code?: string }).code === "57014";
    if (!blocked) throw err;
  }
  await b.query("rollback").catch(() => {});
  await a.query("commit");

  expect(blocked).toBe(true);
  expect(await registrationCount(eventId)).toBe(1);
});

test("the seat count is still right once the blocked caller retries", async () => {
  const host = await createUser("cap2-host");
  const first = await createUser("cap2-first");
  const second = await createUser("cap2-second");
  const eventId = await createPricedEvent(host, "Single Seat Retry", 0, 1);

  const a = await conn();
  await registerInTxn(a, first.userId, eventId);
  await a.query("commit");

  const { error } = await second.client.rpc("register_for_event", { p_event_id: eventId });
  expect(error?.message).toContain("EVENT_FULL");
  expect(await registrationCount(eventId)).toBe(1);
});
