-- =====================================================================
-- Metal Casting ERP - Step 3: Heat Treatment -> Fettling & Finishing
--                              -> Stock Inventory -> Dispatch
-- Run AFTER supabase_metal_casting_schema.sql and supabase_molding_melting_v2.sql.
-- Safe to run more than once.
-- =====================================================================
--
-- Flow (1 mold = 1 casting):
--   Melting heat marked "Poured"  -> castings wait for Heat Treatment
--   HT batch (furnace load)       -> each order/product line has its own
--                                    time_in and time_out (some come out early)
--   Unloaded (time_out set)       -> castings wait for Fettling & Finishing
--   Fettling entry (OK / Rejected + consumables) -> OK pieces go to stock
--   Dispatch (challan, vehicle)   -> reduces stock; order auto "Delivered"
--                                    when dispatched qty >= order qty
-- =====================================================================

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------
-- 0. New consumable categories
-- ---------------------------------------------------------------------
alter table public.consumables drop constraint if exists consumables_category_check;
alter table public.consumables add constraint consumables_category_check
  check (category in ('Melting & Pouring Consumable', 'Molding & Molding Consumable',
                      'Heat Treatment Consumable', 'Fettling & Finishing Consumable'));

insert into public.consumables (category, consumable_name, consumable_code, unit_of_measurement, description, status)
values
  ('Heat Treatment Consumable', 'Oil', 'CON-HT-OIL', 'KG', 'Furnace fuel / quenching oil.', 'Active'),
  ('Heat Treatment Consumable', 'Gas', 'CON-HT-GAS', 'KG', 'Furnace gas.', 'Active'),
  ('Fettling & Finishing Consumable', '16" Wheel', 'CON-FF-WHEEL16', 'Pcs', 'Grinding wheel 16 inch.', 'Active'),
  ('Fettling & Finishing Consumable', '9" Disc', 'CON-FF-DISC9', 'Pcs', 'Grinding disc 9 inch.', 'Active'),
  ('Fettling & Finishing Consumable', '7" Disc', 'CON-FF-DISC7', 'Pcs', 'Grinding disc 7 inch.', 'Active'),
  ('Fettling & Finishing Consumable', '4" Disc', 'CON-FF-DISC4', 'Pcs', 'Grinding disc 4 inch.', 'Active'),
  ('Fettling & Finishing Consumable', 'MS Welding Rod', 'CON-FF-MSROD', 'KG', 'Mild steel welding rod.', 'Active'),
  ('Fettling & Finishing Consumable', 'Mn Welding Rod', 'CON-FF-MNROD', 'KG', 'Manganese welding rod.', 'Active'),
  ('Fettling & Finishing Consumable', 'M-Seal', 'CON-FF-MSEAL', 'KG', 'Sealing compound.', 'Active'),
  ('Fettling & Finishing Consumable', 'Enamel Paint', 'CON-FF-ENAMEL', 'Litre', 'Finishing paint.', 'Active'),
  ('Fettling & Finishing Consumable', 'Red Oxide', 'CON-FF-REDOX', 'Litre', 'Primer.', 'Active'),
  ('Fettling & Finishing Consumable', 'Chisel / Clipper', 'CON-FF-CHISEL', 'Pcs', 'Fettling hand tools.', 'Active')
on conflict (consumable_code) do nothing;

-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------
create table if not exists public.ht_batches (
  id uuid primary key default gen_random_uuid(),
  batch_no text unique,
  furnace_no text,
  ht_date date not null default current_date,
  process_type text,
  temperature_c numeric(8, 2),
  soak_hours numeric(6, 2),
  operator_name text,
  status text not null default 'In Furnace' check (status in ('In Furnace', 'Completed')),
  remarks text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- One row per order/product loaded in a batch, with its own In / Out time
create table if not exists public.ht_items (
  id uuid primary key default gen_random_uuid(),
  ht_batch_id uuid not null references public.ht_batches(id) on delete cascade,
  order_uuid uuid not null references public.orders(id) on delete cascade,
  qty integer not null check (qty > 0),
  time_in timestamptz not null default now(),
  time_out timestamptz,
  remarks text,
  created_at timestamptz not null default now(),
  constraint ht_items_out_after_in check (time_out is null or time_out >= time_in)
);
create index if not exists ht_items_batch_idx on public.ht_items(ht_batch_id);
create index if not exists ht_items_order_idx on public.ht_items(order_uuid);

create table if not exists public.ht_consumable_usage (
  id uuid primary key default gen_random_uuid(),
  ht_batch_id uuid not null references public.ht_batches(id) on delete cascade,
  consumable_id uuid references public.consumables(id) on delete set null,
  consumable_name text not null,
  unit_of_measurement text,
  qty numeric(12, 3) not null check (qty > 0),
  created_at timestamptz not null default now()
);
create index if not exists ht_usage_batch_idx on public.ht_consumable_usage(ht_batch_id);

create table if not exists public.fettling_entries (
  id uuid primary key default gen_random_uuid(),
  order_uuid uuid not null references public.orders(id) on delete cascade,
  entry_date date not null default current_date,
  qty_ok integer not null default 0 check (qty_ok >= 0),
  qty_rejected integer not null default 0 check (qty_rejected >= 0),
  operator_name text,
  remarks text,
  created_at timestamptz not null default now(),
  constraint fettling_entries_qty_positive check (qty_ok + qty_rejected > 0)
);
create index if not exists fettling_entries_order_idx on public.fettling_entries(order_uuid);

create table if not exists public.fettling_consumable_usage (
  id uuid primary key default gen_random_uuid(),
  fettling_entry_id uuid not null references public.fettling_entries(id) on delete cascade,
  order_uuid uuid not null references public.orders(id) on delete cascade,
  consumable_id uuid references public.consumables(id) on delete set null,
  consumable_name text not null,
  unit_of_measurement text,
  qty numeric(12, 3) not null check (qty > 0),
  created_at timestamptz not null default now()
);
create index if not exists fettling_usage_entry_idx on public.fettling_consumable_usage(fettling_entry_id);

create table if not exists public.dispatches (
  id uuid primary key default gen_random_uuid(),
  dispatch_no text unique,
  order_uuid uuid not null references public.orders(id) on delete cascade,
  dispatch_date date not null default current_date,
  qty integer not null check (qty > 0),
  challan_no text,
  invoice_no text,
  vehicle_no text,
  transporter text,
  driver_name text,
  driver_mobile text,
  remarks text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists dispatches_order_idx on public.dispatches(order_uuid);

drop trigger if exists ht_batches_set_updated_at on public.ht_batches;
create trigger ht_batches_set_updated_at before update on public.ht_batches
for each row execute function public.set_updated_at();

drop trigger if exists dispatches_set_updated_at on public.dispatches;
create trigger dispatches_set_updated_at before update on public.dispatches
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------
-- 2. Helper quantities per order
-- ---------------------------------------------------------------------
create or replace function public.order_poured_qty(oid uuid) returns integer language sql stable as $$
  select coalesce(sum(molds_poured), 0)::int from public.melting_batches where order_uuid = oid and status = 'Poured';
$$;
create or replace function public.order_ht_done_qty(oid uuid) returns integer language sql stable as $$
  select coalesce(sum(qty), 0)::int from public.ht_items where order_uuid = oid and time_out is not null;
$$;
create or replace function public.order_fettled_qty(oid uuid) returns integer language sql stable as $$
  select coalesce(sum(qty_ok + qty_rejected), 0)::int from public.fettling_entries where order_uuid = oid;
$$;
create or replace function public.order_finished_ok_qty(oid uuid) returns integer language sql stable as $$
  select coalesce(sum(qty_ok), 0)::int from public.fettling_entries where order_uuid = oid;
$$;
create or replace function public.order_dispatched_qty(oid uuid) returns integer language sql stable as $$
  select coalesce(sum(qty), 0)::int from public.dispatches where order_uuid = oid;
$$;

-- Order status follows finishing + dispatch
create or replace function public.sync_order_flow_status(oid uuid) returns void language plpgsql as $$
declare
  q int; st text; ok int; sent int;
begin
  select quantity, status into q, st from public.orders where id = oid;
  if st is null or st = 'Cancelled' then return; end if;
  ok := public.order_finished_ok_qty(oid);
  sent := public.order_dispatched_qty(oid);
  if sent >= q then
    update public.orders set status = 'Delivered' where id = oid and status <> 'Delivered';
  elsif ok >= q then
    update public.orders set status = 'Completed' where id = oid and status <> 'Completed';
  elsif st in ('Completed', 'Delivered') then
    update public.orders set status = 'In Production' where id = oid;
  end if;
end; $$;

-- ---------------------------------------------------------------------
-- 3. Triggers - Heat Treatment
-- ---------------------------------------------------------------------
create or replace function public.ht_batch_before_save() returns trigger language plpgsql as $$
declare next_number bigint;
begin
  if new.batch_no is null or new.batch_no = '' then
    select coalesce(max((regexp_match(batch_no, '^HTB-([0-9]+)$'))[1]::bigint), 0) + 1
      into next_number from public.ht_batches where batch_no ~ '^HTB-[0-9]+$';
    new.batch_no := 'HTB-' || lpad(next_number::text, 6, '0');
  end if;
  return new;
end; $$;
drop trigger if exists ht_batches_before_save on public.ht_batches;
create trigger ht_batches_before_save before insert on public.ht_batches
for each row execute function public.ht_batch_before_save();

-- Never load more castings than poured; never undo HT for pieces already fettled
create or replace function public.ht_items_guard() returns trigger language plpgsql as $$
declare
  oid uuid := coalesce(new.order_uuid, old.order_uuid);
  rid uuid := coalesce(new.id, old.id);
  loaded int; done int;
begin
  -- order itself being deleted (cascade): nothing to protect
  if tg_op = 'DELETE' and not exists (select 1 from public.orders where id = oid) then return old; end if;
  if tg_op in ('INSERT', 'UPDATE') then
    select coalesce(sum(qty), 0) into loaded from public.ht_items where order_uuid = oid and id <> rid;
    if new.qty > public.order_poured_qty(oid) - loaded then
      raise exception 'Only % poured castings are waiting for heat treatment on this order',
        greatest(public.order_poured_qty(oid) - loaded, 0);
    end if;
  end if;
  select coalesce(sum(qty), 0) into done from public.ht_items where order_uuid = oid and id <> rid and time_out is not null;
  if tg_op <> 'DELETE' and new.time_out is not null then done := done + new.qty; end if;
  if done < public.order_fettled_qty(oid) then
    raise exception 'Cannot change: % pieces of this order are already fettled', public.order_fettled_qty(oid);
  end if;
  return coalesce(new, old);
end; $$;
drop trigger if exists ht_items_guard on public.ht_items;
create trigger ht_items_guard before insert or update or delete on public.ht_items
for each row execute function public.ht_items_guard();

-- Batch status: Completed when every item has an out time
create or replace function public.ht_items_sync_batch() returns trigger language plpgsql as $$
declare bid uuid := coalesce(new.ht_batch_id, old.ht_batch_id);
begin
  update public.ht_batches b
     set status = case
       when exists (select 1 from public.ht_items i where i.ht_batch_id = bid)
        and not exists (select 1 from public.ht_items i where i.ht_batch_id = bid and i.time_out is null)
       then 'Completed' else 'In Furnace' end
   where b.id = bid;
  return null;
end; $$;
drop trigger if exists ht_items_sync_batch on public.ht_items;
create trigger ht_items_sync_batch after insert or update or delete on public.ht_items
for each row execute function public.ht_items_sync_batch();

-- A poured heat cannot be deleted / un-poured once its castings are in HT
create or replace function public.melting_batches_guard_ht() returns trigger language plpgsql as $$
declare
  oid uuid := old.order_uuid;
  poured_after int;
  loaded int;
begin
  -- order itself being deleted (cascade): nothing to protect
  if tg_op = 'DELETE' and not exists (select 1 from public.orders where id = oid) then return old; end if;
  select coalesce(sum(molds_poured), 0) into poured_after from public.melting_batches
   where order_uuid = oid and status = 'Poured' and id <> old.id;
  if tg_op = 'UPDATE' and new.status = 'Poured' then poured_after := poured_after + new.molds_poured; end if;
  select coalesce(sum(qty), 0) into loaded from public.ht_items where order_uuid = oid;
  if poured_after < loaded then
    raise exception 'Cannot change: % castings of this order are already in heat treatment', loaded;
  end if;
  return coalesce(new, old);
end; $$;
drop trigger if exists melting_batches_guard_ht on public.melting_batches;
create trigger melting_batches_guard_ht before update or delete on public.melting_batches
for each row execute function public.melting_batches_guard_ht();

-- ---------------------------------------------------------------------
-- 4. Triggers - Fettling
-- ---------------------------------------------------------------------
create or replace function public.fettling_guard() returns trigger language plpgsql as $$
declare
  oid uuid := coalesce(new.order_uuid, old.order_uuid);
  rid uuid := coalesce(new.id, old.id);
  other_all int; other_ok int;
begin
  -- order itself being deleted (cascade): nothing to protect
  if tg_op = 'DELETE' and not exists (select 1 from public.orders where id = oid) then return old; end if;
  select coalesce(sum(qty_ok + qty_rejected), 0), coalesce(sum(qty_ok), 0)
    into other_all, other_ok from public.fettling_entries where order_uuid = oid and id <> rid;
  if tg_op <> 'DELETE' then
    if new.qty_ok + new.qty_rejected > public.order_ht_done_qty(oid) - other_all then
      raise exception 'Only % heat-treated pieces are waiting for fettling on this order',
        greatest(public.order_ht_done_qty(oid) - other_all, 0);
    end if;
    other_ok := other_ok + new.qty_ok;
  end if;
  if other_ok < public.order_dispatched_qty(oid) then
    raise exception 'Cannot change: % pieces of this order are already dispatched', public.order_dispatched_qty(oid);
  end if;
  return coalesce(new, old);
end; $$;
drop trigger if exists fettling_guard on public.fettling_entries;
create trigger fettling_guard before insert or update or delete on public.fettling_entries
for each row execute function public.fettling_guard();

create or replace function public.fettling_sync_order() returns trigger language plpgsql as $$
begin
  perform public.sync_order_flow_status(coalesce(new.order_uuid, old.order_uuid));
  return null;
end; $$;
drop trigger if exists fettling_sync_order on public.fettling_entries;
create trigger fettling_sync_order after insert or update or delete on public.fettling_entries
for each row execute function public.fettling_sync_order();

-- ---------------------------------------------------------------------
-- 5. Triggers - Dispatch
-- ---------------------------------------------------------------------
create or replace function public.dispatch_before_save() returns trigger language plpgsql as $$
declare
  other int; next_number bigint;
begin
  select coalesce(sum(qty), 0) into other from public.dispatches where order_uuid = new.order_uuid and id <> new.id;
  if new.qty > public.order_finished_ok_qty(new.order_uuid) - other then
    raise exception 'Only % finished pieces are in stock for this order',
      greatest(public.order_finished_ok_qty(new.order_uuid) - other, 0);
  end if;
  if new.dispatch_no is null or new.dispatch_no = '' then
    select coalesce(max((regexp_match(dispatch_no, '^DSP-([0-9]+)$'))[1]::bigint), 0) + 1
      into next_number from public.dispatches where dispatch_no ~ '^DSP-[0-9]+$';
    new.dispatch_no := 'DSP-' || lpad(next_number::text, 6, '0');
  end if;
  return new;
end; $$;
drop trigger if exists dispatches_before_save on public.dispatches;
create trigger dispatches_before_save before insert or update on public.dispatches
for each row execute function public.dispatch_before_save();

create or replace function public.dispatch_sync_order() returns trigger language plpgsql as $$
begin
  perform public.sync_order_flow_status(coalesce(new.order_uuid, old.order_uuid));
  return null;
end; $$;
drop trigger if exists dispatches_sync_order on public.dispatches;
create trigger dispatches_sync_order after insert or update or delete on public.dispatches
for each row execute function public.dispatch_sync_order();

-- ---------------------------------------------------------------------
-- 6. RLS (development policies, same pattern as earlier files)
--    Tighten these before production.
-- ---------------------------------------------------------------------
alter table public.ht_batches enable row level security;
alter table public.ht_items enable row level security;
alter table public.ht_consumable_usage enable row level security;
alter table public.fettling_entries enable row level security;
alter table public.fettling_consumable_usage enable row level security;
alter table public.dispatches enable row level security;

drop policy if exists "Allow anon all ht_batches" on public.ht_batches;
create policy "Allow anon all ht_batches" on public.ht_batches for all using (true) with check (true);
drop policy if exists "Allow anon all ht_items" on public.ht_items;
create policy "Allow anon all ht_items" on public.ht_items for all using (true) with check (true);
drop policy if exists "Allow anon all ht_consumable_usage" on public.ht_consumable_usage;
create policy "Allow anon all ht_consumable_usage" on public.ht_consumable_usage for all using (true) with check (true);
drop policy if exists "Allow anon all fettling_entries" on public.fettling_entries;
create policy "Allow anon all fettling_entries" on public.fettling_entries for all using (true) with check (true);
drop policy if exists "Allow anon all fettling_consumable_usage" on public.fettling_consumable_usage;
create policy "Allow anon all fettling_consumable_usage" on public.fettling_consumable_usage for all using (true) with check (true);
drop policy if exists "Allow anon all dispatches" on public.dispatches;
create policy "Allow anon all dispatches" on public.dispatches for all using (true) with check (true);
