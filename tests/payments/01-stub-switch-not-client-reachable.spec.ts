import { afterAll, expect, test } from "vitest";
import { anonClient, applyRedGuard, createUser, guard } from "../access/_harness";
import { forceFailFlag } from "./_fixtures";

/**
 * Defect 1 (9 September): set_payment_stub_force_fail carried the implicit
 * PUBLIC execute grant, so any visitor — signed in or not — could disable
 * payments for the whole platform. 0011 revokes it down to service_role.
 *
 * Asserted by DATA STATE, per the harness ground rules: the switch must
 * still read false afterwards, whatever the RPC returned.
 */
guard(
  "stub-switch-granted-to-clients",
  `grant execute on function public.set_payment_stub_force_fail (boolean) to anon, authenticated;`,
  `revoke execute on function public.set_payment_stub_force_fail (boolean) from anon, authenticated;`,
);

const restore = await applyRedGuard();
afterAll(async () => {
  const a = await (await import("../access/_harness")).admin();
  await a.query(`update public.payment_stub_settings set force_fail = false where id`);
  if (restore) await restore();
});

test("an anonymous visitor cannot disable payments", async () => {
  const anon = anonClient();
  await anon.rpc("set_payment_stub_force_fail", { p_force_fail: true });
  expect(await forceFailFlag()).toBe(false);
});

test("a signed-in member cannot disable payments", async () => {
  const member = await createUser("stub-member");
  await member.client.rpc("set_payment_stub_force_fail", { p_force_fail: true });
  expect(await forceFailFlag()).toBe(false);
});
