-- 0001: extensions and enums (BUILD_PLAN P1)
-- pg_trgm backs fuzzy search on handles/titles; unaccent normalises
-- user text before to_tsvector in the search_vector triggers (0006).
create extension if not exists pg_trgm;
create extension if not exists unaccent;

-- individual = a single artist/member; organisation = a band, gallery,
-- venue, collective. Any logged-in account may register for events
-- regardless of kind (written assumption in BUILD_PLAN §1).
create type public.account_kind as enum ('individual', 'organisation');

create type public.event_status as enum ('draft', 'published', 'cancelled');
