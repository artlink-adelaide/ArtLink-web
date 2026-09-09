-- 0010: anonymous handle-availability check (P2 onboarding).
--
-- "这个 handle 被占了吗?" must be answerable WITHOUT letting anonymous
-- visitors read the profiles table. Widening the profiles SELECT policy
-- would expose every profile to the public anon key; instead a SECURITY
-- DEFINER function answers exactly one boolean and nothing else.
-- The RLS policies on profiles are untouched.

create function public.handle_available (p_handle text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    p_handle ~ '^[a-z0-9_]{3,30}$'
    and not exists (
      select 1 from public.profiles pr where pr.handle = p_handle
    );
$$;

grant execute on function public.handle_available (text) to anon, authenticated;
