-- Intentionally idempotent retirement marker: installations that received an
-- earlier 0002 revision still remove the legacy non-atomic RPC here.
drop function if exists public.networking_register_device(text, text, text, text);
