# Academy Result Manager — Unified Release (existing database upgrade)

This release consolidates the existing V3, V4, V5 and V5.1 React modules and adds a direct migration matching the database shown by the user (`academies`, `profiles`, `students`, `exams`, `marks`, `attendance`, `fees`, `invitations`, `slos`, `slo_assessments`).

## Installation sequence
1. BACK UP Supabase database and current GitHub repository. Test on a Supabase staging clone before production.
2. Open `supabase/upgrade_existing_to_unified.sql` in Supabase SQL Editor and run ONCE. Do not run schema.sql or historical V2→V3→V4→V5 migration files on this existing database.
3. Confirm tables `exam_configs`, `mark_sections`, `result_approvals`, `student_guardians`, `report_templates`, `grading_scales`, `subject_pass_rules`, `academy_subjects`, `student_custom_fields`, `academy_ui_settings`, `unified_change_history` exist.
4. Upload the extracted project contents (not the ZIP itself) to a new GitHub branch or test repository.
5. In Vercel set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` for Production and Preview; deploy the test branch.
6. Test sign-in, academy loading, student add/edit, exam creation, marks, approvals, PNG export, and mobile layout with non-sensitive sample data.
7. Only after testing, promote the build to production.

## Existing schema and class-wise policy
Student records remain grouped by `class_name`. The existing `students.section` column is left untouched for data safety but is not required by the unified academic workflow. No new sections are created.

## WhatsApp
The report studio opens a WhatsApp chat and downloads an image; a human must attach and send it. Fully automatic WhatsApp sending requires a configured official Meta WhatsApp Business Platform account, valid templates, consent and a server-side integration.

## Build and deployment caveats
This project has not been confirmed production-ready on a real Supabase account. Validate RLS for teacher and admin roles, test database migration on a clone, and check Vercel build logs. Do not expose Supabase service-role keys in the browser.

## Recovery
The SQL runs in one transaction. If a statement fails, Supabase rolls back that run. Restoring from a backup is still recommended for any later data/behavior issues.
