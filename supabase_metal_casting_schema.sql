-- Supabase schema for Metal Casting ERP
-- Run this in Supabase SQL Editor before importing/using the tables in FlutterFlow.

create extension if not exists "pgcrypto";

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  product_name text not null,
  model_id text not null unique,
  description text,
  status text not null default 'Active' check (status in ('Active', 'Inactive')),
  image_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.raw_materials (
  id uuid primary key default gen_random_uuid(),
  category text not null check (category in ('Scrap Input', 'FE Alloy & Metal Input')),
  material_name text not null,
  material_code text not null unique,
  unit_of_measurement text not null,
  description text,
  status text not null default 'Active' check (status in ('Active', 'Inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.consumables (
  id uuid primary key default gen_random_uuid(),
  category text not null check (category in ('Melting & Pouring Consumable', 'Molding & Molding Consumable')),
  consumable_name text not null,
  consumable_code text not null unique,
  unit_of_measurement text not null,
  description text,
  status text not null default 'Active' check (status in ('Active', 'Inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  order_id text unique,
  product_id uuid references public.products(id) on delete set null,
  model_name text not null,
  model_id text not null,
  product_image_url text,
  customer_name text not null,
  customer_mobile text,
  order_date date not null default current_date,
  delivery_date date,
  quantity integer not null check (quantity > 0),
  remarks text,
  status text not null default 'Pending' check (status in ('Pending', 'In Production', 'Completed', 'Delivered', 'Cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

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

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists products_set_updated_at on public.products;
create trigger products_set_updated_at
before update on public.products
for each row execute function public.set_updated_at();

drop trigger if exists raw_materials_set_updated_at on public.raw_materials;
create trigger raw_materials_set_updated_at
before update on public.raw_materials
for each row execute function public.set_updated_at();

drop trigger if exists consumables_set_updated_at on public.consumables;
create trigger consumables_set_updated_at
before update on public.consumables
for each row execute function public.set_updated_at();

drop trigger if exists orders_set_updated_at on public.orders;
create trigger orders_set_updated_at
before update on public.orders
for each row execute function public.set_updated_at();

drop trigger if exists molding_jobs_set_updated_at on public.molding_jobs;
create trigger molding_jobs_set_updated_at
before update on public.molding_jobs
for each row execute function public.set_updated_at();

drop trigger if exists melting_batches_set_updated_at on public.melting_batches;
create trigger melting_batches_set_updated_at
before update on public.melting_batches
for each row execute function public.set_updated_at();

create or replace function public.generate_order_id()
returns trigger
language plpgsql
as $$
declare
  next_number bigint;
begin
  if new.order_id is null or new.order_id = '' then
    select coalesce(max((regexp_match(order_id, '^ORD-([0-9]+)$'))[1]::bigint), 0) + 1
      into next_number
      from public.orders
      where order_id ~ '^ORD-[0-9]+$';

    new.order_id = 'ORD-' || lpad(next_number::text, 6, '0');
  end if;

  return new;
end;
$$;

drop trigger if exists orders_generate_order_id on public.orders;
create trigger orders_generate_order_id
before insert on public.orders
for each row execute function public.generate_order_id();

alter table public.products enable row level security;
alter table public.raw_materials enable row level security;
alter table public.consumables enable row level security;
alter table public.orders enable row level security;
alter table public.molding_jobs enable row level security;
alter table public.melting_batches enable row level security;

-- Development/testing policies for FlutterFlow preview.
-- Tighten these before production if the app will have public users.
drop policy if exists "Allow anon read products" on public.products;
create policy "Allow anon read products" on public.products for select using (true);
drop policy if exists "Allow anon write products" on public.products;
create policy "Allow anon write products" on public.products for all using (true) with check (true);

drop policy if exists "Allow anon read raw_materials" on public.raw_materials;
create policy "Allow anon read raw_materials" on public.raw_materials for select using (true);
drop policy if exists "Allow anon write raw_materials" on public.raw_materials;
create policy "Allow anon write raw_materials" on public.raw_materials for all using (true) with check (true);

drop policy if exists "Allow anon read consumables" on public.consumables;
create policy "Allow anon read consumables" on public.consumables for select using (true);
drop policy if exists "Allow anon write consumables" on public.consumables;
create policy "Allow anon write consumables" on public.consumables for all using (true) with check (true);

drop policy if exists "Allow anon read orders" on public.orders;
create policy "Allow anon read orders" on public.orders for select using (true);
drop policy if exists "Allow anon write orders" on public.orders;
create policy "Allow anon write orders" on public.orders for all using (true) with check (true);

drop policy if exists "Allow anon read molding_jobs" on public.molding_jobs;
create policy "Allow anon read molding_jobs" on public.molding_jobs for select using (true);
drop policy if exists "Allow anon write molding_jobs" on public.molding_jobs;
create policy "Allow anon write molding_jobs" on public.molding_jobs for all using (true) with check (true);

drop policy if exists "Allow anon read melting_batches" on public.melting_batches;
create policy "Allow anon read melting_batches" on public.melting_batches for select using (true);
drop policy if exists "Allow anon write melting_batches" on public.melting_batches;
create policy "Allow anon write melting_batches" on public.melting_batches for all using (true) with check (true);

insert into public.products (product_name, model_id, description, status, image_url)
values
  ('Pump Housing', 'PH-1001', 'Cast metal pump housing sample product.', 'Active', null),
  ('Valve Body', 'VB-2001', 'Industrial valve body sample product.', 'Active', null)
on conflict (model_id) do nothing;

insert into public.raw_materials (category, material_name, material_code, unit_of_measurement, description, status)
values
  ('Scrap Input', 'MS Scrap', 'RM-SCRAP-MS', 'KG', 'Mild steel scrap input.', 'Active'),
  ('FE Alloy & Metal Input', 'Ferro Silicon', 'RM-FE-SI', 'KG', 'FE alloy input for melting.', 'Active')
on conflict (material_code) do nothing;

insert into public.consumables (category, consumable_name, consumable_code, unit_of_measurement, description, status)
values
  ('Melting & Pouring Consumable', 'Ladle Coating', 'CON-MP-LADLE', 'KG', 'Consumable for melting and pouring process.', 'Active'),
  ('Molding & Molding Consumable', 'Silica Sand', 'CON-MM-SAND', 'KG', 'Consumable for molding process.', 'Active')
on conflict (consumable_code) do nothing;
