-- 0005: events + event_collaborators + the trigger guaranteeing an event
-- always has at least one collaborator: its creator.
create table public.events (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references public.profiles (id) on delete cascade,
  category_id smallint references public.categories (id),
  title text not null,
  description text,
  status public.event_status not null default 'draft',
  starts_at timestamptz not null,
  ends_at timestamptz,
  price_cents integer not null default 0 check (price_cents >= 0),
  capacity integer check (capacity is null or capacity > 0),
  cover_path text,
  search_vector tsvector,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.event_collaborators (
  event_id uuid not null references public.events (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  role text not null default 'collaborator',
  added_at timestamptz not null default now(),
  primary key (event_id, profile_id)
);

create index events_host_idx on public.events (host_id);
create index events_category_idx on public.events (category_id);
create index events_status_starts_idx on public.events (status, starts_at);
create index events_search_vector_idx on public.events using gin (search_vector);
create index event_collaborators_profile_idx on public.event_collaborators (profile_id);

create trigger trg_events_touch_updated_at
  before update on public.events
  for each row execute function public.touch_updated_at ();

-- SECURITY DEFINER so the invariant holds regardless of who inserts and,
-- later, of the RLS policies on event_collaborators (0007).
create function public.events_add_host_collaborator () returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.event_collaborators (event_id, profile_id, role)
  values (new.id, new.host_id, 'host')
  on conflict do nothing;
  return new;
end;
$$;

create trigger trg_events_add_host_collaborator
  after insert on public.events
  for each row execute function public.events_add_host_collaborator ();
