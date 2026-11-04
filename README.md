# Rumah Sehat Kakang — Refleksi

Frontend SvelteKit 5, backend Express 5, PostgreSQL hosted on Supabase.

## Run

Use Node 22. Run `npm ci`, then `npm run dev`. For the Express scaffold use `npm run server`. Build with `npm run build`; validate with `npm run check`.

## Current scope

Responsive admin frontend: dashboard, reservations, customer list, therapist list, service catalog, payment simulation, settings. Reservations are demo data persisted in localStorage; session completion is not proof of payment. The active service catalog is read from Supabase using a public read-only policy. No real customer data should be entered yet. Authentication, role authorization, real booking persistence and real payments are not implemented. Prices and therapists are examples.

Supabase project: tpdcetrvlpemqcibokmb (Singapore). The publishable browser key is intentionally public. No server secrets are included. PostgreSQL connections must use a server-only DATABASE_URL with certificate validation when backend integration is implemented.

## Deployment

Vercel project target name: refleksi-kakang, account team kakangbakery. Use SvelteKit framework with Node 22. Backend Express is separately runnable; `api/index.js` exports its serverless handler. Frontend build has no database secrets. GitHub repository creation and Vercel deployment are pending account access.
