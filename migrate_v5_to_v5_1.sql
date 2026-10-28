-- V5.1 additive migration. First install V3, V4 and V5 in that order.
-- Transactional; refuses to run if prerequisites are missing.
begin;
do $$begin
 if to_regprocedure('public.is_staff(uuid)') is null then raise exception 'Missing V3: run migrate_v2_to_v3.sql after checking existing database state'; end if;
 if to_regprocedure('public.audit_v4()') is null then raise exception 'Missing V4: run migrate_v3_to_v4.sql after checking existing database state'; end if;
 if to_regclass('public.exam_configs') is null then raise exception 'Missing V5: run migrate_v4_to_v5.sql'; end if;
end$$;
create table if not exists public.subject_pass_rules (
 id uuid primary key default gen_random_uuid(),academy_id uuid not null references public.academies(id) on delete cascade,
 class_name text not null,subject text not null,pass_percentage numeric not null default 40 check(pass_percentage between 0 and 100),
 updated_at timestamptz not null default now(),unique(academy_id,class_name,subject));
create table if not exists public.academy_subjects (
 id uuid primary key default gen_random_uuid(),academy_id uuid not null references public.academies(id) on delete cascade,
 class_name text not null,name text not null,created_at timestamptz not null default now(),unique(academy_id,class_name,name));
create table if not exists public.student_custom_fields (
 id uuid primary key default gen_random_uuid(),academy_id uuid not null references public.academies(id) on delete cascade,
 student_id uuid not null,field_name text not null,field_value text not null default '',
 foreign key(student_id,academy_id) references public.students(id,academy_id) on delete cascade,
 unique(academy_id,student_id,field_name));
create table if not exists public.academy_ui_settings (
 id uuid primary key default gen_random_uuid(),academy_id uuid not null references public.academies(id) on delete cascade,
 setting_key text not null,setting_value jsonb not null default '{}'::jsonb,
 unique(academy_id,setting_key));
do $$declare t text;begin
 foreach t in array array['subject_pass_rules','academy_subjects','student_custom_fields','academy_ui_settings'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('drop policy if exists v51_staff_read on public.%I',t);
  execute format('drop policy if exists v51_staff_insert on public.%I',t);
  execute format('drop policy if exists v51_staff_update on public.%I',t);
  execute format('drop policy if exists v51_staff_delete on public.%I',t);
  execute format('create policy v51_staff_read on public.%I for select to authenticated using (public.is_staff(academy_id))',t);
  execute format('create policy v51_staff_insert on public.%I for insert to authenticated with check (public.is_academy_admin(academy_id))',t);
  execute format('create policy v51_staff_update on public.%I for update to authenticated using (public.is_academy_admin(academy_id)) with check (public.is_academy_admin(academy_id))',t);
  execute format('create policy v51_staff_delete on public.%I for delete to authenticated using (public.is_academy_admin(academy_id))',t);
  execute format('drop trigger if exists audit_v51_change on public.%I',t);
  execute format('create trigger audit_v51_change after insert or update or delete on public.%I for each row execute function public.audit_v4()',t);
 end loop;
end$$;
commit;
