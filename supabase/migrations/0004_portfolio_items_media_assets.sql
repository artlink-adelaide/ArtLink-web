-- 0004: portfolio_items + media_assets, including the five extended
-- media columns from BUILD_PLAN (alt_text, content_type, width/height,
-- bucket, variant). Each exists because a bare (path, kind) table
-- cannot carry this product:
--   alt_text     — accessibility; publishing requires it (guarded below)
--   content_type — the SNIFFED real type, never the browser's claim
--   width/height — reserve layout space, no CLS when images load
--   bucket       — separates public `media` from private `drafts`
--   variant      — original master vs derived sizes
create table public.portfolio_items (
  id uuid primary key default gen_random_uuid (),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  description text,
  media_kind text not null check (media_kind in ('image', 'video')),
  published boolean not null default false,
  published_at timestamptz,
  search_vector tsvector,
  created_at timestamptz not null default now (),
  updated_at timestamptz not null default now ()
);

create table public.media_assets (
  id uuid primary key default gen_random_uuid (),
  portfolio_item_id uuid not null references public.portfolio_items (id) on delete cascade,
  path text not null,
  alt_text text,
  content_type text not null,
  width integer,
  height integer,
  bucket text not null check (bucket in ('avatars', 'media', 'covers', 'drafts')),
  variant text not null default 'original',
  position integer not null default 0,
  created_at timestamptz not null default now ()
);

create index portfolio_items_profile_idx on public.portfolio_items (profile_id);
create index portfolio_items_search_vector_idx on public.portfolio_items using gin (search_vector);
create index media_assets_item_idx on public.media_assets (portfolio_item_id);
create index media_assets_bucket_idx on public.media_assets (bucket);

create trigger trg_portfolio_items_touch_updated_at
  before update on public.portfolio_items
  for each row execute function public.touch_updated_at ();

-- "空值不允许发布": a portfolio item cannot flip to published while any
-- of its media lacks alt text. Enforced here so no client can bypass it.
create function public.portfolio_items_publish_guard () returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.published and old.published is distinct from true then
    if exists (
      select 1 from public.media_assets m
      where m.portfolio_item_id = new.id
        and (m.alt_text is null or btrim(m.alt_text) = '')
    ) then
      raise exception 'cannot publish portfolio item: media alt_text missing';
    end if;
    new.published_at := coalesce(old.published_at, now ());
  end if;
  return new;
end;
$$;

create trigger trg_portfolio_items_publish_guard
  before update of published on public.portfolio_items
  for each row execute function public.portfolio_items_publish_guard ();
