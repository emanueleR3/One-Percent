# One Percent: cloud sync backend

The Mac app and the iPhone app keep their own copy of your goals and habits and exchange changes
through a free Supabase project. One table, `public.sync_records`, holds every item as a JSON
document; row level security keeps each account to its own rows.

Project: see [`project.json`](project.json). The **publishable** key is meant to be embedded in the
apps: on its own it can do nothing, because the table only answers to a signed-in user. Never put
the project's `secret` / `service_role` key in this repo or in an app.

## Set it up (about 5 minutes, once)

1. **Create the table.** Dashboard → *SQL Editor* → new query → paste
   [`migrations/20261009000000_sync_records.sql`](migrations/20261009000000_sync_records.sql) → *Run*.
   It is safe to run again.
2. **Create your account.** *Authentication → Users → Add user → Create new user*: your email and a
   password, with *Auto Confirm User* ticked.
3. **Close sign-ups.** *Authentication → Sign In / Providers* (called *Sign In / Up* in some
   versions) → turn off *Allow new users to sign up*. The apps only sign in; nobody else needs an
   account, and this keeps strangers from using up the free quota.
4. **Check it.**
   ```bash
   EMAIL=you@example.com PASSWORD='your password' python3 supabase/tests/smoke.py
   ```
   It must end with `ALL LIVE CHECKS PASSED`.

Realtime needs nothing else: the migration adds the table to the `supabase_realtime` publication.
Free projects pause after 7 days without traffic (restore them from the dashboard); using the
apps keeps them awake.

## Check the real thing end to end (including the live channel)

```bash
zsh Scripts/test-live.sh
```

Asks for your email and password, then syncs a goal between two simulated devices through the
real project and waits for Realtime to announce a change. It leaves one tombstone behind.

## Test the schema without touching the project

```bash
zsh supabase/tests/run-local.sh
```

Starts a throwaway Postgres in Docker, applies the migration twice, and runs
[`tests/schema_test.sql`](tests/schema_test.sql): last writer wins and tie-breaking, tombstones,
isolation between users, refused deletes, no anonymous access, forged timestamps, bad input,
purging, Realtime publication.

## How the apps talk to it

A record, as sent to `push_records` and stored:

| field | meaning |
|---|---|
| `id` | the item's own UUID (`TaskItem.id`, `Habit.id`) |
| `kind` | `task`, `habit` or `pref` |
| `data` | the item's `Codable` JSON, the same as in `tasks.json` (ISO 8601 dates) |
| `client_updated_at` | when this device last changed it (`updatedAt`). Decides conflicts |
| `deleted` | `true` = tombstone (a deletion that other devices still need to hear about) |
| `device_id` | stable per install; breaks ties when two edits carry the same time |
| `server_updated_at` | set by the server on every applied change; never sent. The pull cursor |

**Push** `POST /rest/v1/rpc/push_records` with `{"p_records": [ ... ]}` (up to 500). Per item the
answer says whether it was applied. An older change is ignored; re-sending is harmless.

**Pull** `GET /rest/v1/sync_records?server_updated_at=gt.<cursor>&order=server_updated_at.asc&limit=500`.
Start the next pull a few seconds *before* the last cursor (commit order can differ from
timestamp order) and ignore what you already hold: applying a record is idempotent.

**Live** subscribe to `postgres_changes` on `public.sync_records` filtered by `user_id=eq.<your id>`.
On iPhone the socket dies with the app in the background: on every return to the foreground,
reconnect, then pull.

**Conflicts** are last-writer-wins per item, not per field. Goals are small and edited by one
person on one device at a time, so that is enough.

**Deleting** an item is a push with `deleted: true`. `purge_tombstones()` forgets tombstones older
than 180 days; a device offline for longer than that would not hear about those deletions.
