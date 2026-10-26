# Academy Result Manager V4

V4 upgrades V3, preserving existing modules and adding a WhatsApp queue, rule-based parent summaries, teacher question drafts, risk flags, printable fee summaries, appointments, audit logs, Excel exports, encrypted backup workflow, and offline marks drafts.

## Critical WhatsApp distinction

**WhatsApp Business App is not the WhatsApp Business Platform (Cloud API).** A Business App account by itself cannot send unattended messages through this project. The app always supports manual click-to-chat. Cloud API automation requires Meta Business setup, an eligible phone number, approved templates, opt-in, API credentials, and potentially messaging fees. Message queue drafts are never automatically sent. Admins must confirm consent, enter an approved template name and queue messages. The server sends **only the approved template** and not the arbitrary preview body. Templates in this implementation have **no variables**: if you want personalized marks, results, report images or fee amounts, you must extend the approved template parameter and media flow before relying on them. Automatic result card images are NOT yet supported by the Cloud API endpoint. A queued message with template name does not guarantee the preview body is delivered. Message status `sent` is API acceptance, not proof of delivery. Webhook updates `delivered` / `read` when provided.

The server endpoint `/api/send-queued` requires `Authorization: Bearer <CRON_SECRET>` and can be called by an external scheduled service or Vercel Cron if supported by your plan. It processes up to 20 approved messages per run. It does not automatically create queue entries from changes to marks, attendance, or fees. For unattended event-triggered automation, a future trusted server-side job must enqueue messages with opt-in and correct template parameters.

## Android deployment

1. Back up V3 and make a new GitHub branch or download a copy of your existing repository. Extract the ZIP on Android.
2. Upload V4 **contents** to the existing repository root, preserving folders including `src`, `api`, `supabase`, and `.github`. Delete obsolete files if needed. Commit. GitHub's mobile browser can be cumbersome for folders; using GitHub's web editor (github.dev) in desktop-site mode is an alternative.
3. In Supabase Dashboard → SQL Editor, run **only** `supabase/migrate_v3_to_v4.sql` on the existing V3 database. Do not rerun earlier schemas. Test first in a separate staging project.
4. Vercel should redeploy automatically. Existing `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` stay as they were. Build preset: Vite, command `npm run build`, output `dist`.
5. Test with sample data. Verify RLS and permissions using separate teacher, admin and parent test accounts. The new modules require online access except the offline marks drafts.
6. For optional Cloud API automation, set **server-only** Vercel variables `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `CRON_SECRET`, `WHATSAPP_ACCESS_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID`, `WHATSAPP_VERIFY_TOKEN`, `WHATSAPP_APP_SECRET`, and optionally `WHATSAPP_TEMPLATE_LANGUAGE`. Redeploy. Configure Meta webhook `https://YOUR-DOMAIN/api/whatsapp-webhook`. Never put service role or WhatsApp tokens in GitHub, `VITE_*`, or browser source.
7. Configure a scheduler to call `GET https://YOUR-DOMAIN/api/send-queued` with bearer `CRON_SECRET` at an appropriate interval. Do not publish the token. Do not use the endpoint until Cloud API and templates are approved and opt-ins verified.
8. Optional automatic backups: GitHub repository Settings → Secrets and variables → Actions: set `SUPABASE_DB_URL` (Postgres connection string with dump permissions) and `BACKUP_PASSPHRASE` (strong separate secret). Enable GitHub Actions. `.github/workflows/backup.yml` creates a daily encrypted pg_dump artifact retained for 7 days; restore tests, retention and off-site storage remain your responsibility. Some hosted database connection strings require pooler session mode for pg_dump. Do not expose backup artifacts publicly.

## Testing

- Add a dummy student and test. Confirm result cards and attendance still work.
- Create a draft WhatsApp message. Confirm it opens the correct chat manually. Do not queue for API without verified consent and approved template.
- Test audit insert/update events in Supabase. Confirm a teacher cannot see admin-only audit data.
- Save offline marks while online, disconnect, reload and confirm drafts persist; reconnect and sync. **Sync overwrites** an existing score for the same student and test; do not use with concurrent teachers until conflict resolution is added.
- Generate an Excel snapshot and a printable fee receipt. The receipt shows monthly paid totals, not individual payment transactions.
- Create an appointment and confirm it is saved.

## Limitations and next production tasks

- Rule-based insights and question scaffolds are not a connected generative AI model; teachers must check all academic content.
- There is no automatic PDF/PNG attachment delivery through the Cloud API yet, no event-triggered enqueue job, and no automatic personalized template variables.
- Parent appointment editing/confirmation, approval workflow, queue cancellation, robust retry, delivery reconciliation, opt-out handling, deduplication and concurrency recovery require additional work.
- Backup workflow is optional and needs credentials. Exported Excel files contain private student data; store securely.
- Browser localStorage is not a durable offline database. Drafts can be lost if browser data is cleared.
- Before production, review student-data retention, access controls, consent records, privacy requirements and disaster recovery.

## Development

`npm install` then `npm run dev`; `npm run build` creates `dist`. Run `npm run build` before deploying when possible.
