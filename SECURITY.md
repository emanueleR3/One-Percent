# Security

## Reporting a problem

Please report security problems privately, not in a public issue: on GitHub, open the repository's
**Security** tab and choose **Report a vulnerability**. Include what you found, how to reproduce it,
and what an attacker could do with it. You will get an answer as soon as possible, and credit in the
fix if you want it.

## What is in scope

- The Mac and iPhone apps, including how they store data and the sign-in session.
- The sync backend in `supabase/`: the migration, row-level security, and the `push_records` function.
- The build and install scripts in `Scripts/`.

## Good to know

- The Supabase **publishable** key is meant to ship inside the apps. On its own it grants nothing:
  every row answers only to its signed-in owner. Never put a `secret` / `service_role` key in the
  apps or in this repository.
- Each person who builds the apps uses their own Supabase project (`Config/Local.xcconfig`, which git
  ignores). Turn off sign-ups in that project: the apps never create accounts.
- On the Mac the sign-in session is kept in a file only you can read
  (`~/Library/Application Support/OnePercent/session.json`, mode 0600); on the iPhone it is kept in
  the Keychain.
