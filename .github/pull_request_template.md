## What this changes

<!-- One or two sentences. -->

## Vertical

<!-- Accounts & Profiles / Events / Public Discovery & Trending / Collaboration / Multimedia, Storage & Deployment -->

## Requirement source

<!-- Tag the requirement this serves, per proposal Section 3:
     - Layer 1 (confirmed client requirement) - cite the Section 3.1 item
     - Layer 2 (team implementation decision)
     Anything in Layer 3 (future implementation) should not be in a PR. -->

- [ ] Layer 1 — Section 3.1 item: ______
- [ ] Layer 2 — team implementation decision

## Checks

- [ ] `npm run lint`, `npm run typecheck`, `npm test` and `npm run build` pass locally
- [ ] Access rules: a non-collaborator cannot edit; a non-owner cannot modify
- [ ] No secret committed (`SUPABASE_SERVICE_ROLE_KEY` never leaves `.env.local`)
- [ ] Migrations touching `profiles`, `media_assets` or `events` reviewed by the other affected vertical owner (Change Register C5)

## Reviewer

<!-- PR review is mandatory per the risk register mitigation for integration failures. -->
