-- V5.4 additive migration. Apply only after the unified and V5.2 migrations.
-- Run on a backup/staging database first. Does not alter old student or marks records.
BEGIN;
DO $$ BEGIN
 IF to_regclass('public.academies') IS NULL OR to_regclass('public.test_series') IS NULL THEN
  RAISE EXCEPTION 'Existing unified and V5.2 schema required';
 END IF;
 IF to_regprocedure('public.my_academy()') IS NULL OR to_regprocedure('public.is_academy_admin(uuid)') IS NULL THEN
  RAISE EXCEPTION 'Academy security functions are missing';
 END IF;
END $$;
CREATE TABLE IF NOT EXISTS public.academic_sessions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 academy_id uuid NOT NULL REFERENCES public.academies(id) ON DELETE CASCADE,
 name text NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 60),
 start_date date NOT NULL,
 end_date date NOT NULL,
 status text NOT NULL DEFAULT 'planned' CHECK (status IN ('planned','active','archived')),
 created_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT session_dates_valid CHECK (end_date >= start_date),
 UNIQUE(academy_id,name)
);
CREATE INDEX IF NOT EXISTS academic_sessions_academy_idx ON public.academic_sessions(academy_id,start_date DESC);
ALTER TABLE public.academic_sessions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS academic_sessions_select ON public.academic_sessions;
CREATE POLICY academic_sessions_select ON public.academic_sessions FOR SELECT TO authenticated USING (academy_id=public.my_academy());
DROP POLICY IF EXISTS academic_sessions_insert ON public.academic_sessions;
CREATE POLICY academic_sessions_insert ON public.academic_sessions FOR INSERT TO authenticated WITH CHECK (public.is_academy_admin(academy_id));
DROP POLICY IF EXISTS academic_sessions_update ON public.academic_sessions;
CREATE POLICY academic_sessions_update ON public.academic_sessions FOR UPDATE TO authenticated USING (public.is_academy_admin(academy_id)) WITH CHECK (public.is_academy_admin(academy_id));
DROP POLICY IF EXISTS academic_sessions_delete ON public.academic_sessions;
CREATE POLICY academic_sessions_delete ON public.academic_sessions FOR DELETE TO authenticated USING (public.is_academy_admin(academy_id));
GRANT SELECT,INSERT,UPDATE,DELETE ON public.academic_sessions TO authenticated;
-- Optional session association. Existing records remain valid with NULL.
ALTER TABLE public.test_series ADD COLUMN IF NOT EXISTS academic_session_id uuid REFERENCES public.academic_sessions(id) ON DELETE SET NULL;
ALTER TABLE public.exams ADD COLUMN IF NOT EXISTS academic_session_id uuid REFERENCES public.academic_sessions(id) ON DELETE SET NULL;
-- Prevent attaching another academy's session to an exam or series.
CREATE OR REPLACE FUNCTION public.v54_guard_academic_session() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF NEW.academic_session_id IS NOT NULL AND NOT EXISTS (
  SELECT 1 FROM public.academic_sessions s WHERE s.id=NEW.academic_session_id AND s.academy_id=NEW.academy_id
 ) THEN RAISE EXCEPTION 'Academic session belongs to a different academy'; END IF;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS v54_series_session_guard ON public.test_series;
CREATE TRIGGER v54_series_session_guard BEFORE INSERT OR UPDATE OF academic_session_id,academy_id ON public.test_series FOR EACH ROW EXECUTE FUNCTION public.v54_guard_academic_session();
DROP TRIGGER IF EXISTS v54_exams_session_guard ON public.exams;
CREATE TRIGGER v54_exams_session_guard BEFORE INSERT OR UPDATE OF academic_session_id,academy_id ON public.exams FOR EACH ROW EXECUTE FUNCTION public.v54_guard_academic_session();
COMMIT;
