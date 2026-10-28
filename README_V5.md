# Academy Result Manager V5 — upgrade from V4

## Contents
- `src/main.jsx`: existing V2/V3/V4 features, V5 navigation, and an error boundary to replace blank-screen crashes with a recoverable error view.
- `src/V5.jsx`: flexible tests, spreadsheet-style section marks, Excel import/export, guardian contacts and consent, bulk section editing, student history, report templates, PNG/print-to-PDF, progress and rankings, SLO overview, approval workflow.
- `supabase/migrate_v4_to_v5.sql`: new V5 tables, row-level policies, validation triggers and audit triggers.
- Existing V4 files, server endpoints, backup workflow and older migrations are preserved.

## Upgrade an existing V4 Supabase database
1. Export/backup your V4 database and data. Prefer testing on a cloned/staging Supabase project first.
2. In Supabase SQL Editor run **only** `supabase/migrate_v4_to_v5.sql`. Do not rerun `schema.sql` or older migrations on an existing V4 database.
3. Verify six new tables: `student_guardians`, `exam_configs`, `mark_sections`, `result_approvals`, `report_templates`, `grading_scales`.
4. Replace existing repository contents with the extracted V5 project contents (keep `.github`, `api`, `src`, and `supabase` directories). Do not upload the ZIP as one file. Commit to the same branch connected to Vercel.
5. Vercel automatically builds the new commit. Framework Vite; build `npm run build`; output `dist`; root `./`. Retain existing `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` production environment variables. Redeploy if variables were changed.
6. Sign in and open **V5 Academic Studio** in the sidebar. Create a test, enter marks, save, approve/publish as admin, and generate a PNG. On Android, choose Print → Save as PDF.

## First-time database installation
Run `supabase/schema.sql`, then `supabase/migrate_v2_to_v3.sql`, then `supabase/migrate_v3_to_v4.sql`, then `supabase/migrate_v4_to_v5.sql`, in that order. Check each step before continuing. This does not migrate old browser-local V1 data.

## Important limitations / known issues
- V5 uses **manual** WhatsApp sharing (PNG download plus opening parent chat). V4 Cloud API endpoints are preserved but automatic result-image sending is **not** implemented or tested. Official WhatsApp Business Platform setup, opt-in and approved templates are needed for unattended messaging.
- Section marks are saved to both `mark_sections` and the legacy `marks` table for compatibility. Legacy V4 report views may display results before V5 approval; use V5 report studio for publication controls. Do not treat the V5 approval system as a universal publication security boundary until legacy views and parent access policies are updated.
- The marks entry screen supports explicit Save, not background autosave. Excel import stages values for review before saving. Offline draft sync is still the V4 module.
- Retests can be created as separate tests; automatic attempt linking and retest aggregation are not implemented.
- Student academic history currently shows marks for the student's current class; full cross-year historical promotion support requires a session/enrollment model.
- Backup and recovery: the existing V4 optional GitHub Actions backup is preserved. Verify backups and restore procedures separately. The V5 ZIP is not a backup of live student data.
- Automated PDF file generation is not implemented; use browser Print → Save as PDF.
- The code passed a TypeScript JSX **syntax parse**, but the full Vite production build and end-to-end Supabase integration **could not be verified** because package installation was unavailable in this environment. Deploy to staging before production.
- Protect guardian information and avoid exposing student reports through public URLs. Review RLS for all existing V4 tables, especially `marks`, `parent_students`, and message data.

## Troubleshooting
If Vercel build fails, open Deployments → failed deployment → Build Logs and check the first error. If the app displays the error boundary, copy the error text (remove private data) and investigate Supabase tables, policies and browser console. If you see 'V5 tables unavailable', apply the V5 migration in the correct Supabase project.
