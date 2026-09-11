import { admin, type TestUser } from "../access/_harness";

/**
 * Payment-path fixtures. The access harness's createEvent() goes through
 * an authenticated client and does not carry price or capacity, so these
 * insert directly on the admin connection: the subject under test is the
 * definer RPC, not the event-insert policy.
 */
export async function createPricedEvent(
  host: TestUser,
  title: string,
  priceCents: number,
  capacity: number | null = null,
): Promise<string> {
  const a = await admin();
  const { rows } = await a.query(
    `insert into public.events (host_id, title, status, starts_at, price_cents, capacity)
     values ($1, $2, 'published', now() + interval '7 days', $3, $4)
     returning id`,
    [host.userId, title, priceCents, capacity],
  );
  return rows[0].id as string;
}

/** Counts orders belonging to one member for one event. */
export async function orderCount(eventId: string, memberId: string): Promise<number> {
  const a = await admin();
  const { rows } = await a.query(
    `select count(*)::int as n
       from public.orders o
       join public.event_registrations r on r.id = o.registration_id
      where r.event_id = $1 and r.member_id = $2`,
    [eventId, memberId],
  );
  return rows[0].n as number;
}

export async function registrationCount(eventId: string): Promise<number> {
  const a = await admin();
  const { rows } = await a.query(
    `select count(*)::int as n from public.event_registrations where event_id = $1`,
    [eventId],
  );
  return rows[0].n as number;
}

export async function forceFailFlag(): Promise<boolean> {
  const a = await admin();
  const { rows } = await a.query(`select force_fail from public.payment_stub_settings where id`);
  return rows[0].force_fail as boolean;
}
