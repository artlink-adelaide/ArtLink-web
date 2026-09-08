-- 0006: page_views, the trending views, record_page_view, and the
-- search_vector maintenance triggers for profiles / portfolio_items /
-- events (the columns were created with their tables in 0003-0005;
-- this migration gives every one of them its maintaining trigger,
-- plus GIN coverage came with the tables).
create table public.page_views (
  id bigint generated always as identity primary key,
  subject_type text not null check (subject_type in ('event', 'profile', 'portfolio_item')),
  subject_id uuid not null,
  viewer_id uuid references public.profiles (id) on delete set null,
  viewed_at timestamptz not null default now ()
);

create index page_views_subject_idx on public.page_views (subject_type, subject_id, viewed_at);
create index page_views_viewer_idx on public.page_views (viewer_id);

-- ---------------- search_vector maintenance ----------------
-- Title-weighted higher than description (setweight A > B > C).
-- unaccent is STABLE, fine inside a trigger (not a generated column).
-- search_path is pinned because trigger functions must not depend on
-- the caller's session path (a SECURITY DEFINER caller with an empty
-- path would otherwise break unaccent resolution).

create function public.profiles_search_vector_refresh () returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.search_vector :=
    setweight(to_tsvector('english', unaccent(coalesce(new.display_name, ''))), 'A') ||
    setweight(to_tsvector('english', unaccent(coalesce(new.handle, ''))), 'B') ||
    setweight(to_tsvector('english', unaccent(coalesce(new.bio, ''))), 'C');
  return new;
end;
$$;

create trigger trg_profiles_search_vector
  before insert or update of display_name, handle, bio on public.profiles
  for each row execute function public.profiles_search_vector_refresh ();

create function public.portfolio_items_search_vector_refresh () returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.search_vector :=
    setweight(to_tsvector('english', unaccent(coalesce(new.title, ''))), 'A') ||
    setweight(to_tsvector('english', unaccent(coalesce(new.description, ''))), 'B');
  return new;
end;
$$;

create trigger trg_portfolio_items_search_vector
  before insert or update of title, description on public.portfolio_items
  for each row execute function public.portfolio_items_search_vector_refresh ();

create function public.events_search_vector_refresh () returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.search_vector :=
    setweight(to_tsvector('english', unaccent(coalesce(new.title, ''))), 'A') ||
    setweight(to_tsvector('english', unaccent(coalesce(new.description, ''))), 'B');
  return new;
end;
$$;

create trigger trg_events_search_vector
  before insert or update of title, description on public.events
  for each row execute function public.events_search_vector_refresh ();

-- ---------------- trending views ----------------
-- SECURITY DEFINER semantics (default view behaviour, owner = postgres)
-- are deliberate: page_views itself denies ALL direct reads via RLS
-- (0007), while the aggregate over published subjects is public data —
-- the anonymous homepage depends on it.

create view public.trending_events as
select
  e.id,
  e.host_id,
  e.category_id,
  e.title,
  e.starts_at,
  e.price_cents,
  count(pv.id) filter (
    where pv.viewed_at > now() - interval '7 days'
  ) as view_count
from public.events e
left join public.page_views pv
  on pv.subject_type = 'event' and pv.subject_id = e.id
group by e.id;

create view public.trending_artists as
select
  p.id,
  p.handle,
  p.display_name,
  p.category_id,
  p.avatar_path,
  count(distinct pi.id) as published_items,
  count(pv.id) filter (
    where pv.viewed_at > now() - interval '7 days'
  ) as view_count
from public.profiles p
left join public.page_views pv
  on pv.subject_type = 'profile' and pv.subject_id = p.id
left join public.portfolio_items pi
  on pi.profile_id = p.id and pi.published
where p.published
group by p.id;

-- Anonymous-callable page view recorder. SECURITY DEFINER because
-- page_views has no insert policy by design (visitors must never write
-- or read the table directly); the definer path is the only door in.
create function public.record_page_view (
  p_subject_type text,
  p_subject_id uuid
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ok boolean;
begin
  if p_subject_type not in ('event', 'profile', 'portfolio_item') then
    raise exception 'UNKNOWN_SUBJECT_TYPE: %', p_subject_type;
  end if;

  v_ok :=
    case p_subject_type
      when 'event' then
        exists (select 1 from public.events e
                where e.id = p_subject_id and e.status = 'published')
      when 'profile' then
        exists (select 1 from public.profiles p
                where p.id = p_subject_id and p.published)
      when 'portfolio_item' then
        exists (select 1 from public.portfolio_items pi
                where pi.id = p_subject_id and pi.published)
    end;

  if not v_ok then
    raise exception 'SUBJECT_NOT_FOUND_OR_NOT_PUBLISHED';
  end if;

  insert into public.page_views (subject_type, subject_id, viewer_id)
  values (p_subject_type, p_subject_id, auth.uid ());
end;
$$;

grant execute on function public.record_page_view (text, uuid) to anon, authenticated;
