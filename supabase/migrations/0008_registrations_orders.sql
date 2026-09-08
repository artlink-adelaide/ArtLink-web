-- 0008: event_registrations + orders + the state-machine functions
-- register_for_event / settle_order / cancel_registration.
--
-- Money-adjacent state transitions go through SECURITY DEFINER
-- functions ONLY: the tables have no write policies at all, so no
-- client can insert or update a registration or order directly
-- (BUILD_PLAN scenario 17). Reads: your own; event collaborators see
-- their events' registrations.

create table public.event_registrations (
  id uuid primary key default gen_random_uuid (),
  event_id uuid not null references public.events (id) on delete cascade,
  member_id uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'confirmed', 'payment_failed', 'cancelled')),
  created_at timestamptz not null default now (),
  updated_at timestamptz not null default now (),
  unique (event_id, member_id)
);

create table public.orders (
  id uuid primary key default gen_random_uuid (),
  registration_id uuid not null references public.event_registrations (id) on delete cascade,
  member_id uuid not null references public.profiles (id) on delete cascade,
  amount_cents integer not null check (amount_cents >= 0),
  status text not null default 'pending'
    check (status in ('pending', 'succeeded', 'failed')),
  gateway text not null default 'stub',
  created_at timestamptz not null default now (),
  updated_at timestamptz not null default now ()
);

create index event_registrations_event_idx on public.event_registrations (event_id);
create index event_registrations_member_idx on public.event_registrations (member_id);
create index orders_registration_idx on public.orders (registration_id);
create index orders_member_idx on public.orders (member_id);

alter table public.event_registrations enable row level security;
alter table public.orders enable row level security;

create policy "own registrations visible, plus event team"
  on public.event_registrations for select
  to authenticated
  using (
    member_id = auth.uid ()
    or public.is_event_collaborator (event_id, auth.uid ())
  );

create policy "own orders visible, plus event team"
  on public.orders for select
  to authenticated
  using (
    member_id = auth.uid ()
    or public.is_event_collaborator (
      (select r.event_id from public.event_registrations r where r.id = registration_id),
      auth.uid ()
    )
  );

-- Intentionally NO insert/update/delete policies on either table.

create trigger trg_event_registrations_touch_updated_at
  before update on public.event_registrations
  for each row execute function public.touch_updated_at ();

create trigger trg_orders_touch_updated_at
  before update on public.orders
  for each row execute function public.touch_updated_at ();

-- ---------------- stub gateway switch ----------------
-- Local/CI fake-gateway control for settle_order. No policies: only
-- the definer functions read it; tests flip it via definer RPC.
create table public.payment_stub_settings (
  id boolean primary key default true check (id),
  force_fail boolean not null default false
);

alter table public.payment_stub_settings enable row level security;
-- Intentionally NO policies: only the SECURITY DEFINER functions touch
-- this table; clients can neither read nor write the gateway switch.
insert into public.payment_stub_settings (id, force_fail) values (true, false);

create function public.set_payment_stub_force_fail (p_force_fail boolean)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.payment_stub_settings set force_fail = p_force_fail where id = true;
$$;

grant execute on function public.set_payment_stub_force_fail (boolean) to authenticated;

-- ---------------- functions ----------------

-- Register the caller for a published event.
--   free  event -> registration confirmed immediately
--   paid  event -> registration pending + a pending order; settle_order
--                  moves it to confirmed or payment_failed
-- Re-registering while pending/payment_failed issues a NEW order
-- against the SAME registration (retry), per scenario 14.
create function public.register_for_event (p_event_id uuid)
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

  select * into v_event
  from public.events e
  where e.id = p_event_id and e.status = 'published';
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
    values (v_registration.id, v_member, v_event.price_cents, 'pending');
  end if;

  return v_registration.id;
end;
$$;

-- Settle a pending order through the stub gateway.
--   second settle of a settled order -> no-op, returns current status
--   settling someone else's order   -> rejected (not found for you)
create function public.settle_order (p_order_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member uuid := auth.uid ();
  v_order public.orders;
  v_force_fail boolean;
begin
  if v_member is null then
    raise exception 'AUTH_REQUIRED: sign in to settle orders';
  end if;

  select * into v_order
  from public.orders o
  where o.id = p_order_id and o.member_id = v_member;
  if not found then
    raise exception 'ORDER_NOT_FOUND_OR_NOT_YOURS';
  end if;

  if v_order.status <> 'pending' then
    return v_order.status;  -- idempotent no-op (scenario 15)
  end if;

  select force_fail into v_force_fail
  from public.payment_stub_settings where id = true;

  if v_force_fail then
    update public.orders set status = 'failed' where id = v_order.id;
    update public.event_registrations
    set status = 'payment_failed'
    where id = v_order.registration_id and status in ('pending', 'payment_failed');
    return 'failed';
  end if;

  update public.orders set status = 'succeeded' where id = v_order.id;
  update public.event_registrations
  set status = 'confirmed'
  where id = v_order.registration_id and status in ('pending', 'payment_failed');
  return 'succeeded';
end;
$$;

create function public.cancel_registration (p_registration_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member uuid := auth.uid ();
begin
  if v_member is null then
    raise exception 'AUTH_REQUIRED: sign in to cancel registrations';
  end if;

  update public.event_registrations
  set status = 'cancelled'
  where id = p_registration_id and member_id = v_member;
  if not found then
    raise exception 'REGISTRATION_NOT_FOUND_OR_NOT_YOURS';
  end if;
end;
$$;

grant execute on function
  public.register_for_event (uuid),
  public.settle_order (uuid),
  public.cancel_registration (uuid)
to authenticated;
