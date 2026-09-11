-- 0007: ALL row-level-security policies for the tables that exist at
-- this point in the sequence (categories..page_views), plus the four
-- storage buckets and their storage.objects policies.
--
-- Migrations 0008/0009 create further tables (event_registrations,
-- orders, interactions); each of those migrations enables RLS on its
-- own tables inline, because 0007 cannot reference tables that do not
-- exist yet. The CI invariant (check-invariants.mjs) verifies that
-- every public table ends up with RLS enabled regardless.
--
-- Circular-policy avoidance: events <-> event_collaborators would
-- recurse if their policies queried each other directly. All
-- collaborator/host predicates go through SECURITY DEFINER helpers,
-- which bypass RLS and terminate the recursion.

create function public.is_event_collaborator (p_event uuid, p_member uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.event_collaborators ec
    where ec.event_id = p_event and ec.profile_id = p_member
  );
$$;

create function public.is_event_host (p_event uuid, p_member uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.events e
    where e.id = p_event and e.host_id = p_member
  );
$$;

-- ---------------- tables ----------------

alter table public.categories enable row level security;
alter table public.profiles enable row level security;
alter table public.portfolio_items enable row level security;
alter table public.media_assets enable row level security;
alter table public.events enable row level security;
alter table public.event_collaborators enable row level security;
alter table public.page_views enable row level security;

-- categories: world-readable, no client writes.
create policy "categories are world-readable"
  on public.categories for select
  to anon, authenticated
  using (true);

-- profiles: published pages are public; you always see yourself;
-- only you can edit you. Insert happens solely via handle_new_user
-- (SECURITY DEFINER) — no insert policy on purpose.
create policy "published profiles are world-readable"
  on public.profiles for select
  to anon, authenticated
  using (published or id = auth.uid ());

create policy "members update own profile"
  on public.profiles for update
  to authenticated
  using (id = auth.uid ())
  with check (id = auth.uid ());

-- portfolio_items: anonymous reads published; the owner does anything.
create policy "published portfolio items are world-readable"
  on public.portfolio_items for select
  to anon, authenticated
  using (published or profile_id = auth.uid ());

create policy "members insert own portfolio items"
  on public.portfolio_items for insert
  to authenticated
  with check (profile_id = auth.uid ());

create policy "members update own portfolio items"
  on public.portfolio_items for update
  to authenticated
  using (profile_id = auth.uid ())
  with check (profile_id = auth.uid ());

create policy "members delete own portfolio items"
  on public.portfolio_items for delete
  to authenticated
  using (profile_id = auth.uid ());

-- media_assets: visibility follows the parent portfolio item.
create policy "published items media is world-readable"
  on public.media_assets for select
  to anon, authenticated
  using (
    exists (
      select 1 from public.portfolio_items pi
      where pi.id = portfolio_item_id
        and (pi.published or pi.profile_id = auth.uid ())
    )
  );

create policy "members manage media of own items"
  on public.media_assets for insert
  to authenticated
  with check (
    exists (
      select 1 from public.portfolio_items pi
      where pi.id = portfolio_item_id and pi.profile_id = auth.uid ()
    )
  );

create policy "members update media of own items"
  on public.media_assets for update
  to authenticated
  using (
    exists (
      select 1 from public.portfolio_items pi
      where pi.id = portfolio_item_id and pi.profile_id = auth.uid ()
    )
  )
  with check (
    exists (
      select 1 from public.portfolio_items pi
      where pi.id = portfolio_item_id and pi.profile_id = auth.uid ()
    )
  );

create policy "members delete media of own items"
  on public.media_assets for delete
  to authenticated
  using (
    exists (
      select 1 from public.portfolio_items pi
      where pi.id = portfolio_item_id and pi.profile_id = auth.uid ()
    )
  );

-- events: published is public; collaborators see and edit (including
-- drafts); the host is a collaborator via trigger and additionally
-- may delete. Non-collaborators see nothing of a draft and can never
-- edit. Deletes are host-only.
create policy "published events are world-readable"
  on public.events for select
  to anon, authenticated
  using (
    status = 'published'
    or host_id = auth.uid ()
    or public.is_event_collaborator (id, auth.uid ())
  );

create policy "members create events they host"
  on public.events for insert
  to authenticated
  with check (host_id = auth.uid ());

create policy "collaborators update events"
  on public.events for update
  to authenticated
  using (
    host_id = auth.uid ()
    or public.is_event_collaborator (id, auth.uid ())
  )
  with check (
    host_id = auth.uid ()
    or public.is_event_collaborator (id, auth.uid ())
  );

create policy "hosts delete own events"
  on public.events for delete
  to authenticated
  using (host_id = auth.uid ());

-- event_collaborators: visible to the collaboration team (host is on
-- it); only the host manages the roster.
create policy "event team sees collaborators"
  on public.event_collaborators for select
  to anon, authenticated
  using (public.is_event_collaborator (event_id, auth.uid ()));

create policy "hosts add collaborators"
  on public.event_collaborators for insert
  to authenticated
  with check (public.is_event_host (event_id, auth.uid ()));

create policy "hosts remove collaborators"
  on public.event_collaborators for delete
  to authenticated
  using (public.is_event_host (event_id, auth.uid ()));

-- page_views: NO policies. Direct reads and writes are denied for
-- anon, authenticated, everything. The only door in is the SECURITY
-- DEFINER record_page_view(), and public aggregates go through the
-- trending views.
comment on table public.page_views is
  'Raw visitor events. RLS: no policies — never readable or writable by clients.';

-- ---------------- storage buckets ----------------

insert into storage.buckets (id, name, public)
values
  ('avatars', 'avatars', true),
  ('media', 'media', true),
  ('covers', 'covers', true),
  ('drafts', 'drafts', false)
on conflict (id) do update set public = excluded.public;

-- Public buckets: world-readable. Private drafts: no anon select at
-- all; even authenticated users are limited to their own uid/ folder,
-- so guessing another user's object path returns an error, not bytes.
create policy "public buckets are world-readable"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id in ('avatars', 'media', 'covers'));

create policy "drafts readable by owner folder only"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'drafts'
    and (storage.foldername (name))[1] = auth.uid ()::text
  );

create policy "members write own folder"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id in ('avatars', 'media', 'covers', 'drafts')
    and (storage.foldername (name))[1] = auth.uid ()::text
  );

create policy "members update own folder"
  on storage.objects for update
  to authenticated
  using (
    bucket_id in ('avatars', 'media', 'covers', 'drafts')
    and (storage.foldername (name))[1] = auth.uid ()::text
  )
  with check (
    bucket_id in ('avatars', 'media', 'covers', 'drafts')
    and (storage.foldername (name))[1] = auth.uid ()::text
  );

create policy "members delete own folder"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id in ('avatars', 'media', 'covers', 'drafts')
    and (storage.foldername (name))[1] = auth.uid ()::text
  );
