-- 0009: interactions (likes) + like_counts + toggle_like +
-- record_member_view + category_affinity + the recommended views for
-- BOTH sides (events and artists) — four discovery objects total
-- together with 0006's trending pair (invariant 3).
--
-- Likes: members read/write only their own rows (scenario 19 keeps
-- other people's interactions invisible). Aggregate like_counts is a
-- default (definer) view: totals are public, rows are not.

create table public.interactions (
  id bigint generated always as identity primary key,
  member_id uuid not null references public.profiles (id) on delete cascade,
  subject_type text not null check (subject_type in ('event', 'profile', 'portfolio_item')),
  subject_id uuid not null,
  kind text not null default 'like' check (kind in ('like')),
  created_at timestamptz not null default now (),
  unique (member_id, subject_type, subject_id, kind)
);

create index interactions_member_idx on public.interactions (member_id);
create index interactions_subject_idx on public.interactions (subject_type, subject_id);

alter table public.interactions enable row level security;

create policy "members see own interactions"
  on public.interactions for select
  to authenticated
  using (member_id = auth.uid ());

create policy "members like as themselves"
  on public.interactions for insert
  to authenticated
  with check (member_id = auth.uid ());

create policy "members un-like as themselves"
  on public.interactions for delete
  to authenticated
  using (member_id = auth.uid ());

-- Public per-subject totals; the underlying rows stay private.
create view public.like_counts as
select subject_type, subject_id, count(*) as like_count
from public.interactions
where kind = 'like'
group by subject_type, subject_id;

create function public.toggle_like (p_subject_type text, p_subject_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member uuid := auth.uid ();
  v_ok boolean;
begin
  if v_member is null then
    raise exception 'AUTH_REQUIRED: sign in to like';
  end if;
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

  if exists (
    select 1 from public.interactions i
    where i.member_id = v_member
      and i.subject_type = p_subject_type
      and i.subject_id = p_subject_id
      and i.kind = 'like'
  ) then
    delete from public.interactions i
    where i.member_id = v_member
      and i.subject_type = p_subject_type
      and i.subject_id = p_subject_id
      and i.kind = 'like';
    return false;
  end if;

  insert into public.interactions (member_id, subject_type, subject_id, kind)
  values (v_member, p_subject_type, p_subject_id, 'like');
  return true;
end;
$$;

grant execute on function public.toggle_like (text, uuid) to authenticated;

-- Logged-in view recorder feeding category affinity (views weight 1).
create function public.record_member_view (p_subject_type text, p_subject_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid () is null then
    raise exception 'AUTH_REQUIRED: sign in to record member views';
  end if;
  perform public.record_page_view (p_subject_type, p_subject_id);
end;
$$;

grant execute on function public.record_member_view (text, uuid) to authenticated;

-- Per-member affinity toward each category: 3 points per like, 1 per
-- logged-in view of a subject in that category. SECURITY INVOKER so
-- each member's affinity is computed strictly from rows THEY may see
-- (their own interactions/views) — nobody can read someone else's
-- affinity profile through this view.
create view public.category_affinity
with (security_invoker = true) as
select
  signal.member_id,
  signal.category_id,
  sum(signal.score) as affinity
from (
  select
    i.member_id,
    coalesce(e.category_id, p.category_id, op.category_id) as category_id,
    3 as score
  from public.interactions i
  left join public.events e
    on i.subject_type = 'event' and e.id = i.subject_id
  left join public.profiles p
    on i.subject_type = 'profile' and p.id = i.subject_id
  left join public.portfolio_items pi
    on i.subject_type = 'portfolio_item' and pi.id = i.subject_id
  left join public.profiles op
    on op.id = pi.profile_id
  union all
  select
    pv.viewer_id as member_id,
    coalesce(e.category_id, p.category_id, op.category_id) as category_id,
    1 as score
  from public.page_views pv
  left join public.events e
    on pv.subject_type = 'event' and e.id = pv.subject_id
  left join public.profiles p
    on pv.subject_type = 'profile' and p.id = pv.subject_id
  left join public.portfolio_items pi
    on pv.subject_type = 'portfolio_item' and pi.id = pv.subject_id
  left join public.profiles op
    on op.id = pi.profile_id
  where pv.viewer_id is not null
) signal
where signal.category_id is not null
group by signal.member_id, signal.category_id;

-- Recommended feeds. SECURITY INVOKER: each member gets their own
-- ordering via their affinity; anonymous visitors see the global
-- trending order (no affinity rows for anon).
create view public.recommended_events
with (security_invoker = true) as
select
  e.id,
  e.host_id,
  e.category_id,
  e.title,
  e.description,
  e.starts_at,
  e.ends_at,
  e.price_cents,
  e.capacity,
  e.cover_path,
  coalesce(t.view_count, 0) as view_count,
  coalesce(ca.affinity, 0) as affinity
from public.events e
left join public.trending_events t on t.id = e.id
left join public.category_affinity ca
  on ca.category_id = e.category_id and ca.member_id = auth.uid ()
where e.status = 'published'
order by coalesce(ca.affinity, 0) desc, coalesce(t.view_count, 0) desc, e.starts_at asc;

create view public.recommended_artists
with (security_invoker = true) as
select
  p.id,
  p.handle,
  p.display_name,
  p.category_id,
  p.avatar_path,
  coalesce(t.published_items, 0) as published_items,
  coalesce(t.view_count, 0) as view_count,
  coalesce(ca.affinity, 0) as affinity
from public.profiles p
left join public.trending_artists t on t.id = p.id
left join public.category_affinity ca
  on ca.category_id = p.category_id and ca.member_id = auth.uid ()
where p.published
order by coalesce(ca.affinity, 0) desc, coalesce(t.view_count, 0) desc, p.handle asc;
