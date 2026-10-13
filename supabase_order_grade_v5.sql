-- v5: Grade on orders (Grade 1..7 or a custom value)
alter table public.orders add column if not exists grade text;
notify pgrst, 'reload schema';
