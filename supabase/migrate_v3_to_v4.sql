-- Run ONCE after V2 and V3 migrations. Review in a staging project first.
begin;
create table if not exists public.message_queue (
 id uuid primary key default gen_random_uuid(),academy_id uuid not null references public.academies(id) on delete cascade,
 student_id uuid references public.students(id) on delete set null,phone text not null,kind text not null check(kind in ('result','absence','fee','announcement','monthly')),
 body text not null,scheduled_for timestamptz not null default now(),status text not null default 'draft' check(status in ('draft','queued','sending','sent','delivered','read','failed')),
 consent_confirmed boolean not null default false,template_name text not null default '',provider_message_id text,last_error text,
 created_at timestamptz not null default now(),sent_at timestamptz);
create index if not exists message_due on public.message_queue(status,scheduled_for);
create table if not exists public.parent_appointments (
 id uuid primary key default gen_random_uuid(),academy_id uuid not null references public.academies(id) on delete cascade,
 student_id uuid not null references public.students(id) on delete cascade,starts_at timestamptz not null,topic text not null,
 status text not null default 'requested' check(status in ('requested','confirmed','completed','cancelled')),
 created_at timestamptz not null default now());
create table if not exists public.activity_audit (
 id bigint generated always as identity primary key,academy_id uuid not null references public.academies(id) on delete cascade,
 actor_id uuid,table_name text not null,record_id text,operation text not null,
 before_data jsonb,after_data jsonb,created_at timestamptz not null default now());
create index if not exists audit_academy_created on public.activity_audit(academy_id,created_at desc);
create table if not exists public.backup_runs (
 id uuid primary key default gen_random_uuid(),academy_id uuid not null references public.academies(id) on delete cascade,
 status text not null,notes text default '',created_at timestamptz not null default now());
-- No browser user can edit delivery status to 'sent': updates limited to editable draft/queued states.
create or replace function public.message_queue_guard() returns trigger language plpgsql set search_path=public as $$
begin
 if auth.role()='authenticated' then
  if old.status not in ('draft','queued') or new.status not in ('draft','queued') then raise exception 'Delivery state is server-managed';end if;
  if new.academy_id<>old.academy_id or new.phone<>old.phone or new.body<>old.body or new.student_id is distinct from old.student_id then raise exception 'Recipient and body cannot change';end if;
 end if;
 return new;
end$$;
drop trigger if exists guard_message_queue on public.message_queue;
create trigger guard_message_queue before update on public.message_queue for each row execute function public.message_queue_guard();
-- Audit changes without relying on frontend code.
create or replace function public.audit_v4() returns trigger language plpgsql security definer set search_path=public as $$
declare record_data jsonb; a uuid;
begin
 record_data:=case when TG_OP='DELETE' then to_jsonb(old) else to_jsonb(new) end;
 a:=(record_data->>'academy_id')::uuid;
 insert into public.activity_audit(academy_id,actor_id,table_name,record_id,operation,before_data,after_data)
 values(a,auth.uid(),TG_TABLE_NAME,record_data->>'id',TG_OP,case when TG_OP in ('UPDATE','DELETE') then to_jsonb(old) else null end,case when TG_OP in ('INSERT','UPDATE') then to_jsonb(new) else null end);
 return case when TG_OP='DELETE' then old else new end;
end$$;
do $$declare t text;begin foreach t in array array['students','exams','marks','attendance','fees','message_queue','parent_appointments'] loop
 execute format('drop trigger if exists audit_v4_change on public.%I',t);
 execute format('create trigger audit_v4_change after insert or update or delete on public.%I for each row execute function public.audit_v4()',t);
 end loop;end$$;
-- Server-enforced RLS for V4 data.
do $$declare t text;begin foreach t in array array['message_queue','parent_appointments','activity_audit','backup_runs'] loop
 execute format('alter table public.%I enable row level security',t);
 end loop;end$$;
create policy v4_message_read on public.message_queue for select to authenticated using(public.is_staff(academy_id));
create policy v4_message_insert on public.message_queue for insert to authenticated with check(public.is_staff(academy_id) and status='draft' and consent_confirmed=false);
create policy v4_message_update on public.message_queue for update to authenticated using(public.is_academy_admin(academy_id)) with check(public.is_academy_admin(academy_id));
create policy v4_appointments_read on public.parent_appointments for select to authenticated using(public.is_staff(academy_id) or public.is_linked_parent(academy_id,student_id));
create policy v4_appointments_insert on public.parent_appointments for insert to authenticated with check(public.is_staff(academy_id) or public.is_linked_parent(academy_id,student_id));
create policy v4_audit_read on public.activity_audit for select to authenticated using(public.is_academy_admin(academy_id));
create policy v4_backup_read on public.backup_runs for select to authenticated using(public.is_academy_admin(academy_id));
-- No authenticated insert/update/delete policies for audit or backup tables.
commit;
