# Rumah Sehat Kakang — Refleksi

SvelteKit 5 frontend, Express 5 API, Supabase Auth and PostgreSQL with row-level security. Deployed to Vercel.

## Local development

Use Node 22. Run `npm ci`, then `npm run server` and `npm run dev` in separate terminals. Vite proxies `/api` to Express on port 3001. `npm run check`, `npm test`, and `npm run build` validate the app. The build script merges the Express function into SvelteKit's Vercel Build Output. No service-role key is required or included.

## Authentication and roles

Email/password login with verified email. Public registration always creates a customer. Roles are read from the protected `profiles` table on every API request and checked again by database policies. User-editable metadata is never trusted for permissions.

| Role | Permissions |
| --- | --- |
| Administrator | View all appointments, create reservations for customers, assign therapists, manage other accounts and role changes, read role audit history, update own contact profile. |
| Therapist | View assigned appointments and related customer contact data, start a confirmed session, complete an in-progress session, update own contact profile. |
| Customer | View and create own appointments, view assigned therapist details and service catalog, update own contact profile. |

Administrator can deactivate accounts; changes affect API and direct Data API access immediately. No account may change its own privileges through the app. The last active administrator cannot be disabled or demoted. Role changes/deactivation with active reservations require handling those reservations first. Therapist assignment prevents overlapping active sessions. Service prices and durations are set by the database, never trusted from browser input. Completing a session does not record a payment.

Public profiles and appointments are inaccessible to anonymous users. A publishable Supabase key is intentionally public. No production data is stored in localStorage; Supabase SDK stores only the authentication session there. Dashboard shells do not embed private data; the Express API authenticates before returning it.

## Initial administrator

An owner bootstrap email is configured privately in the database. Its first verified registration is promoted once. Other registrations remain customers regardless of supplied metadata. No passwords or user accounts are seeded. A real owner must register and verify their email. Configure the Supabase Auth Site URL and allowed redirect URLs to the production origin for seamless email confirmation. Without that configuration, confirm the email and return manually to the app's login page.

Database project: `tpdcetrvlpemqcibokmb`, Singapore. `supabase/rbac-schema.sql` records the new schema; do not re-run on an initialized database. The private bootstrap email row is provisioned separately, not committed. Supabase's hosted email delivery limits apply; production-scale mail needs configured SMTP.

## Validation

`tests/rbac.test.js` runs five Express authorization and input-boundary tests. `tests/rls.sql` tests real PostgreSQL policies and triggers in a transaction that rolls back all fixtures, including auth users. It covers owner verification, metadata privilege escalation, customer/therapist row isolation, role tampering, assignment, overlaps, valid/invalid session transitions, immediate inactive-user denial, and anonymous access denial. Only run against this project's intended schema.

The dashboard shows up to 300 most recent authorized reservations; account management shows up to 500 recent accounts and 100 recent audit entries. No payment gateway or clinical notes are included.
