-- 0002: categories + the seven fixed seeds (BUILD_PLAN §1).
-- The category list is deliberately closed; adding one later is costly
-- by design, so seeds are idempotent and slugs are the stable key.
create table public.categories (
  id smallint generated always as identity primary key,
  slug text not null unique,
  name text not null,
  sort_order smallint not null default 0,
  created_at timestamptz not null default now()
);

comment on table public.categories is
  'The seven fixed ArtLink categories (Music, Photography, Visual Arts, Performance, Design, Film, Food).';

insert into public.categories (slug, name, sort_order) values
  ('music', 'Music', 1),
  ('photography', 'Photography', 2),
  ('visual-arts', 'Visual Arts', 3),
  ('performance', 'Performance', 4),
  ('design', 'Design', 5),
  ('film', 'Film', 6),
  ('food', 'Food', 7);
