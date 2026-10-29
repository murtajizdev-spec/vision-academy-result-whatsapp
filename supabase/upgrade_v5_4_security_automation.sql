-- V5.4 SECURITY + COMMUNICATION ADDITIVE MIGRATION.
-- Run AFTER unified, V5.2 and V5.4 migrations on a BACKUP CLONE first.
-- Review existing RLS policies before applying. Parent access becomes published-only.
BEGIN;
DO $$ BEGIN
 IF to_regclass('public.result_approvals') IS NULL OR to_regclass('public.student_guardians') IS NULL OR to_regclass('public.academic_sessions') IS NULL THEN
  RAISE EXCEPTION 'Apply earlier unified/V5.4 migrations first'; END IF;
END $$;
CREATE TABLE IF NOT EXISTS public.teacher_assignments (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),academy_id uuid NOT NULL REFERENCES public.academies(id) ON DELETE CASCADE,
 teacher_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,class_name text NOT NULL,subject text NOT NULL,
 UNIQUE(academy_id,teacher_id,class_name,subject));
CREATE TABLE IF NOT EXISTS public.parent_access (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),academy_id uuid NOT NULL REFERENCES public.academies(id) ON DELETE CASCADE,
 student_id uuid NOT NULL,parent_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 UNIQUE(student_id,parent_user_id),FOREIGN KEY(student_id,academy_id) REFERENCES public.students(id,academy_id) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS public.message_queue (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),academy_id uuid NOT NULL REFERENCES public.academies(id) ON DELETE CASCADE,
 student_id uuid REFERENCES public.students(id) ON DELETE SET NULL,phone text NOT NULL,
 kind text NOT NULL DEFAULT 'announcement' CHECK(kind IN ('result','absence','fee','announcement','monthly')),
 body text NOT NULL DEFAULT '',scheduled_for timestamptz NOT NULL DEFAULT now(),
 status text NOT NULL DEFAULT 'queued' CHECK(status IN ('draft','queued','sending','sent','delivered','read','failed')),
 consent_confirmed boolean NOT NULL DEFAULT false,template_name text NOT NULL DEFAULT '',
 template_language text NOT NULL DEFAULT 'en',template_parameters jsonb NOT NULL DEFAULT '[]'::jsonb,
 provider_message_id text,last_error text,created_at timestamptz NOT NULL DEFAULT now(),sent_at timestamptz);
ALTER TABLE public.message_queue ADD COLUMN IF NOT EXISTS template_language text NOT NULL DEFAULT 'en';
ALTER TABLE public.message_queue ADD COLUMN IF NOT EXISTS template_parameters jsonb NOT NULL DEFAULT '[]'::jsonb;
CREATE INDEX IF NOT EXISTS v54_queue_due ON public.message_queue(status,scheduled_for);
CREATE UNIQUE INDEX IF NOT EXISTS v54_queue_provider_id ON public.message_queue(provider_message_id) WHERE provider_message_id IS NOT NULL;
-- Private helpers run with caller identity but bypass table RLS safely.
CREATE OR REPLACE FUNCTION public.v54_staff(a uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM public.profiles p WHERE p.id=auth.uid() AND p.academy_id=a AND p.role IN ('admin','teacher')) $$;
CREATE OR REPLACE FUNCTION public.v54_parent(a uuid,s uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM public.parent_access l JOIN public.profiles p ON p.id=l.parent_user_id
 WHERE l.parent_user_id=auth.uid() AND l.academy_id=a AND l.student_id=s AND p.role='parent' AND p.academy_id=a) $$;
CREATE OR REPLACE FUNCTION public.v54_published(e uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM public.result_approvals r WHERE r.exam_id=e AND r.status='published') $$;
CREATE OR REPLACE FUNCTION public.v54_can_edit_mark(a uuid,e uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT public.is_academy_admin(a) OR EXISTS(
 SELECT 1 FROM public.profiles p JOIN public.teacher_assignments t ON t.teacher_id=p.id AND t.academy_id=p.academy_id
 JOIN public.exams x ON x.academy_id=t.academy_id AND x.class_name=t.class_name AND x.subject=t.subject
 WHERE p.id=auth.uid() AND p.role='teacher' AND p.academy_id=a AND x.id=e) $$;
-- Grant helper execution to authenticated only.
REVOKE ALL ON FUNCTION public.v54_staff(uuid),public.v54_parent(uuid,uuid),public.v54_published(uuid),public.v54_can_edit_mark(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.v54_staff(uuid),public.v54_parent(uuid,uuid),public.v54_published(uuid),public.v54_can_edit_mark(uuid,uuid) TO authenticated;
-- Restrict additional sensitive tables regardless of old permissive policies.
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['student_guardians','student_custom_fields','academy_ui_settings','report_templates','grading_scales','subject_pass_rules','academy_subjects','academic_sessions','test_series'] LOOP
  EXECUTE format('DROP POLICY IF EXISTS v54_staff_only_read ON public.%I',t);
  EXECUTE format('CREATE POLICY v54_staff_only_read ON public.%I AS RESTRICTIVE FOR SELECT TO authenticated USING (public.v54_staff(academy_id))',t);
 END LOOP;
END $$;
-- RESTRICTIVE policies intersect existing permissive policies, preventing legacy parent data leakage.
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['students','exams','marks','attendance','fees'] LOOP
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
 END LOOP;
END $$;
-- Parent SELECT permissions for deployments that skipped the historical V3 parent migration.
DROP POLICY IF EXISTS v54_parent_students_select ON public.students;
CREATE POLICY v54_parent_students_select ON public.students FOR SELECT TO authenticated USING(public.v54_parent(academy_id,id));
DROP POLICY IF EXISTS v54_parent_marks_select ON public.marks;
CREATE POLICY v54_parent_marks_select ON public.marks FOR SELECT TO authenticated USING(public.v54_parent(academy_id,student_id) AND public.v54_published(exam_id));
DROP POLICY IF EXISTS v54_parent_exams_select ON public.exams;
CREATE POLICY v54_parent_exams_select ON public.exams FOR SELECT TO authenticated USING(public.v54_published(id) AND EXISTS
 (SELECT 1 FROM public.parent_access l JOIN public.students s ON s.id=l.student_id WHERE l.academy_id=exams.academy_id AND s.class_name=exams.class_name AND public.v54_parent(l.academy_id,l.student_id)));
DROP POLICY IF EXISTS v54_parent_attendance_select ON public.attendance;
CREATE POLICY v54_parent_attendance_select ON public.attendance FOR SELECT TO authenticated USING(public.v54_parent(academy_id,student_id));
DROP POLICY IF EXISTS v54_student_read_guard ON public.students;
CREATE POLICY v54_student_read_guard ON public.students AS RESTRICTIVE FOR SELECT TO authenticated USING
 (public.v54_staff(academy_id) OR public.v54_parent(academy_id,id));
DROP POLICY IF EXISTS v54_exam_read_guard ON public.exams;
CREATE POLICY v54_exam_read_guard ON public.exams AS RESTRICTIVE FOR SELECT TO authenticated USING
 (public.v54_staff(academy_id) OR (public.v54_published(id) AND EXISTS
 (SELECT 1 FROM public.parent_access l JOIN public.students s ON s.id=l.student_id
 WHERE l.academy_id=exams.academy_id AND s.class_name=exams.class_name AND public.v54_parent(l.academy_id,l.student_id))));
DROP POLICY IF EXISTS v54_marks_read_guard ON public.marks;
CREATE POLICY v54_marks_read_guard ON public.marks AS RESTRICTIVE FOR SELECT TO authenticated USING
 (public.v54_staff(academy_id) OR (public.v54_parent(academy_id,student_id) AND public.v54_published(exam_id)));
DROP POLICY IF EXISTS v54_attendance_read_guard ON public.attendance;
CREATE POLICY v54_attendance_read_guard ON public.attendance AS RESTRICTIVE FOR SELECT TO authenticated USING
 (public.v54_staff(academy_id) OR public.v54_parent(academy_id,student_id));
DROP POLICY IF EXISTS v54_fees_read_guard ON public.fees;
CREATE POLICY v54_fees_read_guard ON public.fees AS RESTRICTIVE FOR SELECT TO authenticated USING(public.v54_staff(academy_id));
-- Prevent teachers from editing unrelated subjects even if older permissive policies allow them.
DROP POLICY IF EXISTS v54_marks_insert_guard ON public.marks;
CREATE POLICY v54_marks_insert_guard ON public.marks AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK
 (public.v54_can_edit_mark(academy_id,exam_id));
DROP POLICY IF EXISTS v54_marks_update_guard ON public.marks;
CREATE POLICY v54_marks_update_guard ON public.marks AS RESTRICTIVE FOR UPDATE TO authenticated USING
 (public.v54_can_edit_mark(academy_id,exam_id)) WITH CHECK(public.v54_can_edit_mark(academy_id,exam_id));
DROP POLICY IF EXISTS v54_marks_delete_guard ON public.marks;
CREATE POLICY v54_marks_delete_guard ON public.marks AS RESTRICTIVE FOR DELETE TO authenticated USING
 (public.is_academy_admin(academy_id));
DROP POLICY IF EXISTS v54_section_insert_guard ON public.mark_sections;
CREATE POLICY v54_section_insert_guard ON public.mark_sections AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK
 (public.v54_can_edit_mark(academy_id,exam_id));
DROP POLICY IF EXISTS v54_section_update_guard ON public.mark_sections;
CREATE POLICY v54_section_update_guard ON public.mark_sections AS RESTRICTIVE FOR UPDATE TO authenticated USING
 (public.v54_can_edit_mark(academy_id,exam_id)) WITH CHECK(public.v54_can_edit_mark(academy_id,exam_id));
-- Validate assigned account roles and academy ownership, including service-role writes.
CREATE OR REPLACE FUNCTION public.v54_guard_access() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
DECLARE wanted text; uid uuid;
BEGIN
 IF TG_TABLE_NAME='teacher_assignments' THEN wanted:='teacher';uid:=NEW.teacher_id;
 ELSE wanted:='parent';uid:=NEW.parent_user_id; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.profiles p WHERE p.id=uid AND p.academy_id=NEW.academy_id AND p.role=wanted) THEN
  RAISE EXCEPTION 'Linked user must be a % in the same academy',wanted;
 END IF;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS v54_teacher_role_guard ON public.teacher_assignments;
CREATE TRIGGER v54_teacher_role_guard BEFORE INSERT OR UPDATE ON public.teacher_assignments FOR EACH ROW EXECUTE FUNCTION public.v54_guard_access();
DROP TRIGGER IF EXISTS v54_parent_role_guard ON public.parent_access;
CREATE TRIGGER v54_parent_role_guard BEFORE INSERT OR UPDATE ON public.parent_access FOR EACH ROW EXECUTE FUNCTION public.v54_guard_access();
-- Teacher assignment and parent linkage: admin-managed only.
ALTER TABLE public.teacher_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parent_access ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS v54_teacher_select ON public.teacher_assignments;
CREATE POLICY v54_teacher_select ON public.teacher_assignments FOR SELECT TO authenticated USING
 (public.is_academy_admin(academy_id) OR teacher_id=auth.uid());
DROP POLICY IF EXISTS v54_teacher_admin ON public.teacher_assignments;
CREATE POLICY v54_teacher_admin ON public.teacher_assignments FOR ALL TO authenticated USING
 (public.is_academy_admin(academy_id)) WITH CHECK(public.is_academy_admin(academy_id));
DROP POLICY IF EXISTS v54_parent_access_select ON public.parent_access;
CREATE POLICY v54_parent_access_select ON public.parent_access FOR SELECT TO authenticated USING
 (public.is_academy_admin(academy_id) OR parent_user_id=auth.uid());
DROP POLICY IF EXISTS v54_parent_access_admin ON public.parent_access;
CREATE POLICY v54_parent_access_admin ON public.parent_access FOR ALL TO authenticated USING
 (public.is_academy_admin(academy_id)) WITH CHECK(public.is_academy_admin(academy_id));
GRANT SELECT,INSERT,UPDATE,DELETE ON public.teacher_assignments,public.parent_access TO authenticated;
-- Message queue only admins can create/edit; only service-role cron changes delivery states.
ALTER TABLE public.message_queue ENABLE ROW LEVEL SECURITY;
DO $$ DECLARE pol record; BEGIN FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='message_queue' LOOP
 EXECUTE format('DROP POLICY IF EXISTS %I ON public.message_queue',pol.policyname); END LOOP; END $$;
CREATE POLICY v54_message_select ON public.message_queue FOR SELECT TO authenticated USING(public.is_academy_admin(academy_id));
CREATE POLICY v54_message_insert ON public.message_queue FOR INSERT TO authenticated WITH CHECK
 (public.is_academy_admin(academy_id) AND status IN ('draft','queued') AND consent_confirmed=true);
CREATE POLICY v54_message_update ON public.message_queue FOR UPDATE TO authenticated USING
 (public.is_academy_admin(academy_id) AND status IN ('draft','queued','failed')) WITH CHECK(public.is_academy_admin(academy_id));
CREATE POLICY v54_message_delete ON public.message_queue FOR DELETE TO authenticated USING(public.is_academy_admin(academy_id) AND status='draft');
GRANT SELECT,INSERT,UPDATE,DELETE ON public.message_queue TO authenticated;
-- Immutable ownership + delivery status for browser clients; service role bypasses.
CREATE OR REPLACE FUNCTION public.v54_queue_guard() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF auth.role()='authenticated' AND TG_OP='UPDATE' THEN
  IF NEW.status NOT IN ('draft','queued') OR OLD.status NOT IN ('draft','queued','failed') THEN RAISE EXCEPTION 'Delivery status is server managed'; END IF;
  IF NEW.academy_id<>OLD.academy_id OR NEW.student_id IS DISTINCT FROM OLD.student_id OR NEW.phone<>OLD.phone
   OR NEW.template_name<>OLD.template_name THEN RAISE EXCEPTION 'Recipient/template cannot change'; END IF;
 END IF;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS guard_message_queue ON public.message_queue;
DROP TRIGGER IF EXISTS v54_queue_guard ON public.message_queue;
CREATE TRIGGER v54_queue_guard BEFORE UPDATE ON public.message_queue FOR EACH ROW EXECUTE FUNCTION public.v54_queue_guard();
-- Existing unified audit trigger logs marks; add teacher assignment and parent access audit.
CREATE OR REPLACE FUNCTION public.v54_access_audit() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r jsonb; a uuid;
BEGIN
 r:=CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
 a:=(r->>'academy_id')::uuid;
 INSERT INTO public.unified_change_history(academy_id,entity_type,entity_id,action,actor_id,old_data,new_data)
 VALUES(a,TG_TABLE_NAME,(r->>'id')::uuid,TG_OP,CASE WHEN auth.role()='authenticated' THEN auth.uid() ELSE NULL END,
 CASE WHEN TG_OP IN ('UPDATE','DELETE') THEN to_jsonb(OLD) ELSE NULL END,
 CASE WHEN TG_OP IN ('UPDATE','INSERT') THEN to_jsonb(NEW) ELSE NULL END);
 RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END $$;
DROP TRIGGER IF EXISTS v54_assignment_audit ON public.teacher_assignments;
CREATE TRIGGER v54_assignment_audit AFTER INSERT OR UPDATE OR DELETE ON public.teacher_assignments FOR EACH ROW EXECUTE FUNCTION public.v54_access_audit();
DROP TRIGGER IF EXISTS v54_parent_audit ON public.parent_access;
CREATE TRIGGER v54_parent_audit AFTER INSERT OR UPDATE OR DELETE ON public.parent_access FOR EACH ROW EXECUTE FUNCTION public.v54_access_audit();
-- Audit is private to admins; existing broad select policy is replaced.
DROP POLICY IF EXISTS unified_read ON public.unified_change_history;
CREATE POLICY v54_audit_admin_read ON public.unified_change_history FOR SELECT TO authenticated USING(public.is_academy_admin(academy_id));
COMMIT;
