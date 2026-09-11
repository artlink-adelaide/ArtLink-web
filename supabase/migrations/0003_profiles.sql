-- 0003: profiles + handle_new_user trigger (registration creates the profile row).
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  handle text not null unique,
  display_name text not null,
  account_kind public.account_kind not null default 'individual',
  category_id smallint references public.categories (id),
  bio text,
  avatar_path text,
  published boolean not null default false,
  search_vector tsvector,
  created_at timestamptz not null default now (),
  updated_at timestamptz not null default now (),
  constraint handle_shape check (handle ~ '^[a-z0-9_]{3,30}$')
);

create index profiles_search_vector_idx on public.profiles using gin (search_vector);
create index profiles_category_idx on public.profiles (category_id);
create index profiles_published_idx on public.profiles (published);

-- Shared updated_at maintenance for every table that has the column.
create function public.touch_updated_at () returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now ();
  return new;
end;
$$;

create trigger trg_profiles_touch_updated_at
  before update on public.profiles
  for each row execute function public.touch_updated_at ();

-- Fires on auth.users insert. SECURITY DEFINER is required: the auth
-- hook runs as supabase_auth_admin, which owns no rights on public.
-- Handle generation: metadata handle if valid, else the email local-part
-- sanitised to the handle shape, with a numeric suffix on collision.
create function public.handle_new_user () returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  base text;
  candidate text;
  suffix int := 0;
begin
  base := lower(
    coalesce(
      nullif(new.raw_user_meta_data ->> 'handle', ''),
      split_part(coalesce(new.email, ''), '@', 1),
      'member'
    )
  );
  base := regexp_replace(base, '[^a-z0-9_]+', '_', 'g');
  base := regexp_replace(base, '^_+|_+$', '');
  if length(base) < 3 then
    base := 'member_' || substr(replace(new.id::text, '-', ''), 1, 8);
  end if;
  base := substr(base, 1, 30);

  candidate := base;
  while exists (select 1 from public.profiles p where p.handle = candidate) loop
    suffix := suffix + 1;
    candidate := substr(base, 1, 30 - length(suffix::text)) || suffix::text;
  end loop;

  insert into public.profiles (id, handle, display_name, account_kind, category_id)
  values (
    new.id,
    candidate,
    coalesce(
      nullif(new.raw_user_meta_data ->> 'display_name', ''),
      initcap(replace(candidate, '_', ' '))
    ),
    case new.raw_user_meta_data ->> 'account_kind'
      when 'organisation' then 'organisation'::public.account_kind
      else 'individual'::public.account_kind
    end,
    case
      when new.raw_user_meta_data ->> 'category_id' ~ '^\d+$'
        then (new.raw_user_meta_data ->> 'category_id')::smallint
      else null
    end
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user ();
