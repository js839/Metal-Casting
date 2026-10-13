-- =====================================================================
-- Metal Casting ERP - v7: Casting rejection after Melting & Pouring
--   Per heat, per order: how many poured castings came out bad + why.
--   Only GOOD castings (poured - rejected) go on to Heat Treatment.
-- Run AFTER v6 (supabase_multi_order_heat_v6.sql). Safe to run again.
-- =====================================================================

-- 1. Rejection columns on each (heat, order) line
alter table public.melting_batch_orders add column if not exists molds_rejected integer not null default 0;
alter table public.melting_batch_orders add column if not exists rejection_reason text;
alter table public.melting_batch_orders add column if not exists rejection_remarks text;
alter table public.melting_batch_orders drop constraint if exists melting_batch_orders_rejected_check;
alter table public.melting_batch_orders add constraint melting_batch_orders_rejected_check
  check (molds_rejected >= 0 and molds_rejected <= molds_poured);

-- Heat-level total (kept in sync automatically)
alter table public.melting_batches add column if not exists molds_rejected integer not null default 0;

-- 2. Good castings per order = poured - rejected (in Poured heats)
create or replace function public.order_poured_qty(oid uuid) returns integer language sql stable as $$
  select coalesce(sum(l.molds_poured - l.molds_rejected), 0)::int
    from public.melting_batch_orders l join public.melting_batches b on b.id = l.melting_batch_id
   where l.order_uuid = oid and b.status = 'Poured';
$$;

-- 3. Line guard: mold availability (poured) + HT protection (good castings)
create or replace function public.melting_batch_orders_guard()
returns trigger language plpgsql as $$
declare
  oid uuid := coalesce(new.order_uuid, old.order_uuid);
  bid uuid := coalesce(new.melting_batch_id, old.melting_batch_id);
  ord text;
  made int; used int; good_after int; loaded int; bstatus text;
begin
  if tg_op = 'DELETE' and not exists (select 1 from public.orders where id = oid) then return old; end if;
  select order_id into ord from public.orders where id = oid;

  if tg_op in ('INSERT', 'UPDATE') then
    if new.molds_rejected > new.molds_poured then
      raise exception 'Order %: rejected (%) cannot be more than poured (%) in this heat', ord, new.molds_rejected, new.molds_poured;
    end if;
    select molds_made into made from public.molding_jobs where order_uuid = oid;
    select coalesce(sum(molds_poured), 0) into used
      from public.melting_batch_orders where order_uuid = oid and melting_batch_id <> new.melting_batch_id;
    if new.molds_poured > coalesce(made, 0) - used then
      raise exception 'Only % molds are available for pouring on order %', greatest(coalesce(made, 0) - used, 0), ord;
    end if;
  end if;

  select coalesce(sum(l.molds_poured - l.molds_rejected), 0) into good_after
    from public.melting_batch_orders l join public.melting_batches b on b.id = l.melting_batch_id
   where l.order_uuid = oid and b.status = 'Poured' and l.melting_batch_id <> bid;
  if tg_op <> 'DELETE' then
    select status into bstatus from public.melting_batches where id = bid;
    if bstatus = 'Poured' then good_after := good_after + new.molds_poured - new.molds_rejected; end if;
  end if;
  select coalesce(sum(qty), 0) into loaded from public.ht_items where order_uuid = oid;
  if good_after < loaded then
    raise exception 'Cannot change: % castings of order % are already in heat treatment', loaded, ord;
  end if;
  return coalesce(new, old);
end; $$;

-- 4. Heat status change / delete guard uses good castings too
create or replace function public.melting_batches_guard_ht()
returns trigger language plpgsql as $$
declare r record; good_after int; loaded int;
begin
  for r in select l.order_uuid, l.molds_poured - l.molds_rejected as good, o.order_id
             from public.melting_batch_orders l join public.orders o on o.id = l.order_uuid
            where l.melting_batch_id = old.id loop
    select coalesce(sum(l2.molds_poured - l2.molds_rejected), 0) into good_after
      from public.melting_batch_orders l2 join public.melting_batches b on b.id = l2.melting_batch_id
     where l2.order_uuid = r.order_uuid and b.status = 'Poured' and l2.melting_batch_id <> old.id;
    if tg_op = 'UPDATE' and new.status = 'Poured' then good_after := good_after + r.good; end if;
    select coalesce(sum(qty), 0) into loaded from public.ht_items where order_uuid = r.order_uuid;
    if good_after < loaded then
      raise exception 'Cannot change: % castings of order % are already in heat treatment', loaded, r.order_id;
    end if;
  end loop;
  return coalesce(new, old);
end; $$;

-- 5. Keep heat totals (poured + rejected) in sync with its order lines
create or replace function public.melting_batch_orders_sync_total()
returns trigger language plpgsql as $$
declare bid uuid := coalesce(new.melting_batch_id, old.melting_batch_id); total int; rej int;
begin
  select coalesce(sum(molds_poured), 0), coalesce(sum(molds_rejected), 0) into total, rej
    from public.melting_batch_orders where melting_batch_id = bid;
  update public.melting_batches set molds_poured = total, molds_rejected = rej
   where id = bid and (molds_poured is distinct from total or molds_rejected is distinct from rej);
  return null;
end; $$;

notify pgrst, 'reload schema';
