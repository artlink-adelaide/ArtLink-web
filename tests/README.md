# Tests

Two kinds of test are planned, matching the proposal's evaluation criteria:

- **Access-rule tests (E2)** — the ones that carry assessment weight:
  - a non-collaborator cannot edit an event
  - every listed collaborator *can* edit an event
  - a non-owner cannot modify a portfolio
  - an anonymous visitor can read public portfolios and events, and write nothing
- **Functional tests (E1)** — each confirmed Section 3.1 item works end to end.

Access-rule tests run against the local Supabase stack (`supabase start`), using
separate authenticated clients per user so Row-Level Security is genuinely
exercised rather than bypassed by the service-role key.
