# Academy Result Manager V5.4 — Incremental Implementation

This is a **source release**, not a certified production deployment. It is based on the actual V5.3 project and preserves earlier modules.

## Implemented in this release
- Academic Management navigation and a Student 360° view with test history, attendance, fee balance, Excel export and browser print-to-PDF.
- Academic session creation/listing with academy-scoped Supabase RLS. Session association columns and cross-academy integrity triggers.
- Excel rectangular range paste into the test-series marks grid, last-edit undo (50-entry buffer), existing bulk save and browser draft recovery.
- Improved keyboard focus, sticky spreadsheet columns and print/mobile styling.
- Existing bulk test-series creation, subject dropdowns and earlier modules retained.

## Not implemented / not verified
- Full report-card drag-and-drop designer, server-side autosave, full undo/redo across sessions, automatic WhatsApp Cloud API delivery, scheduled notifications, parent portal security audit, and end-to-end role permission tests.
- This environment has not confirmed an npm/Vite production build or live Supabase SQL execution. Do not replace a live deployment without tests.
- Student 360° lists all locally loaded marks; **published-result filtering is not yet implemented**. Keep this page staff-only and do not expose it to parents.
- Academic sessions currently organize dates; full session-based filtering and student promotions are future work.

## Deployment sequence
1. Back up the current project and Supabase database.
2. Verify existing `upgrade_existing_to_unified.sql` and `upgrade_v5_2_series.sql` were applied. Do **not** rerun historical V2/V3/V4 migrations blindly.
3. Run `supabase/upgrade_v5_4.sql` on a staging database and verify academy isolation.
4. Configure Vercel `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` (never expose service-role key).
5. Run `npm install`, `npm run check`, `npm run build`; use `dist` as Vercel output directory.
6. Test login, class/subject creation, 10-test bulk creation, Excel paste, undo, marks save and refresh, academic sessions, profile export, mobile layout and RLS before production rollout.

## Known safety issue to review
Existing earlier versions may allow non-approved reports to be viewed by staff, and older RLS policies may be broader than desired. A complete permissions audit is mandatory before granting parent/teacher access to sensitive data.
