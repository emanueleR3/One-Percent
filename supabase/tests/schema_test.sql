-- Behaviour tests for the sync schema. Every check raises if it fails; run with ON_ERROR_STOP.
\set ON_ERROR_STOP on
\set A '''11111111-1111-1111-1111-111111111111'''
\set B '''22222222-2222-2222-2222-222222222222'''
\set T1 '''aaaaaaaa-0000-0000-0000-000000000001'''
\set H1 '''bbbbbbbb-0000-0000-0000-000000000001'''

insert into auth.users (id, email) values (:A, 'a@test'), (:B, 'b@test') on conflict do nothing;

-- 1. first push stores both items
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :A, true) as sub \gset
do $$
declare n int;
begin
    select count(*) into n from public.push_records($j$[
        {"id":"aaaaaaaa-0000-0000-0000-000000000001","kind":"task","data":{"title":"v1"},"client_updated_at":"2026-10-09T10:00:00Z","device_id":"mac"},
        {"id":"bbbbbbbb-0000-0000-0000-000000000001","kind":"habit","data":{"title":"gym"},"client_updated_at":"2026-10-09T10:00:00Z","device_id":"mac"}
    ]$j$::jsonb) where r_applied;
    assert n = 2, 'first push applies both items';
end $$;
commit;

-- 2. an older change is ignored, a newer one wins and moves the server cursor forward
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :A, true) as sub \gset
do $$
declare stored_before timestamptz; applied boolean; stored_after timestamptz; title text;
begin
    select server_updated_at into stored_before from public.sync_records where id = 'aaaaaaaa-0000-0000-0000-000000000001';

    select r_applied into applied from public.push_records('[{"id":"aaaaaaaa-0000-0000-0000-000000000001","kind":"task","data":{"title":"older"},"client_updated_at":"2026-10-09T09:00:00Z","device_id":"phone"}]'::jsonb);
    assert applied = false, 'older change must be ignored';
    select data ->> 'title' into title from public.sync_records where id = 'aaaaaaaa-0000-0000-0000-000000000001';
    assert title = 'v1', 'older change must not overwrite';

    select r_applied into applied from public.push_records('[{"id":"aaaaaaaa-0000-0000-0000-000000000001","kind":"task","data":{"title":"v2"},"client_updated_at":"2026-10-09T11:00:00Z","device_id":"phone"}]'::jsonb);
    assert applied, 'newer change must win';
    select data ->> 'title', server_updated_at into title, stored_after from public.sync_records where id = 'aaaaaaaa-0000-0000-0000-000000000001';
    assert title = 'v2', 'newer data stored';
    assert stored_after > stored_before, 'server_updated_at moves forward on every applied change';
end $$;
commit;

-- 3. equal times: the larger device id wins, and re-sending the same change is harmless
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :A, true) as sub \gset
do $$
declare applied boolean;
begin
    select r_applied into applied from public.push_records('[{"id":"aaaaaaaa-0000-0000-0000-000000000001","kind":"task","data":{"title":"zzz"},"client_updated_at":"2026-10-09T11:00:00Z","device_id":"zzz"}]'::jsonb);
    assert applied, 'tie goes to the larger device id';
    select r_applied into applied from public.push_records('[{"id":"aaaaaaaa-0000-0000-0000-000000000001","kind":"task","data":{"title":"aaa"},"client_updated_at":"2026-10-09T11:00:00Z","device_id":"aaa"}]'::jsonb);
    assert applied = false, 'tie goes against the smaller device id';
    select r_applied into applied from public.push_records('[{"id":"aaaaaaaa-0000-0000-0000-000000000001","kind":"task","data":{"title":"zzz"},"client_updated_at":"2026-10-09T11:00:00Z","device_id":"zzz"}]'::jsonb);
    assert applied = false, 'sending the same change twice is a no-op';
end $$;
commit;

-- 4. a soft delete is just a newer change
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :A, true) as sub \gset
do $$
declare gone boolean;
begin
    perform * from public.push_records('[{"id":"aaaaaaaa-0000-0000-0000-000000000001","kind":"task","data":{},"client_updated_at":"2026-10-09T12:00:00Z","deleted":true,"device_id":"mac"}]'::jsonb);
    select deleted into gone from public.sync_records where id = 'aaaaaaaa-0000-0000-0000-000000000001';
    assert gone, 'tombstone stored';
end $$;
commit;

-- 5. another user sees nothing, cannot change or forge rows, and ids may even collide safely
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :B, true) as sub \gset
do $$
declare n int; changed int; title text;
begin
    select count(*) into n from public.sync_records;
    assert n = 0, 'user B must not see user A rows';

    update public.sync_records set data = '{"hacked":true}' where id = 'bbbbbbbb-0000-0000-0000-000000000001';
    get diagnostics changed = row_count;
    assert changed = 0, 'user B must not update user A rows';

    begin
        insert into public.sync_records (id, user_id, kind, client_updated_at)
        values (gen_random_uuid(), '11111111-1111-1111-1111-111111111111', 'task', now());
        raise exception 'expected the forged insert to fail' using errcode = 'XX999';
    exception when insufficient_privilege then null; end;

    -- same id as one of A's rows: stored separately for B
    perform * from public.push_records('[{"id":"bbbbbbbb-0000-0000-0000-000000000001","kind":"habit","data":{"title":"mine"},"client_updated_at":"2026-10-09T08:00:00Z","device_id":"b-phone"}]'::jsonb);
    select data ->> 'title' into title from public.sync_records where id = 'bbbbbbbb-0000-0000-0000-000000000001';
    assert title = 'mine', 'B stores its own copy';
end $$;
commit;

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :A, true) as sub \gset
do $$
declare title text;
begin
    select data ->> 'title' into title from public.sync_records where id = 'bbbbbbbb-0000-0000-0000-000000000001';
    assert title = 'gym', 'A row untouched by B';
end $$;
commit;

-- 6. nobody can hard-delete, and the anonymous role gets nothing
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :A, true) as sub \gset
do $$
begin
    begin
        delete from public.sync_records;
        raise exception 'expected delete to be refused' using errcode = 'XX999';
    exception when insufficient_privilege then null; end;
end $$;
commit;

begin;
set local role anon;
do $$
begin
    begin
        perform count(*) from public.sync_records;
        raise exception 'anon must not read' using errcode = 'XX999';
    exception when insufficient_privilege then null; end;
    begin
        perform * from public.push_records('[]'::jsonb);
        raise exception 'anon must not push' using errcode = 'XX999';
    exception when insufficient_privilege then null; end;
end $$;
commit;

-- 7. the server clock cannot be forged
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :A, true) as sub \gset
do $$
declare stamped timestamptz;
begin
    insert into public.sync_records (id, kind, client_updated_at, server_updated_at)
    values ('cccccccc-0000-0000-0000-000000000001', 'pref', now(), '2000-01-01T00:00:00Z');
    select server_updated_at into stamped from public.sync_records where id = 'cccccccc-0000-0000-0000-000000000001';
    assert stamped > '2020-01-01', 'server_updated_at is set by the server';
end $$;
commit;

-- 8. bad input is refused
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :A, true) as sub \gset
do $$
begin
    begin
        perform * from public.push_records('[{"id":"dddddddd-0000-0000-0000-000000000001","kind":"weird","client_updated_at":"2026-10-09T10:00:00Z"}]'::jsonb);
        raise exception 'unknown kind accepted' using errcode = 'XX999';
    exception when check_violation then null; end;
    begin
        perform * from public.push_records('{"not":"an array"}'::jsonb);
        raise exception 'non-array accepted' using errcode = 'XX999';
    exception when invalid_parameter_value then null; end;
    begin
        perform * from public.push_records((select jsonb_agg(jsonb_build_object('id', gen_random_uuid(), 'kind', 'task', 'client_updated_at', now())) from generate_series(1, 501)));
        raise exception 'oversized batch accepted' using errcode = 'XX999';
    exception when invalid_parameter_value then null; end;
end $$;
commit;

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '', true) as sub \gset
do $$
begin
    begin
        perform * from public.push_records('[]'::jsonb);
        raise exception 'unauthenticated push accepted' using errcode = 'XX999';
    exception when invalid_authorization_specification then null; end;
end $$;
commit;

-- 9. purging tombstones only touches the caller's deleted rows
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :A, true) as sub \gset
do $$
declare purged int; remaining int;
begin
    purged := public.purge_tombstones(interval '0 seconds');
    assert purged = 1, 'one tombstone purged';
    select count(*) into remaining from public.sync_records where not deleted;
    assert remaining >= 1, 'live rows survive';
end $$;
commit;

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :B, true) as sub \gset
do $$
declare n int;
begin
    select count(*) into n from public.sync_records;
    assert n = 1, 'B rows survive A purge';
end $$;
commit;

-- 10. changes are broadcast
do $$
begin
    assert (select count(*) from pg_publication_tables
            where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'sync_records') = 1,
           'sync_records is in the Realtime publication';
end $$;

\echo ALL SCHEMA TESTS PASSED
