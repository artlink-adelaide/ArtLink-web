import { expect, test } from "vitest";
import { createUser } from "../access/_harness";
import { createPricedEvent, orderCount } from "./_fixtures";

/**
 * Defect 3 (9 September): every call to register_for_event inserted a new
 * pending order against the same registration, so three calls left three
 * separately settleable orders for one seat. Build Spec scenario 16 requires
 * exactly one ledger entry per reserved seat.
 *
 * A 'failed' order must still not block a retry — that path is covered by
 * the partial index predicate in 0011 being 'pending' only.
 */
test("repeat registration reuses the registration and issues one order", async () => {
  const host = await createUser("repeat-host");
  const member = await createUser("repeat-member");
  const eventId = await createPricedEvent(host, "Repeat Paid Show", 2500);

  const first = await member.client.rpc("register_for_event", { p_event_id: eventId });
  const second = await member.client.rpc("register_for_event", { p_event_id: eventId });
  const third = await member.client.rpc("register_for_event", { p_event_id: eventId });

  expect(first.error).toBeNull();
  expect(second.data).toBe(first.data);
  expect(third.data).toBe(first.data);
  expect(await orderCount(eventId, member.userId)).toBe(1);
});

test("a failed order does not block a fresh attempt", async () => {
  const host = await createUser("retry-host");
  const member = await createUser("retry-member");
  const eventId = await createPricedEvent(host, "Retry Paid Show", 1500);

  await member.client.rpc("register_for_event", { p_event_id: eventId });
  const a = await (await import("../access/_harness")).admin();
  await a.query(`update public.orders set status = 'failed' where member_id = $1`, [member.userId]);

  await member.client.rpc("register_for_event", { p_event_id: eventId });
  expect(await orderCount(eventId, member.userId)).toBe(2);
});
