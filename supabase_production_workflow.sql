-- Production workflow extension for Metal Casting ERP.
-- Adds Molding Person and Melting Person process tracking.

create extension if not exists "pgcrypto";

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.molding_jobs (
  id uuid primary key default gen_random_uuid(),
  order_uuid uuid not null references public.orders(id) on delete cascade,
  molds_required integer not null check (molds_required > 0),
  molds_made integer not null default 0 check (molds_made >= 0),
  consumable_id uuid references public.consumables(id) on delete set null,
  consumable_name text,
  consumable_qty numeric(12, 3) default 0 check (consumable_qty >= 0),
  operator_name text,
  work_date date not null default current_date,
  status text not null default 'Not Started' check (status in ('Not Started', 'In Progress', 'Molds Ready', 'Hold')),
  remarks text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (order_uuid)
);

create table if not exists public.melting_batches (
  id uuid primary key default gen_random_uuid(),
  order_uuid uuid not null references public.orders(id) on delete cascade,
  molding_job_id uuid references public.molding_jobs(id) on delete set null,
  raw_material_id uuid references public.raw_materials(id) on delete set null,
  raw_material_name text,
  raw_material_qty numeric(12, 3) default 0 check (raw_material_qty >= 0),
  consumable_id uuid references public.consumables(id) on delete set null,
  consumable_name text,
  consumable_qty numeric(12, 3) default 0 check (consumable_qty >= 0),
  melt_qty_kg numeric(12, 3) default 0 check (melt_qty_kg >= 0),
  pour_qty_kg numeric(12, 3) default 0 check (pour_qty_kg >= 0),
  furnace_no text,
  heat_no text unique,
  operator_name text,
  melting_date date not null default current_date,
  status text not null default 'Pending' check (status in ('Pending', 'Melting', 'Ready for Pouring', 'Poured', 'Hold')),
  remarks text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists molding_jobs_set_updated_at on public.molding_jobs;
create trigger molding_jobs_set_updated_at
before update on public.molding_jobs
for each row execute function public.set_updated_at();

drop trigger if exists melting_batches_set_updated_at on public.melting_batches;
create trigger melting_batches_set_updated_at
before update on public.melting_batches
for each row execute function public.set_updated_at();

alter table public.molding_jobs enable row level security;
alter table public.melting_batches enable row level security;

drop policy if exists "Allow anon read molding_jobs" on public.molding_jobs;
create policy "Allow anon read molding_jobs" on public.molding_jobs for select using (true);
drop policy if exists "Allow anon write molding_jobs" on public.molding_jobs;
create policy "Allow anon write molding_jobs" on public.molding_jobs for all using (true) with check (true);

drop policy if exists "Allow anon read melting_batches" on public.melting_batches;
create policy "Allow anon read melting_batches" on public.melting_batches for select using (true);
drop policy if exists "Allow anon write melting_batches" on public.melting_batches;
create policy "Allow anon write melting_batches" on public.melting_batches for all using (true) with check (true);
