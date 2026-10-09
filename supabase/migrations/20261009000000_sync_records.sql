-- One Percent: cloud sync.
--
-- One table holds every synced item (goals, habits, small preferences) as a JSON document plus
-- the few columns sync needs. Devices keep their own copy and exchange changes:
--   * push: public.push_records(...)  -> last writer wins per item, decided by the device clock
--   * pull: select ... where server_updated_at > :cursor  (PostgREST, protected by RLS)
--   * live: Supabase Realtime on this table (Postgres changes, also protected by RLS)
-- Deletions are soft (deleted = true) so a device that was offline still learns about them.
--
-- Safe to run more than once. Paste it in the Supabase dashboard (SQL Editor) and run it.

begin;

-- ---------------------------------------------------------------------------------------------
-- Table
-- ---------------------------------------------------------------------------------------------
create table if not exists public.sync_records (
    id                uuid        not null,
    user_id           uuid        not null default auth.uid() references auth.users (id) on delete cascade,
    kind              text        not null check (kind in ('task', 'habit', 'pref')),
    data              jsonb       not null default '{}'::jsonb,
    -- When the device last changed the item (its own clock). Decides who wins a conflict.
    client_updated_at timestamptz not null,
    -- When the server stored it (set by a trigger, never trusted from the client). The pull cursor.
    server_updated_at timestamptz not null default clock_timestamp(),
    deleted           boolean     not null default false,
    device_id         text        not null default '' check (octet_length(device_id) <= 100),
    primary key (user_id, id),
    constraint sync_records_data_size check (pg_column_size(data) < 200000)
);

comment on table public.sync_records is 'One Percent sync: one JSON document per goal, habit or preference, per user.';

create index if not exists sync_records_pull_idx on public.sync_records (user_id, server_updated_at);
create index if not exists sync_records_kind_idx on public.sync_records (user_id, kind) where not deleted;

-- ---------------------------------------------------------------------------------------------
-- The server decides "when it was stored"; a client can never set it (nor another user's id).
-- ---------------------------------------------------------------------------------------------
create or replace function public.sync_records_stamp()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.server_updated_at := clock_timestamp();
    return new;
end;
$$;

drop trigger if exists sync_records_stamp on public.sync_records;
create trigger sync_records_stamp
    before insert or update on public.sync_records
    for each row execute function public.sync_records_stamp();

-- ---------------------------------------------------------------------------------------------
-- Row level security: a signed-in user sees and writes only their own rows. No delete policy:
-- items are deleted by setting `deleted`, and old tombstones are purged by purge_tombstones().
-- ---------------------------------------------------------------------------------------------
alter table public.sync_records enable row level security;
alter table public.sync_records force row level security;

drop policy if exists "sync_records_select_own" on public.sync_records;
create policy "sync_records_select_own" on public.sync_records
    for select to authenticated
    using (user_id = (select auth.uid()));

drop policy if exists "sync_records_insert_own" on public.sync_records;
create policy "sync_records_insert_own" on public.sync_records
    for insert to authenticated
    with check (user_id = (select auth.uid()));

drop policy if exists "sync_records_update_own" on public.sync_records;
create policy "sync_records_update_own" on public.sync_records
    for update to authenticated
    using (user_id = (select auth.uid()))
    with check (user_id = (select auth.uid()));

-- Explicit grants (the Data API no longer assumes them). The anonymous role gets nothing.
revoke all on table public.sync_records from public, anon, authenticated;
grant select, insert, update on table public.sync_records to authenticated;

-- ---------------------------------------------------------------------------------------------
-- push_records: apply a batch of changes, last writer wins per item.
--   p_records: [{ "id": uuid, "kind": "task|habit|pref", "data": {...},
--                 "client_updated_at": timestamptz, "deleted": bool, "device_id": text }, ...]
-- An incoming change is ignored when the stored one is newer; when both carry the same time the
-- larger device_id wins, so every device converges on the same result. Re-sending is harmless.
-- Returns, per item, whether it was applied and the server time of the stored version.
-- ---------------------------------------------------------------------------------------------
create or replace function public.push_records(p_records jsonb)
returns table (r_id uuid, r_applied boolean, r_server_updated_at timestamptz)
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_user   uuid := auth.uid();
    v_rec    jsonb;
    v_id     uuid;
    v_server timestamptz;
begin
    if v_user is null then
        raise exception 'not authenticated' using errcode = '28000';
    end if;
    if p_records is null or jsonb_typeof(p_records) <> 'array' then
        raise exception 'p_records must be a JSON array' using errcode = '22023';
    end if;
    if jsonb_array_length(p_records) > 500 then
        raise exception 'at most 500 records per push' using errcode = '22023';
    end if;

    for v_rec in select value from jsonb_array_elements(p_records) loop
        v_id := (v_rec ->> 'id')::uuid;
        v_server := null;

        insert into public.sync_records as s (id, user_id, kind, data, client_updated_at, deleted, device_id)
        values (
            v_id,
            v_user,
            v_rec ->> 'kind',
            coalesce(v_rec -> 'data', '{}'::jsonb),
            (v_rec ->> 'client_updated_at')::timestamptz,
            coalesce((v_rec ->> 'deleted')::boolean, false),
            coalesce(v_rec ->> 'device_id', '')
        )
        on conflict (user_id, id) do update
            set kind              = excluded.kind,
                data              = excluded.data,
                client_updated_at = excluded.client_updated_at,
                deleted           = excluded.deleted,
                device_id         = excluded.device_id
            where (excluded.client_updated_at, excluded.device_id) > (s.client_updated_at, s.device_id)
        returning s.server_updated_at into v_server;

        r_id := v_id;
        r_applied := v_server is not null;
        if v_server is null then
            select s.server_updated_at into v_server
            from public.sync_records s
            where s.user_id = v_user and s.id = v_id;
        end if;
        r_server_updated_at := v_server;
        return next;
    end loop;
end;
$$;

revoke all on function public.push_records(jsonb) from public, anon;
grant execute on function public.push_records(jsonb) to authenticated;

-- ---------------------------------------------------------------------------------------------
-- purge_tombstones: forget deletions older than the given age (default 180 days), only for the
-- caller's own rows. A device that stayed offline longer than that would not hear about them.
-- ---------------------------------------------------------------------------------------------
create or replace function public.purge_tombstones(p_older_than interval default interval '180 days')
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user  uuid := auth.uid();
    v_count integer;
begin
    if v_user is null then
        raise exception 'not authenticated' using errcode = '28000';
    end if;
    delete from public.sync_records s
    where s.user_id = v_user
      and s.deleted
      and s.server_updated_at < clock_timestamp() - p_older_than;
    get diagnostics v_count = row_count;
    return v_count;
end;
$$;

revoke all on function public.purge_tombstones(interval) from public, anon;
grant execute on function public.purge_tombstones(interval) to authenticated;

-- ---------------------------------------------------------------------------------------------
-- Realtime: broadcast row changes on this table (RLS still decides who receives what).
-- ---------------------------------------------------------------------------------------------
do $$
begin
    if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
       and not exists (
           select 1 from pg_publication_tables
           where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'sync_records'
       ) then
        alter publication supabase_realtime add table public.sync_records;
    end if;
end
$$;

commit;
