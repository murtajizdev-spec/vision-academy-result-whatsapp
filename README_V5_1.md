# Academy Result Manager V5.1 — upgrade notes

This is an incremental source-code upgrade of V5. Existing V3/V4 modules are preserved. The student interface is class-wise, without section selectors. Existing `students.section` column remains in the database for backwards compatibility; new student records store an empty section.

## Important: your database is NOT yet ready

You reported `is_staff(uuid)=false`, `audit_v4()=false`, and `students=true`. Do not apply the V5.1 SQL first. The V3 and V4 migration scripts are present in `/supabase`, but may fail if partially installed. Back up the database, inspect `pg_policies`, triggers and existing tables, then apply missing migrations in order on a TEST project:

1. `schema.sql` only for a truly empty database (do not rerun on existing DB).
2. `migrate_v2_to_v3.sql` after confirming V3 has not already been partly applied.
3. `migrate_v3_to_v4.sql` after confirming V4 has not already been partly applied.
4. `migrate_v4_to_v5.sql` after checking V5 tables and policies.
5. `migrate_v5_to_v5_1.sql` (transactional, prerequisite checks, re-runnable policies/triggers).

Never run the legacy migration scripts blindly on an existing production database. No service-role or secret keys should be placed in VITE_ variables.

## Features added in this patch

- Class-wise student directory; no section selector in main student form or V5 studio.
- Inline editing of student name, class, roll number and parent contact.
- Bulk promotion to a selected class, preserving existing academic records.
- Suggested next numeric roll number, manually editable.
- Subject/class-specific pass percentages in V5.1 settings; custom subjects.
- Duplicate test action, preserving V5 test configuration.
- Browser-local marks draft recovery with explicit save to Supabase. **Draft autosave is local to the current device/browser, not server-synced.**
- Retains V5 Excel import/export, result approvals, gradebook, report templates, PNG and print-to-PDF, manual WhatsApp sharing, analytics and audit triggers.
- New schema supports custom student fields and dashboard settings; their full editing UI is not implemented in this patch.

## Known limitations

- A full npm/Vite production build was **not verified** in the creation environment because dependency installation timed out. Run `npm ci` (if lockfile supplied) or `npm install`, then `npm run build` locally or in Vercel.
- Subject pass defaults are stored and displayed; existing V5 test creation retains its own editable pass percentage, and does not yet automatically copy the saved default.
- Automatic WhatsApp sending requires official WhatsApp Business Platform configuration and permission; current sharing requires manual attachment.
- Browser print offers Save as PDF; batch PDF/image export is not implemented.
- Some requested items (monthly weighting editor, undo restoration, dashboard layout editor, profile custom field UI, editable report remarks) remain future work. Do not rely on them in production.
- Existing V4 screens may still expose results outside V5 approval workflow; review RLS and access before using real student data.

## Android → GitHub → Vercel

1. Download ZIP, extract on Android using Files or a ZIP utility.
2. Back up your GitHub repo and Supabase database.
3. Upload changed project files to your existing GitHub repo (keep directory structure).
4. In Supabase SQL Editor, install the missing migrations safely, then `migrate_v5_to_v5_1.sql`.
5. In Vercel, keep `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` in Production Environment Variables; redeploy.
6. Open the Vercel build log and confirm `vite build` succeeds. Test login, academy creation, class filtering, student edit, test duplication, draft recovery and result publishing with dummy records.
7. If the screen turns white, capture the Chrome JavaScript console error; the existing React error boundary shows a recovery screen for render errors, not all asynchronous errors.
