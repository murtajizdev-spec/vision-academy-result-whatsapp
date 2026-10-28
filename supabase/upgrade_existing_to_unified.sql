-- UNIFIED RELEASE • direct additive migration for the user's existing Supabase schema.
-- Does not run or require the V2→V3 or V3→V4 migrations.
-- Existing academies, profiles, students, exams, marks, attendance, fees and SLOs remain intact.
-- Run against a staging clone first. Take a database backup before production.
BEGIN;
DO $$ BEGIN
 IF to_regclass('public.academies') IS NULL OR to_regclass('public.students') IS NULL OR to_regclass('public.exams') IS NULL OR to_regclass('public.marks') IS NULL THEN
   RAISE EXCEPTION 'Existing academy/student/exam/marks tables missing: do not apply'; END IF;
 IF to_regprocedure('public.my_academy()') IS NULL OR to_regprocedure('public.is_academy_admin(uuid)') IS NULL THEN
   RAISE EXCEPTION 'Existing academy authorization functions missing: do not apply'; END IF;
END $$;
-- Composite unique keys needed to enforce academy ownership through foreign keys.
CREATE UNIQUE INDEX IF NOT EXISTS unified_student_academy_id ON public.students(id,academy_id);
CREATE UNIQUE INDEX IF NOT EXISTS unified_exam_academy_id ON public.exams(id,academy_id);
CREATE TABLE IF NOT EXISTS public.student_guardians (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),academy_id uuid NOT NULL REFERENCES public.academies(id) ON DELETE CASCADE,
 student_id uuid NOT NULL,name text NOT NULL,relationship text NOT NULL DEFAULT 'Guardian',phone text NOT NULL DEFAULT '',
 whatsapp_opt_in boolean NOT NULL DEFAULT false,created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(student_id,academy_id) REFERENCES public.students(id,academy_id) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS public.exam_configs (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),academy_id uuid NOT NULL REFERENCES public.academies(id) ON DELETE CASCADE,
 exam_id uuid NOT NULL UNIQUE,mcq_max numeric NOT NULL DEFAULT 0 CHECK(mcq_max>=0),
 short_max numeric NOT NULL DEFAULT 0 CHECK(short_max>=0),long_max numeric NOT NULL DEFAULT 0 CHECK(long_max>=0),
 practical_max numeric NOT NULL DEFAULT 0 CHECK(practical_max>=0),passing_percentage numeric NOT NULL DEFAULT 40 CHECK(passing_percentage BETWEEN 0 AND 100),
 syllabus text NOT NULL DEFAULT '',created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(exam_id,academy_id) REFERENCES public.exams(id,academy_id) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS public.mark_sections (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),academy_id uuid NOT NULL REFERENCES public.academies(id) ON DELETE CASCADE,
 student_id uuid NOT NULL,exam_id uuid NOT NULL,mcq numeric NOT NULL DEFAULT 0 CHECK(mcq>=0),
 short numeric NOT NULL DEFAULT 0 CHECK(short>=0),long numeric NOT NULL DEFAULT 0 CHECK(long>=0),
 practical numeric NOT NULL DEFAULT 0 CHECK(practical>=0),status text NOT NULL DEFAULT 'present' CHECK(status IN ('present','absent','exempt')),
 updated_at timestamptz NOT NULL DEFAULT now(),UNIQUE(student_id,exam_id),
 FOREIGN KEY(student_id,academy_id) REFERENCES public.students(id,academy_id) ON DELETE CASCADE,
 FOREIGN KEY(exam_id,academy_id) REFERENCES public.exams(id,academy_id) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS public.result_approvals (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),academy_id uuid NOT NULL REFERENCES public.academies(id) ON DELETE CASCADE,
 exam_id uuid NOT NULL UNIQUE,status text NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','submitted','approved','published')),
 reviewed_by uuid REFERENCES auth.users(id),reviewed_at timestamptz,updated_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(exam_id,academy_id) REFERENCES public.exams(id,academy_id) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS public.report_templates (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),academy_id uuid NOT NULL REFERENCES public.academies(id) ON DELETE CASCADE,
 name text NOT NULL,accent_color text NOT NULL DEFAULT '#1d4ed8',footer text NOT NULL DEFAULT '',
 show_position boolean NOT NULL DEFAULT true,created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS public.grading_scales (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),academy_id uuid NOT NULL REFERENCES public.academies(id) ON DELETE CASCADE,
 label text NOT NULL,min_percentage numeric NOT NULL CHECK(min_percentage BETWEEN 0 AND 100),UNIQUE(academy_id,label));
CREATE TABLE IF NOT EXISTS public.subject_pass_rules (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),academy_id uuid NOT NULL REFERENCES public.academies(id) ON DELETE CASCADE,
 class_name text NOT NULL,subject text NOT NULL,pass_percentage numeric NOT NULL DEFAULT 40 CHECK(pass_percentage BETWEEN 0 AND 100),
 updated_at timestamptz NOT NULL DEFAULT now(),UNIQUE(academy_id,class_name,subject));
CREATE TABLE IF NOT EXISTS public.academy_subjects (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),academy_id uuid NOT NULL REFERENCES public.academies(id) ON DELETE CASCADE,
 class_name text NOT NULL,name text NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(academy_id,class_name,name));
CREATE TABLE IF NOT EXISTS public.student_custom_fields (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),academy_id uuid NOT NULL REFERENCES public.academies(id) ON DELETE CASCADE,
 student_id uuid NOT NULL,field_name text NOT NULL,field_value text NOT NULL DEFAULT '',
 FOREIGN KEY(student_id,academy_id) REFERENCES public.students(id,academy_id) ON DELETE CASCADE,
 UNIQUE(academy_id,student_id,field_name));
CREATE TABLE IF NOT EXISTS public.academy_ui_settings (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),academy_id uuid NOT NULL REFERENCES public.academies(id) ON DELETE CASCADE,
 setting_key text NOT NULL,setting_value jsonb NOT NULL DEFAULT '{}'::jsonb,UNIQUE(academy_id,setting_key));
CREATE TABLE IF NOT EXISTS public.unified_change_history (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),academy_id uuid NOT NULL REFERENCES public.academies(id) ON DELETE CASCADE,
 entity_type text NOT NULL,entity_id uuid,action text NOT NULL,actor_id uuid DEFAULT auth.uid(),
 old_data jsonb,new_data jsonb,created_at timestamptz NOT NULL DEFAULT now());
-- Existing RLS permissions: read academy data for members, mutate new configuration only for admins.
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['student_guardians','exam_configs','mark_sections','result_approvals','report_templates','grading_scales','subject_pass_rules','academy_subjects','student_custom_fields','academy_ui_settings','unified_change_history'] LOOP
 EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
 EXECUTE format('DROP POLICY IF EXISTS unified_read ON public.%I',t);
 EXECUTE format('CREATE POLICY unified_read ON public.%I FOR SELECT TO authenticated USING (academy_id=public.my_academy())',t);
 END LOOP;
 FOREACH t IN ARRAY ARRAY['student_guardians','exam_configs','mark_sections','result_approvals','report_templates','grading_scales','subject_pass_rules','academy_subjects','student_custom_fields','academy_ui_settings'] LOOP
 EXECUTE format('DROP POLICY IF EXISTS unified_insert ON public.%I',t);
 EXECUTE format('DROP POLICY IF EXISTS unified_update ON public.%I',t);
 EXECUTE format('DROP POLICY IF EXISTS unified_delete ON public.%I',t);
 EXECUTE format('CREATE POLICY unified_insert ON public.%I FOR INSERT TO authenticated WITH CHECK (academy_id=public.my_academy())',t);
 EXECUTE format('CREATE POLICY unified_update ON public.%I FOR UPDATE TO authenticated USING (academy_id=public.my_academy()) WITH CHECK (academy_id=public.my_academy())',t);
 EXECUTE format('CREATE POLICY unified_delete ON public.%I FOR DELETE TO authenticated USING (public.is_academy_admin(academy_id))',t);
 END LOOP;
END $$;
-- Admin-only settings and approval transitions; teachers may enter draft marks.
CREATE OR REPLACE FUNCTION public.unified_guard_approval() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF NEW.status IN ('approved','published') AND NOT public.is_academy_admin(NEW.academy_id) THEN RAISE EXCEPTION 'Only academy admins can approve or publish'; END IF;
 IF TG_OP='UPDATE' AND OLD.status IN ('approved','published') AND NEW.status<>OLD.status AND NOT public.is_academy_admin(NEW.academy_id) THEN RAISE EXCEPTION 'Only academy admins can reopen results'; END IF;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS unified_guard_approval ON public.result_approvals;
CREATE TRIGGER unified_guard_approval BEFORE INSERT OR UPDATE ON public.result_approvals FOR EACH ROW EXECUTE FUNCTION public.unified_guard_approval();
CREATE OR REPLACE FUNCTION public.unified_guard_marks() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
DECLARE aid uuid; eid uuid; sid uuid; maxscore numeric; section_cfg public.exam_configs%ROWTYPE;
BEGIN
 aid:=COALESCE(NEW.academy_id,OLD.academy_id);eid:=COALESCE(NEW.exam_id,OLD.exam_id);sid:=COALESCE(NEW.student_id,OLD.student_id);
 IF EXISTS(SELECT 1 FROM public.result_approvals a WHERE a.exam_id=eid AND a.academy_id=aid AND a.status IN ('approved','published')) THEN
 RAISE EXCEPTION 'Result locked. Admin must reopen before editing marks'; END IF;
 IF TG_OP<>'DELETE' THEN
 IF NOT EXISTS(SELECT 1 FROM public.students s WHERE s.id=sid AND s.academy_id=aid) THEN RAISE EXCEPTION 'Student does not belong to academy'; END IF;
 SELECT e.max_marks INTO maxscore FROM public.exams e WHERE e.id=eid AND e.academy_id=aid;
 IF maxscore IS NULL THEN RAISE EXCEPTION 'Exam does not belong to academy'; END IF;
 IF TG_TABLE_NAME='marks' THEN
 IF NEW.obtained<0 OR NEW.obtained>maxscore THEN RAISE EXCEPTION 'Marks outside exam range'; END IF;
 ELSE
 SELECT * INTO section_cfg FROM public.exam_configs c WHERE c.exam_id=eid AND c.academy_id=aid;
 IF FOUND AND (NEW.mcq>section_cfg.mcq_max OR NEW.short>section_cfg.short_max OR NEW.long>section_cfg.long_max OR NEW.practical>section_cfg.practical_max) THEN RAISE EXCEPTION 'Section maximum exceeded'; END IF;
 IF NEW.mcq+NEW.short+NEW.long+NEW.practical>maxscore THEN RAISE EXCEPTION 'Exam maximum exceeded'; END IF;
 END IF;
 END IF;
 RETURN COALESCE(NEW,OLD);
END $$;
DROP TRIGGER IF EXISTS unified_marks_guard ON public.marks;
CREATE TRIGGER unified_marks_guard BEFORE INSERT OR UPDATE OR DELETE ON public.marks FOR EACH ROW EXECUTE FUNCTION public.unified_guard_marks();
DROP TRIGGER IF EXISTS unified_sections_guard ON public.mark_sections;
CREATE TRIGGER unified_sections_guard BEFORE INSERT OR UPDATE OR DELETE ON public.mark_sections FOR EACH ROW EXECUTE FUNCTION public.unified_guard_marks();
CREATE OR REPLACE FUNCTION public.unified_audit() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a uuid; record_id uuid;
BEGIN
 a:=COALESCE(NEW.academy_id,OLD.academy_id);record_id:=COALESCE(NEW.id,OLD.id);
 INSERT INTO public.unified_change_history(academy_id,entity_type,entity_id,action,actor_id,old_data,new_data)
 VALUES(a,TG_TABLE_NAME,record_id,TG_OP,auth.uid(),CASE WHEN TG_OP='INSERT' THEN NULL ELSE to_jsonb(OLD) END,CASE WHEN TG_OP='DELETE' THEN NULL ELSE to_jsonb(NEW) END);
 RETURN COALESCE(NEW,OLD);
END $$;
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['students','exams','marks','student_guardians','exam_configs','mark_sections','result_approvals','report_templates','grading_scales','subject_pass_rules','academy_subjects','student_custom_fields','academy_ui_settings'] LOOP
 EXECUTE format('DROP TRIGGER IF EXISTS unified_audit_trigger ON public.%I',t);
 EXECUTE format('CREATE TRIGGER unified_audit_trigger AFTER INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.unified_audit()',t);
 END LOOP;
END $$;
-- Ensure authenticated role can access newly created tables under RLS.
GRANT SELECT,INSERT,UPDATE,DELETE ON public.student_guardians,public.exam_configs,public.mark_sections,public.result_approvals,public.report_templates,public.grading_scales,public.subject_pass_rules,public.academy_subjects,public.student_custom_fields,public.academy_ui_settings TO authenticated;
GRANT SELECT ON public.unified_change_history TO authenticated;
COMMIT;
