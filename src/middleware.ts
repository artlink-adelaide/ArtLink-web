import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { env } from "./lib/env";

/**
 * Route prefixes that require a session. This list (together with the
 * `config.matcher` below and the two redirect branches) IS the auth
 * gate; `npm run test:auth` reverse-verifies it by removing it and
 * expecting the suite to go red.
 */
const PROTECTED_PREFIXES = ["/dashboard", "/onboarding"];

const PUBLIC_PREFIXES = ["/login", "/register"];

export async function middleware(request: NextRequest) {
  let response = NextResponse.next({ request });

  const supabase = createServerClient(
    env.NEXT_PUBLIC_SUPABASE_URL,
    env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          for (const { name, value } of cookiesToSet) {
            request.cookies.set(name, value);
          }
          response = NextResponse.next({ request });
          for (const { name, value, options } of cookiesToSet) {
            response.cookies.set(name, value, options);
          }
        },
      },
    },
  );

  // HARD RULE: authorization uses getUser(), which validates the token
  // with the auth server. getSession() only decodes the local cookie
  // and MUST NOT be used for any permission decision.
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const path = request.nextUrl.pathname;
  const isProtected = PROTECTED_PREFIXES.some((p) => path.startsWith(p));
  const isPublicAuthPage = PUBLIC_PREFIXES.some((p) => path.startsWith(p));

  if (isPublicAuthPage && user) {
    const url = request.nextUrl.clone();
    url.pathname = "/dashboard";
    url.search = "";
    return NextResponse.redirect(url);
  }

  if (!isProtected) {
    return response;
  }

  if (!user) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.search = "";
    url.searchParams.set("next", path);
    return NextResponse.redirect(url);
  }

  // Incomplete onboarding: handle_new_user created the profile row at
  // signup, but category/handle choice happens in /onboarding. category_id
  // is the completion marker — NULL means the user must not reach the
  // dashboard yet (see P2 brief).
  const { data: profile } = await supabase
    .from("profiles")
    .select("category_id")
    .eq("id", user.id)
    .maybeSingle();

  if (profile == null || profile.category_id == null) {
    // `next` marks this redirect as middleware-made; test:auth asserts
    // it so removing the middleware gate turns the suite red even
    // though pages carry their own defense-in-depth redirects.
    const url = request.nextUrl.clone();
    url.pathname = "/onboarding";
    url.search = "";
    url.searchParams.set("next", path);
    return NextResponse.redirect(url);
  }

  return response;
}

export const config = {
  matcher: ["/dashboard/:path*", "/onboarding/:path*", "/login", "/register"],
};
