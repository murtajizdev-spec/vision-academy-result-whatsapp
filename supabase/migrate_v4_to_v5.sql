-- Apply after schema.sql, migrate_v2_to_v3.sql and migrate_v3_to_v4.sql.
-- Run in a staging project first; back up production before applying.
begin;
create table if not exists public.student_guardians (
 id uuid primary key default gen_random_uuid(), academy_id uuid not null references public.academies(id) on delete cascade,
 student_id uuid not null, name text not null, relationship text not null default 'Guardian',
 phone text not null default '', whatsapp_opt_in boolean not null default false,
 created_at timestamptz default now(),
 foreign key(student_id,academy_id) references public.students(id,academy_id) on delete cascade);
create table if not exists public.exam_configs (
 id uuid primary key default gen_random_uuid(), academy_id uuid not null references public.academies(id) on delete cascade,
 exam_id uuid not null unique, mcq_max numeric not null default 0 check(mcq_max>=0),
 short_max numeric not null default 0 check(short_max>=0), long_max numeric not null default 0 check(long_max>=0),
 practical_max numeric not null default 0 check(practical_max>=0),
 passing_percentage numeric not null default 40 check(passing_percentage between 0 and 100),
 syllabus text not null default '', created_at timestamptz default now(),
 foreign key(exam_id,academy_id) references public.exams(id,academy_id) on delete cascade);
create table if not exists public.mark_sections (
 id uuid primary key default gen_random_uuid(), academy_id uuid not null references public.academies(id) on delete cascade,
 student_id uuid not null, exam_id uuid not null,
 mcq numeric not null default 0 check(mcq>=0), short numeric not null default 0 check(short>=0),
 long numeric not null default 0 check(long>=0), practical numeric not null default 0 check(practical>=0),
 status text not null default 'present' check(status in ('present','absent','exempt')),
 updated_at timestamptz not null default now(), unique(student_id,exam_id),
 foreign key(student_id,academy_id) references public.students(id,academy_id) on delete cascade,
 foreign key(exam_id,academy_id) references public.exams(id,academy_id) on delete cascade);
create table if not exists public.result_approvals (
 id uuid primary key default gen_random_uuid(), academy_id uuid not null references public.academies(id) on delete cascade,
 exam_id uuid not null unique, status text not null default 'draft' check(status in ('draft','submitted','approved','published')),
 reviewed_by uuid references auth.users(id), reviewed_at timestamptz, updated_at timestamptz default now(),
 foreign key(exam_id,academy_id) references public.exams(id,academy_id) on delete cascade);
create table if not exists public.report_templates (
 id uuid primary key default gen_random_uuid(), academy_id uuid not null references public.academies(id) on delete cascade,
 name text not null, accent_color text not null default '#1d4ed8', footer text not null default '',
 show_position boolean not null default true, created_at timestamptz default now());
create table if not exists public.grading_scales (
 id uuid primary key default gen_random_uuid(), academy_id uuid not null references public.academies(id) on delete cascade,
 label text not null, min_percentage numeric not null check(min_percentage between 0 and 100),
 unique(academy_id,label));
create or replace function public.v5_validate_sections() returns trigger language plpgsql set search_path=public as $$
declare c public.exam_configs%rowtype; e public.exams%rowtype;
begin
 select * into e from public.exams where id=new.exam_id and academy_id=new.academy_id;
 if not found then raise exception 'Exam not found in academy';end if;
 select * into c from public.exam_configs where exam_id=new.exam_id and academy_id=new.academy_id;
 if found then
  if new.mcq>c.mcq_max or new.short>c.short_max or new.long>c.long_max or new.practical>c.practical_max then
   raise exception 'Section marks exceed section maximum';end if;
 end if;
 if new.mcq+new.short+new.long+new.practical>e.max_marks then raise exception 'Marks exceed exam maximum';end if;
 if exists(select 1 from public.result_approvals where exam_id=new.exam_id and status in ('approved','published')) then
  raise exception 'Result is locked; reopen approval before editing';end if;
 return new;
end$$;
drop trigger if exists v5_check_sections on public.mark_sections;
create trigger v5_check_sections before insert or update on public.mark_sections for each row execute function public.v5_validate_sections();
create or replace function public.v5_approval_guard() returns trigger language plpgsql set search_path=public as $$
begin
 if new.status in ('approved','published') and not public.is_academy_admin(new.academy_id) then
  raise exception 'Only academy admins can approve or publish';end if;
 if TG_OP='UPDATE' and old.status='published' and new.status<>old.status and not public.is_academy_admin(new.academy_id) then
  raise exception 'Only academy admins can reopen published results';end if;
 return new;
end$$;
drop trigger if exists v5_guard_approvals on public.result_approvals;
create trigger v5_guard_approvals before insert or update on public.result_approvals for each row execute function public.v5_approval_guard();
-- RLS; parents have no access to unpublished result metadata.
do $$declare t text;begin foreach t in array array['student_guardians','exam_configs','mark_sections','result_approvals','report_templates','grading_scales'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('create policy v5_staff_read on public.%I for select to authenticated using(public.is_staff(academy_id))',t);
 execute format('create policy v5_staff_insert on public.%I for insert to authenticated with check(public.is_staff(academy_id))',t);
 execute format('create policy v5_staff_update on public.%I for update to authenticated using(public.is_staff(academy_id)) with check(public.is_staff(academy_id))',t);
 end loop;end$$;
-- All edits are recorded in existing V4 activity_audit table.
do $$declare t text;begin foreach t in array array['student_guardians','exam_configs','mark_sections','result_approvals','report_templates','grading_scales'] loop
 execute format('create trigger audit_v5_change after insert or update or delete on public.%I for each row execute function public.audit_v4()',t);
 end loop;end$$;
commit;
