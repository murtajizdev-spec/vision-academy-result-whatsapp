-- Run only AFTER upgrade_existing_to_unified.sql has succeeded.
-- Extends existing exams and academy_subjects; no old-version migrations required.
BEGIN;
DO $$ BEGIN
 IF to_regclass('public.exams') IS NULL OR to_regclass('public.academy_subjects') IS NULL OR to_regclass('public.exam_configs') IS NULL THEN
 RAISE EXCEPTION 'Unified schema missing. Install upgrade_existing_to_unified.sql first.';
 END IF;
 IF to_regprocedure('public.my_academy()') IS NULL OR to_regprocedure('public.is_academy_admin(uuid)') IS NULL THEN
 RAISE EXCEPTION 'Academy security functions are missing; cannot install safely.';
 END IF;
END $$;
CREATE TABLE IF NOT EXISTS public.test_series (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 academy_id uuid NOT NULL REFERENCES public.academies(id) ON DELETE CASCADE,
 name text NOT NULL CHECK(length(trim(name))>0),
 class_name text NOT NULL,
 subject text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.exams ADD COLUMN IF NOT EXISTS series_id uuid REFERENCES public.test_series(id) ON DELETE SET NULL;
ALTER TABLE public.exams ADD COLUMN IF NOT EXISTS series_order integer;
CREATE INDEX IF NOT EXISTS exams_series_id_idx ON public.exams(series_id,series_order);
CREATE INDEX IF NOT EXISTS test_series_academy_idx ON public.test_series(academy_id,class_name,subject);
ALTER TABLE public.test_series ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS series_read ON public.test_series;
CREATE POLICY series_read ON public.test_series FOR SELECT TO authenticated USING (academy_id=public.my_academy());
DROP POLICY IF EXISTS series_insert ON public.test_series;
CREATE POLICY series_insert ON public.test_series FOR INSERT TO authenticated WITH CHECK (academy_id=public.my_academy());
DROP POLICY IF EXISTS series_update ON public.test_series;
CREATE POLICY series_update ON public.test_series FOR UPDATE TO authenticated USING (public.is_academy_admin(academy_id)) WITH CHECK (public.is_academy_admin(academy_id));
DROP POLICY IF EXISTS series_delete ON public.test_series;
CREATE POLICY series_delete ON public.test_series FOR DELETE TO authenticated USING (public.is_academy_admin(academy_id));
GRANT SELECT,INSERT,UPDATE,DELETE ON public.test_series TO authenticated;
-- Validate that an exam cannot be assigned to a series belonging to another academy/class/subject.
CREATE OR REPLACE FUNCTION public.validate_exam_series() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF NEW.series_id IS NOT NULL AND NOT EXISTS (
  SELECT 1 FROM public.test_series s WHERE s.id=NEW.series_id AND s.academy_id=NEW.academy_id AND s.class_name=NEW.class_name AND s.subject=NEW.subject
 ) THEN RAISE EXCEPTION 'Test series must belong to the same academy, class and subject'; END IF;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS validate_exam_series_trigger ON public.exams;
CREATE TRIGGER validate_exam_series_trigger BEFORE INSERT OR UPDATE OF series_id,academy_id,class_name,subject ON public.exams FOR EACH ROW EXECUTE FUNCTION public.validate_exam_series();
COMMIT;
