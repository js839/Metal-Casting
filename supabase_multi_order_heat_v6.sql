-- =====================================================================
-- Metal Casting ERP - v6: one Heat can pour molds of MORE THAN ONE order
--   e.g. Heat HT-000001 -> ORD-000001 (3 molds) + ORD-000002 (2 molds)
-- Run AFTER v2 (molding/melting) and v3 (HT/fettling/dispatch).
-- Safe to run more than once. Existing heats are copied automatically.
-- =====================================================================

-- 1. Orders poured in each heat (one row per order per heat)
create table if not exists public.melting_batch_orders (
  id uuid primary key default gen_random_uuid(),
  melting_batch_id uuid not null references public.melting_batches(id) on delete cascade,
  order_uuid uuid not null references public.orders(id) on delete cascade,
  molds_poured integer not null default 0 check (molds_poured >= 0),
  created_at timestamptz not null default now(),
  unique (melting_batch_id, order_uuid)
);
create index if not exists melting_batch_orders_order_idx on public.melting_batch_orders(order_uuid);
create index if not exists melting_batch_orders_batch_idx on public.melting_batch_orders(melting_batch_id);

-- 2. Copy existing single-order heats
insert into public.melting_batch_orders (melting_batch_id, order_uuid, molds_poured)
select id, order_uuid, coalesce(molds_poured, 0)
  from public.melting_batches
 where order_uuid is not null
on conflict (melting_batch_id, order_uuid) do nothing;

-- 3. melting_batches.order_uuid is now just the "first order" of the heat.
--    Deleting one order must NOT delete a heat shared with other orders.
alter table public.melting_batches alter column order_uuid drop not null;
alter table public.melting_batches drop constraint if exists melting_batches_order_uuid_fkey;
alter table public.melting_batches add constraint melting_batches_order_uuid_fkey
  foreign key (order_uuid) references public.orders(id) on delete set null;

-- 4. Heat before-save: only auto heat no + molding job link (mold check moved to step 5)
create or replace function public.melting_batch_before_save()
returns trigger language plpgsql as $$
declare next_number bigint;
begin
  if new.molding_job_id is null and new.order_uuid is not null then
    select id into new.molding_job_id from public.molding_jobs where order_uuid = new.order_uuid;
  end if;
  if new.heat_no is null or new.heat_no = '' then
    select coalesce(max((regexp_match(heat_no, '^HT-([0-9]+)$'))[1]::bigint), 0) + 1
      into next_number from public.melting_batches where heat_no ~ '^HT-[0-9]+$';
    new.heat_no := 'HT-' || lpad(next_number::text, 6, '0');
  end if;
  return new;
end; $$;

-- 5. Per-order line guard: never pour more molds than made; never undo castings already in HT
create or replace function public.melting_batch_orders_guard()
returns trigger language plpgsql as $$
declare
  oid uuid := coalesce(new.order_uuid, old.order_uuid);
  bid uuid := coalesce(new.melting_batch_id, old.melting_batch_id);
  ord text;
  made int; used int; poured_after int; loaded int; bstatus text;
begin
  if tg_op = 'DELETE' and not exists (select 1 from public.orders where id = oid) then return old; end if;
  select order_id into ord from public.orders where id = oid;

  if tg_op in ('INSERT', 'UPDATE') then
    select molds_made into made from public.molding_jobs where order_uuid = oid;
    select coalesce(sum(molds_poured), 0) into used
      from public.melting_batch_orders where order_uuid = oid and melting_batch_id <> new.melting_batch_id;
    if new.molds_poured > coalesce(made, 0) - used then
      raise exception 'Only % molds are available for pouring on order %', greatest(coalesce(made, 0) - used, 0), ord;
    end if;
  end if;

  select coalesce(sum(l.molds_poured), 0) into poured_after
    from public.melting_batch_orders l join public.melting_batches b on b.id = l.melting_batch_id
   where l.order_uuid = oid and b.status = 'Poured' and l.melting_batch_id <> bid;
  if tg_op <> 'DELETE' then
    select status into bstatus from public.melting_batches where id = bid;
    if bstatus = 'Poured' then poured_after := poured_after + new.molds_poured; end if;
  end if;
  select coalesce(sum(qty), 0) into loaded from public.ht_items where order_uuid = oid;
  if poured_after < loaded then
    raise exception 'Cannot change: % castings of order % are already in heat treatment', loaded, ord;
  end if;
  return coalesce(new, old);
end; $$;
drop trigger if exists melting_batch_orders_guard on public.melting_batch_orders;
create trigger melting_batch_orders_guard before insert or update or delete on public.melting_batch_orders
for each row execute function public.melting_batch_orders_guard();

-- 6. Keep melting_batches.molds_poured = total of its order lines
create or replace function public.melting_batch_orders_sync_total()
returns trigger language plpgsql as $$
declare bid uuid := coalesce(new.melting_batch_id, old.melting_batch_id); total int;
begin
  select coalesce(sum(molds_poured), 0) into total from public.melting_batch_orders where melting_batch_id = bid;
  update public.melting_batches set molds_poured = total where id = bid and molds_poured is distinct from total;
  return null;
end; $$;
drop trigger if exists melting_batch_orders_sync on public.melting_batch_orders;
create trigger melting_batch_orders_sync after insert or update or delete on public.melting_batch_orders
for each row execute function public.melting_batch_orders_sync_total();

-- 7. Poured qty per order now comes from the order lines
create or replace function public.order_poured_qty(oid uuid) returns integer language sql stable as $$
  select coalesce(sum(l.molds_poured), 0)::int
    from public.melting_batch_orders l join public.melting_batches b on b.id = l.melting_batch_id
   where l.order_uuid = oid and b.status = 'Poured';
$$;

-- 8. Heat status change / delete: check every order in the heat against HT
create or replace function public.melting_batches_guard_ht()
returns trigger language plpgsql as $$
declare r record; poured_after int; loaded int;
begin
  for r in select l.order_uuid, l.molds_poured, o.order_id
             from public.melting_batch_orders l join public.orders o on o.id = l.order_uuid
            where l.melting_batch_id = old.id loop
    select coalesce(sum(l2.molds_poured), 0) into poured_after
      from public.melting_batch_orders l2 join public.melting_batches b on b.id = l2.melting_batch_id
     where l2.order_uuid = r.order_uuid and b.status = 'Poured' and l2.melting_batch_id <> old.id;
    if tg_op = 'UPDATE' and new.status = 'Poured' then poured_after := poured_after + r.molds_poured; end if;
    select coalesce(sum(qty), 0) into loaded from public.ht_items where order_uuid = r.order_uuid;
    if poured_after < loaded then
      raise exception 'Cannot change: % castings of order % are already in heat treatment', loaded, r.order_id;
    end if;
  end loop;
  return coalesce(new, old);
end; $$;

-- 9. RLS (same development pattern as other tables)
alter table public.melting_batch_orders enable row level security;
drop policy if exists "Allow anon all melting_batch_orders" on public.melting_batch_orders;
create policy "Allow anon all melting_batch_orders" on public.melting_batch_orders for all using (true) with check (true);

notify pgrst, 'reload schema';
