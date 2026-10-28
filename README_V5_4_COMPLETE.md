# V5.4 Extended Implementation — Source Package

## Added in this package
- New Report Studio in navigation with class/subject/student selectors, printable student and class report cards, academy branding, optional attendance and fee balances, editable remarks, and Excel export.
- Spreadsheet Undo and Redo for single-cell edits (browser session only).
- Previous V5.4 academic sessions, student profiles, test series, Excel range paste, bulk save and drafts remain.

## Limitations — do not deploy as production without testing
- Report Studio is for **authenticated staff only**. It does **not** check approval/published state. Do not grant parents access to it.
- No verified live Supabase migrations, API credentials, production WhatsApp messaging, scheduled notifications, server autosave, or audited role security.
- PDF generation uses the browser print dialog (Print / Save as PDF), not server batch PDFs.
- Existing historical code and dependencies may require further fixes.

## Build and deployment
1. Back up Supabase and existing GitHub repository.
2. Install dependencies with `npm install` then `npm run build`.
3. Run the unified, V5.2 and V5.4 migrations **only if needed** on staging; follow README_V5_4.md.
4. Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` in Vercel; never publish a service-role key.
5. Test permissions, marks save, test series creation, report correctness and mobile printing.
6. Deploy to production only after acceptance tests and rollback plan.
