# Academy Result Manager V5.2 — Bulk Test Series & Spreadsheet Marks

## New functionality
- Connected class and subject selectors; **no section selector**.
- Add subjects to the selected class, saved in Supabase.
- Generate up to 100 tests at once with editable title, syllabus, date, maximum marks and passing percentage.
- Create a named series and link tests to it.
- Class-wide marks spreadsheet: students in rows, series tests in columns, live totals and percentages.
- Excel import/export, browser-local draft recovery, and explicit bulk Save to Supabase.
- Existing modules retained from the Unified release.

## Upgrade order (existing academy database)
1. Make a verified database backup and test on a copy.
2. Confirm `supabase/upgrade_existing_to_unified.sql` was installed successfully. If it has not been, review that migration carefully against your actual database before applying it. Do not run the older V2/V3 migrations merely for this release.
3. Run `supabase/upgrade_v5_2_series.sql` in Supabase SQL Editor.
4. Deploy the project to a **test Vercel deployment** with `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` set.
5. Open **Bulk Test Series & Marks** in the sidebar, choose class and subject, generate tests, review, save, and enter marks.
6. Verify RLS, marks locking, and test-series permissions before using real student data.

## Android GitHub/Vercel
Extract the ZIP using Files. Upload its contents, preserving folders, to a GitHub test branch/repository. Vercel should use `npm run build`, output directory `dist`. Set the two Vite environment variables in Vercel Settings and redeploy.

## Known limitations
- This release does **not** automatically send WhatsApp messages; existing manual workflow remains.
- The series creation consists of several requests. If interrupted after creating the series, some tests/configurations may have been saved. Inspect the existing series before retrying; do not blindly create duplicates.
- Blank marks remain blank during editing, but the spreadsheet totals count blanks as zero until recorded. No explicit absent marker is implemented in this new spreadsheet.
- Draft recovery uses local browser storage; it is not a server-side autosave. Use Save to persist marks.
- Existing exam approval locks are enforced by the installed unified SQL, not by this UI alone.
- Production build and live Supabase end-to-end testing must be completed before calling this production-ready.
