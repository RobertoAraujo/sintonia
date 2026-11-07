-- Enable REPLICA IDENTITY FULL on user_profiles so Supabase Realtime
-- broadcasts all column values (including last_seen) on UPDATE events.
-- Without this, the newRecord payload only contains the primary key.
ALTER TABLE public.user_profiles REPLICA IDENTITY FULL;
