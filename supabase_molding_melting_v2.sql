-- =====================================================================
-- Metal Casting ERP - Step 2: Molding Person + Melting Person workflow
-- Run AFTER supabase_metal_casting_schema.sql (molding_jobs and
-- melting_batches tables must already exist). Safe to run more than once.
-- =====================================================================
--
-- Flow:
--   Order (Pending)
--     -> Molding person creates a molding job for the order (order becomes "In Production")
--     -> Molding person adds daily molding entries: molds made + molding consumables used
--        (molding_jobs.molds_made is auto-summed; status auto: Not Started / In Progress / Molds Ready)
--     -> Melting person sees orders that have molds made, and how many are still available
--     -> Melting person creates a heat (melting batch): raw materials + melting & pouring
--        consumables, melt kg, pour kg, molds poured (cannot exceed molds available)
-- =====================================================================

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------
-- 1. Molding entries (one row per shift/day of work on a molding job)
-- ---------------------------------------------------------------------
create table if not exists public.molding_entries (
  id uuid primary key default gen_random_uuid(),
  molding_job_id uuid not null references public.molding_jobs(id) on delete cascade,
  order_uuid uuid not null references public.orders(id) on delete cascade,
  entry_date date not null default current_date,
  molds_made integer not null check (molds_made > 0),
  operator_name text,
  remarks text,
  created_at timestamptz not null default now()
);
create index if not exists molding_entries_job_idx on public.molding_entries(molding_job_id);

-- Consumables used in a molding entry (Molding & Molding Consumable category)
create table if not exists public.molding_consumable_usage (
  id uuid primary key default gen_random_uuid(),
  molding_entry_id uuid not null references public.molding_entries(id) on delete cascade,
  molding_job_id uuid not null references public.molding_jobs(id) on delete cascade,
  consumable_id uuid references public.consumables(id) on delete set null,
  consumable_name text not null,
  unit_of_measurement text,
  qty numeric(12, 3) not null check (qty > 0),
  created_at timestamptz not null default now()
);
create index if not exists molding_usage_entry_idx on public.molding_consumable_usage(molding_entry_id);
create index if not exists molding_usage_job_idx on public.molding_consumable_usage(molding_job_id);

-- ---------------------------------------------------------------------
-- 2. Melting batches: extra columns
-- ---------------------------------------------------------------------
alter table public.melting_batches add column if not exists molds_poured integer not null default 0;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'melting_batches_molds_poured_check') then
    alter table public.melting_batches add constraint melting_batches_molds_poured_check check (molds_poured >= 0);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'melting_batches_pour_le_melt') then
    alter table public.melting_batches add constraint melting_batches_pour_le_melt
      check (pour_qty_kg is null or melt_qty_kg is null or melt_qty_kg = 0 or pour_qty_kg <= melt_qty_kg) not valid;
  end if;
end $$;

-- Raw materials + melting/pouring consumables used in one heat (multiple lines)
create table if not exists public.melting_material_usage (
  id uuid primary key default gen_random_uuid(),
  melting_batch_id uuid not null references public.melting_batches(id) on delete cascade,
  item_type text not null check (item_type in ('Raw Material', 'Consumable')),
  item_id uuid,
  item_name text not null,
  item_category text,
  unit_of_measurement text,
  qty numeric(12, 3) not null check (qty > 0),
  created_at timestamptz not null default now()
);
create index if not exists melting_usage_batch_idx on public.melting_material_usage(melting_batch_id);

-- ---------------------------------------------------------------------
-- 3. Triggers
-- ---------------------------------------------------------------------

-- 3a. Molding job status is derived from molds_made vs molds_required (unless on Hold)
create or replace function public.molding_job_derive_status()
returns trigger language plpgsql as $$
begin
  if new.status <> 'Hold' then
    new.status := case
      when new.molds_made >= new.molds_required then 'Molds Ready'
      when new.molds_made > 0 then 'In Progress'
      else 'Not Started'
    end;
  end if;
  return new;
end; $$;

drop trigger if exists molding_jobs_derive_status on public.molding_jobs;
create trigger molding_jobs_derive_status
before insert or update on public.molding_jobs
for each row execute function public.molding_job_derive_status();

-- 3b. molds_made = sum of molding entries
create or replace function public.molding_entries_sync_total()
returns trigger language plpgsql as $$
declare
  jid uuid := coalesce(new.molding_job_id, old.molding_job_id);
begin
  update public.molding_jobs
     set molds_made = (select coalesce(sum(molds_made), 0) from public.molding_entries where molding_job_id = jid)
   where id = jid;
  return null;
end; $$;

drop trigger if exists molding_entries_sync on public.molding_entries;
create trigger molding_entries_sync
after insert or update or delete on public.molding_entries
for each row execute function public.molding_entries_sync_total();

-- 3c. Starting a molding job moves a Pending order to In Production
create or replace function public.molding_job_start_order()
returns trigger language plpgsql as $$
begin
  update public.orders set status = 'In Production'
   where id = new.order_uuid and status = 'Pending';
  return new;
end; $$;

drop trigger if exists molding_jobs_start_order on public.molding_jobs;
create trigger molding_jobs_start_order
after insert on public.molding_jobs
for each row execute function public.molding_job_start_order();

-- 3d. Melting batch: auto heat no, link molding job, never pour into more molds than were made
create or replace function public.melting_batch_before_save()
returns trigger language plpgsql as $$
declare
  job_id uuid;
  made integer;
  used integer;
  next_number bigint;
begin
  select id, molds_made into job_id, made from public.molding_jobs where order_uuid = new.order_uuid;

  if new.molding_job_id is null then
    new.molding_job_id := job_id;
  end if;

  select coalesce(sum(molds_poured), 0) into used
    from public.melting_batches
   where order_uuid = new.order_uuid and id <> new.id;

  if new.molds_poured > coalesce(made, 0) - used then
    raise exception 'Only % molds are available for pouring on this order', greatest(coalesce(made, 0) - used, 0);
  end if;

  if new.heat_no is null or new.heat_no = '' then
    select coalesce(max((regexp_match(heat_no, '^HT-([0-9]+)$'))[1]::bigint), 0) + 1
      into next_number
      from public.melting_batches
     where heat_no ~ '^HT-[0-9]+$';
    new.heat_no := 'HT-' || lpad(next_number::text, 6, '0');
  end if;

  return new;
end; $$;

drop trigger if exists melting_batches_before_save on public.melting_batches;
create trigger melting_batches_before_save
before insert or update on public.melting_batches
for each row execute function public.melting_batch_before_save();

-- ---------------------------------------------------------------------
-- 4. RLS (development policies, same pattern as the base schema)
--    Tighten these before production.
-- ---------------------------------------------------------------------
alter table public.molding_entries enable row level security;
alter table public.molding_consumable_usage enable row level security;
alter table public.melting_material_usage enable row level security;

drop policy if exists "Allow anon all molding_entries" on public.molding_entries;
create policy "Allow anon all molding_entries" on public.molding_entries for all using (true) with check (true);

drop policy if exists "Allow anon all molding_consumable_usage" on public.molding_consumable_usage;
create policy "Allow anon all molding_consumable_usage" on public.molding_consumable_usage for all using (true) with check (true);

drop policy if exists "Allow anon all melting_material_usage" on public.melting_material_usage;
create policy "Allow anon all melting_material_usage" on public.melting_material_usage for all using (true) with check (true);
