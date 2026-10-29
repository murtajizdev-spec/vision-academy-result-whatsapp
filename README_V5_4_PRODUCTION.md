# Academy Result Manager V5.4 — Security & WhatsApp Integration Candidate

This is a **staging release candidate**, not a certified production deployment. It extends the V5.4 Extended source with:

- Debounced **Supabase server-persisted autosave** option for spreadsheet marks, retaining local drafts on failure; Save marks remains available.
- **Published-only** Report Studio by default; academy admins can enable draft preview for internal use. Approval fetch failure blocks export/printing.
- **Teacher assignments** by class and subject, **parent access links**, and restrictive Row Level Security on marks, students, exams, attendance, fees, and other academy data.
- Database-backed **change audit** for teacher/parent access changes, plus existing unified marks audit.
- Admin **WhatsApp Communication** UI for queued approved templates, parameters, opt-in confirmation, scheduling and delivery status.
- **Vercel Cron** `/api/send-queued` daily at 04:00 UTC, signed Meta webhook for sent/delivered/read/failed status. This schedule is daily, NOT real-time. For more frequent processing, use a supported cron tier or an external scheduler with the secret header.
- Parent Portal retains its existing UI but server RLS now restricts it to linked students and published marks. Parent accounts must be created/invited and linked by an admin.

## Migration order (STAGING FIRST)

1. Back up the **full database**, auth records, and existing project.
2. Verify existing `public.my_academy()` and `public.is_academy_admin(uuid)`.
3. If not previously applied, apply `supabase/upgrade_existing_to_unified.sql`, `supabase/upgrade_v5_2_series.sql`, and `supabase/upgrade_v5_4.sql` in order. Do not run old V2/V3 migrations blindly.
4. Run **`supabase/upgrade_v5_4_security_automation.sql`**. This intentionally tightens RLS; it may block teachers until assigned. Existing data is not deleted.
5. Invite teacher and parent accounts using the existing authentication workflow; use **Teacher & Parent Access** to assign permissions and links.
6. Check each test's `result_approvals` row and publish approved results before exposing to parents. Missing approval = unpublished.
7. Test separate admin, teacher, parent, and second-academy accounts; test mark lock, export restrictions, and teacher assignment.

## Vercel environment variables

Frontend: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`.

Server-only: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `CRON_SECRET`, `WHATSAPP_ACCESS_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID`, `WHATSAPP_VERIFY_TOKEN`, `WHATSAPP_APP_SECRET`, optional `WHATSAPP_GRAPH_VERSION`.

**Never** prefix service-role or Meta tokens with `VITE_`. Never commit real credentials to GitHub.

## WhatsApp Business Platform setup

- Use the Meta **WhatsApp Business Platform / Cloud API** (not only the WhatsApp Business mobile app).
- Confirm the configured phone number ID and access token have permission to send messages.
- Create/approve a Meta message template, including matching body variable count/order.
- Register webhook URL `https://YOUR-VERCEL-DOMAIN/api/whatsapp-webhook`, configure verification token and subscribe to message status events.
- Configure `CRON_SECRET` in Vercel. Vercel invokes the configured cron with bearer authorization. For manual cron invocation, send `Authorization: Bearer <CRON_SECRET>` from a trusted server; never from frontend JavaScript.
- In the app, choose a student/phone, approved template, parameters, time, and explicitly confirm recipient opt-in. Queue and review status.
- Test with a consented test number. Templates and message content are subject to Meta's review and WhatsApp policy. Message success cannot be guaranteed; inspect `failed` status and Meta logs.
- **No automatic message is sent merely because a result is published**. The admin must queue the approved template. Fully automatic result-triggered queueing requires additional opt-in and template mapping rules.

## Build and verification

- `npm install`
- `npm run build`
- `node scripts/verify-v54.mjs` (requires globally installed TypeScript in the provided environment; static validation only)
- Deploy to Vercel staging and test actual Supabase migration and Meta send/webhook flows.

## Known limits and operational cautions

- The full Vite build was **not run here** because npm registry DNS resolution failed. JSX and API syntax checks passed, but this does not prove runtime correctness.
- SQL migration was **not executed against a real Supabase project**. Inspect existing policies, functions and constraints first; run on a database clone.
- Server autosave uses the existing Supabase `marks` table, not a separate trusted server endpoint. RLS and mark lock triggers enforce authorization; the UI preserves drafts if save fails.
- Blank marks cells are not automatically deleted from the server. Explicit absence/exemption is handled by existing marks-section workflows, not by this grid.
- No automated integration tests were run against real authentication, Meta API, cron, or a production environment.
- Vercel Cron timing and frequency depend on plan. The included daily schedule can deliver messages late relative to requested minute-level times.
- Existing report card screens and legacy modules remain staff-only; they were not completely refactored.
- Legacy permissions should be reviewed for non-marks mutations (exam configuration, attendance, student management) before production rollout.
- Existing RLS policy sets vary by historical migration path. The migration adds restrictive policies but should be reviewed by a Supabase/Postgres specialist on staging.

## Rollback

Keep the database backup and Vercel prior deployment. Reverting frontend code alone **does not revert restrictive RLS changes**; restore the tested database backup or apply a reviewed rollback migration. Do not disable RLS to make a broken workflow work.
