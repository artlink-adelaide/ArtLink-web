-- 0011: payment-path integrity. Fixes the three defects found against 0008
-- on 9 September 2026.
--
-- Written as a forward migration rather than an edit to 0008: that file is
-- already applied on teammates' local stacks and carried by the closed
-- feat/data-layer and feat/auth-accounts branches, so rewriting it in place
-- would leave those databases silently diverged.
--
-- Build Spec §scenarios 15 and 16 govern two of the three:
--   15 — 10 concurrent threads for 5 seats must yield exactly 5 registrations
--   16 — duplicate delivery must reserve exactly 1 seat and write 1 ledger entry
-- (0008's own comments cite a "BUILD_PLAN scenario 14/17" numbering that
-- matches no document in the repository; the Build Spec is used instead.)

-- ---------------- 1. the gateway kill switch is not a client control ----------------
-- 0008 granted EXECUTE to authenticated but never revoked the implicit grant
-- PostgreSQL gives every function in a schema the client roles can use, so
-- anon could call it too: an unauthenticated visitor could disable payments
-- for every user. It is a local/CI test affordance and belongs to
-- service_role alone.
revoke execute on function public.set_payment_stub_force_fail (boolean) from public;
revoke execute on function public.set_payment_stub_force_fail (boolean) from anon;
revoke execute on function public.set_payment_stub_force_fail (boolean) from authenticated;
grant execute on function public.set_payment_stub_force_fail (boolean) to service_role;

-- ---------------- 3. at most one settleable order per registration ----------------
-- Hard backstop for the guard added to register_for_event below. A 'failed'
-- order never blocks a retry, so the partial predicate is exactly 'pending'.
create unique index orders_one_open_order_per_registration
  on public.orders (registration_id)
  where status = 'pending';

-- ---------------- 2 + 3. register_for_event ----------------
-- Changes against 0008:
--   * the event row is taken FOR UPDATE, so the capacity count and the
--     registration insert cannot interleave with a concurrent caller
--   * an order is issued only when the registration has no open order,
--     preserving retry-after-failure while making repeat calls idempotent
create or replace function public.register_for_event (p_event_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member uuid := auth.uid ();
  v_event public.events;
  v_registration public.event_registrations;
  v_confirmed int;
begin
  if v_member is null then
    raise exception 'AUTH_REQUIRED: sign in to register for events';
  end if;

  -- FOR UPDATE serialises registrations for this event: concurrent callers
  -- queue here, so each one's capacity count sees every earlier insert.
  select * into v_event
  from public.events e
  where e.id = p_event_id and e.status = 'published'
  for update;
  if not found then
    raise exception 'EVENT_NOT_FOUND_OR_NOT_PUBLISHED';
  end if;

  select * into v_registration
  from public.event_registrations r
  where r.event_id = p_event_id and r.member_id = v_member;

  if not found then
    if v_event.capacity is not null then
      select count(*) into v_confirmed
      from public.event_registrations r
      where r.event_id = p_event_id and r.status in ('pending', 'confirmed', 'payment_failed');
      if v_confirmed >= v_event.capacity then
        raise exception 'EVENT_FULL';
      end if;
    end if;

    insert into public.event_registrations (event_id, member_id, status)
    values (
      p_event_id,
      v_member,
      case when v_event.price_cents > 0 then 'pending' else 'confirmed' end
    )
    returning * into v_registration;
  elsif v_registration.status = 'cancelled' then
    update public.event_registrations
    set status = case when v_event.price_cents > 0 then 'pending' else 'confirmed' end
    where id = v_registration.id
    returning * into v_registration;
  end if;

  if v_event.price_cents > 0 and v_registration.status in ('pending', 'payment_failed') then
    insert into public.orders (registration_id, member_id, amount_cents, status)
    values (v_registration.id, v_member, v_event.price_cents, 'pending')
    on conflict (registration_id) where status = 'pending' do nothing;
  end if;

  return v_registration.id;
end;
$$;
