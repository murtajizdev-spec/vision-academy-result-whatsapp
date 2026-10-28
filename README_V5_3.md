# Academy Result Manager V5.3 — Integrated UI Release

This package extends V5.2, preserving existing modules and improving mobile navigation, keyboard accessibility, sticky marks-grid student column, and print styles. It does **not** claim completion of unimplemented integrations.

## Features retained
- Student records, class-wise workflows (no section selector in the test-series studio), attendance, fees, reports, analytics, FBISE SLO records, and earlier V3/V4/V5 modules.
- Bulk test series creator, class/subject dropdowns, add subject, test schedules, test edits, and marks spreadsheet.
- Excel import/export and local draft recovery with explicit Supabase save.

## Known limitations
- Not a verified production build: npm dependency installation could not complete in the creation environment. Run `npm ci` or `npm install`, then `npm run build` on your own build runner or Vercel.
- Existing V5.2 Supabase SQL must be reviewed against your actual database. Your database was previously missing functions expected by earlier migration scripts. Do not rerun older migrations blindly.
- Automated WhatsApp messages require Meta's official Cloud API and approved templates; current flow prepares manual WhatsApp sharing.
- Advanced monthly weighting, true server autosave, complete undo restoration, and batch PDF/image generation are not fully implemented.
- V3/V4 modules may have different permission assumptions; review RLS before handling live student records.

## Android GitHub → Vercel
1. Make backups of your GitHub repository and Supabase database.
2. Extract this ZIP; upload files **inside** the folder to a test GitHub repository/branch, preserving folder paths.
3. In Vercel import the repository. Framework: Vite; Build command: `npm run build`; Output: `dist`.
4. Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` for the test environment (use public/anon key, never service-role key). Redeploy.
5. Review SQL in `supabase/` before running anything. The existing-database migration is not guaranteed safe for your live database without review.
6. Test login, academy creation, class selection, subject creation, 2-test series creation, marks saving, report generation, and mobile navigation using fake student data.
7. Only promote the deployment to production after a successful build and passing live integration tests.

## Build locally
`npm install`
`npm run check`
`npm run build`
`npm run preview`

A successful ZIP archive integrity check is not equivalent to a successful Vite production build.
