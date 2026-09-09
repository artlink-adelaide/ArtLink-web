import { afterAll, beforeAll, describe, expect, it } from "vitest";
import {
  appBase,
  completeOnboarding,
  createUser,
  sessionCookieHeader,
  startApp,
  type TestUser,
} from "./_harness";

let fresh: TestUser;
let onboarded: TestUser;
let app: { close: () => Promise<void> };

beforeAll(async () => {
  app = await startApp();
  fresh = await createUser("fresh");
  onboarded = await createUser("onboard");
  await completeOnboarding(onboarded);
});

afterAll(async () => {
  if (app) await app.close();
});

describe("P2 — middleware route protection (real Next server, real RLS)", () => {
  it("anonymous /dashboard redirects to /login carrying next", async () => {
    const res = await fetch(`${appBase()}/dashboard`, { redirect: "manual" });
    expect([302, 303, 307, 308]).toContain(res.status);
    // `next` is the middleware's signature: page-level defense-in-depth
    // redirects do not carry it, so this assertion goes red exactly when
    // the middleware gate is removed.
    expect(res.headers.get("location") ?? "").toContain("/login");
    expect(res.headers.get("location") ?? "").toContain("next=%2Fdashboard");
  });

  it("signed-in but un-onboarded user is bounced to /onboarding", async () => {
    const cookie = await sessionCookieHeader(fresh.email, fresh.password);
    const res = await fetch(`${appBase()}/dashboard`, {
      headers: { cookie },
      redirect: "manual",
    });
    expect([302, 303, 307, 308]).toContain(res.status);
    expect(res.headers.get("location") ?? "").toContain("/onboarding");
    expect(res.headers.get("location") ?? "").toContain("next=%2Fdashboard");
  });

  it("onboarded user gets the dashboard (200)", async () => {
    const cookie = await sessionCookieHeader(onboarded.email, onboarded.password);
    const res = await fetch(`${appBase()}/dashboard`, {
      headers: { cookie },
      redirect: "manual",
    });
    expect(res.status).toBe(200);
  });

  it("signout clears the cookie and the old cookie stops working", async () => {
    const cookie = await sessionCookieHeader(onboarded.email, onboarded.password);
    const before = await fetch(`${appBase()}/dashboard`, {
      headers: { cookie },
      redirect: "manual",
    });
    expect(before.status).toBe(200);

    const res = await fetch(`${appBase()}/auth/signout`, {
      method: "POST",
      headers: { cookie },
      redirect: "manual",
    });
    expect([302, 303, 307, 308]).toContain(res.status);
    expect(new URL(res.headers.get("location") ?? "").pathname).toBe("/");
    const setCookies = res.headers.getSetCookie().join("\n");
    expect(setCookies).toMatch(/sb-[\w-]*auth-token[^=]*=/);

    // The session was revoked server-side: replaying the pre-signout
    // cookie now lands on /login again — via the middleware, hence the
    // `next` marker.
    const after = await fetch(`${appBase()}/dashboard`, {
      headers: { cookie },
      redirect: "manual",
    });
    expect([302, 303, 307, 308]).toContain(after.status);
    expect(after.headers.get("location") ?? "").toContain("/login");
    expect(after.headers.get("location") ?? "").toContain("next=%2Fdashboard");
  });
});
