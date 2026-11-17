# Supabase launch checklist for AI-built apps

Before real users sign up to an app built with Lovable, Bolt, Replit, Cursor or a similar tool on Supabase, check
these things yourself. Each item says what goes wrong, how to check it, and how to fix it.

**Start with Supabase's own lists.** Their
[production security checklist](https://supabase.com/docs/guides/security/production-checklist) covers platform
settings (RLS, SSL, network restrictions, account MFA, Auth settings) and their
[production checklist](https://supabase.com/docs/guides/deployment/going-into-prod) covers performance, availability
and rate limits. Run **Security Advisor** and **Performance Advisor** in the dashboard too. This list does not repeat
them. It covers what those pages leave to you as a "threat review": the mistakes that come from your app's own
tables, policies and code.

The SQL below runs in **Dashboard → SQL Editor** and only reads. Every query is tested on a database with planted
problems (`tests/`). The free [supabase-check](https://github.com/kodev-team/supabase-check) runs most of the
database items at once; its check IDs are given as `K01` and so on.

---

## A. Who can read and change data

### 1. Every table has Row Level Security on (`K01`)
**What goes wrong:** your app's public key ships in the browser. Without RLS, anyone who has it can read and change
the whole table.
**Check:** [`queries/01-tables-without-rls.sql`](queries/01-tables-without-rls.sql). Expected: no rows.
**Fix:** `alter table public.<name> enable row level security;` then add policies for who may read and write which
rows.

### 2. No policy lets everyone write, and "everyone can read" is on purpose (`K03`, `K04`)
**What goes wrong:** a policy with `true` lets every visitor (or every signed-in user) insert, change or delete any
row. AI tools often write `true` to make an error go away.
**Check:** [`queries/02-open-policies.sql`](queries/02-open-policies.sql). Writes listed: none. Reads listed: only
tables that are really public (a blog, a price list).
**Fix:** replace `true` with an ownership check, for example `(select auth.uid()) = user_id`, in `using` and
`with check`.

### 3. Personal and payment columns are not on publicly readable tables (`K11`)
**What goes wrong:** a profile table with "everyone can read" also exposes email, phone or bank columns, even if
your screens never show them. They can be downloaded in bulk with the public key.
**Check:** run supabase-check, or look at every table from item 2 that has a read-all policy.
**Fix:** move private columns to a table only the owner can read, or grant `select` only on the public columns.

### 4. A second account cannot see or change the first account's data
**What goes wrong:** the policies exist but compare the wrong column, or a screen loads records by an id from the
URL. No catalog check can prove this one is fine.
**Check:** create two test accounts, A and B. As A, create a record and note its id. Sign in as B and open A's
record by changing the id in the URL, then try to edit and delete it. Also try through the API with B's token
(copy it from the browser's network tab, request header `Authorization`):

```sh
curl "https://<project>.supabase.co/rest/v1/<table>?id=eq.<A's id>" \
  -H "apikey: <your publishable key>" -H "Authorization: Bearer <B's access token>"
```

Expected: `[]` for reads; an error or nothing changed for writes. Use only your own project and test accounts.
**Fix:** correct the policy for that table (item 2), then repeat the test.

### 5. Users cannot give themselves a role (`K05`, `K10`)
**What goes wrong:** roles stored in `user_metadata` can be changed by every user from the browser; a `user_roles`
table with an insert policy that only checks `user_id` lets anyone add `admin` for themselves.
**Check:** run supabase-check. Then as a normal test user, try:

```sh
curl -X POST "https://<project>.supabase.co/rest/v1/user_roles" \
  -H "apikey: <your publishable key>" -H "Authorization: Bearer <user's access token>" \
  -H "Content-Type: application/json" -d '{"user_id":"<that user id>","role":"admin"}'
```

Expected: an error.
**Fix:** no insert policy for users on the roles table; assign roles from server code or a `security definer`
function that checks who is calling. Keep roles in a table or in `app_metadata`, never `user_metadata`.

### 6. Users cannot change price, payment, status or role columns on their own rows
**What goes wrong:** "users can update their own order" also lets them set `total = 0`, `status = 'paid'` or
`credits = 999999`.
**Check:** [`queries/03-protected-columns.sql`](queries/03-protected-columns.sql) lists such columns that signed-in
users may update. Each one needs a reason.
**Fix:** `revoke update on public.<table> from authenticated; grant update (<columns users may edit>) on
public.<table> to authenticated;` and set the rest from server code.

### 7. Functions and views do not skip your policies (`K06`, `K07`)
**What goes wrong:** a `security definer` function runs with its owner's rights and ignores RLS; a view without
`security_invoker` does the same. Both are callable through the API by default.
**Check:** run supabase-check, or Security Advisor.
**Fix:** inside each such function, check who is calling; move helpers out of `public` or revoke `execute` from
`anon, authenticated`; `alter view <name> set (security_invoker = true);`.

### 8. User files are in private buckets with per-user policies (`K09`)
**What goes wrong:** a public bucket serves any file to anyone who has or guesses the path: invoices, IDs, contracts.
**Check:** [`queries/04-storage-policies.sql`](queries/04-storage-policies.sql). Public buckets: only logos and
public images. Policies for user files compare the folder with the user's id.
**Fix:** make the bucket private, serve files with signed URLs, and use a policy such as
`(storage.foldername(name))[1] = (select auth.uid())::text`.

### 9. Realtime does not broadcast private rows
**What goes wrong:** a table added to Realtime without RLS sends every change to every listener.
**Check:** [`queries/05-realtime-tables.sql`](queries/05-realtime-tables.sql). Every row should say `t` (true).
**Fix:** enable RLS and policies on those tables, or remove them from the publication. Supabase notes that RLS does
not filter `DELETE` events.

## B. Keys and server code

### 10. No secret key is in the browser code
**What goes wrong:** the `service_role` (secret) key, or a Stripe or OpenAI secret key, in frontend code gives anyone
full access. Variables starting with `VITE_` or `NEXT_PUBLIC_` are built into the browser bundle.
**Check:** in your repository:

```sh
grep -rnE "service_role|SERVICE_ROLE|sb_secret_|sk_live_|sk_test_|sk-[A-Za-z0-9]{20}" src/ app/ components/ pages/ 2>/dev/null
grep -rnE "(VITE|NEXT_PUBLIC)_[A-Z_]*(SECRET|SERVICE|PRIVATE)" . --include=*.ts --include=*.tsx --include=*.js --include=*.env* 2>/dev/null
```

Expected: no output. If a key was ever committed, it is public in the history.
**Fix:** move the call to an Edge Function that reads the key from its secrets, then **rotate the key**.

### 11. Every Edge Function checks who is calling
**What goes wrong:** a function deployed with JWT verification off, or one that uses the service role key, can be
called by anyone and does whatever it does for them.
**Check:** `grep -n "verify_jwt = false" supabase/config.toml`. For each function listed, and each function that uses
the service role key, read the first lines: does it check a signed-in user, an admin role or a webhook signature
before acting?
**Fix:** keep JWT verification on unless the function is a webhook; in the function, read the user from the token
and check their right to the specific record.

### 12. Payment webhooks verify the signature, and prices come from the server
**What goes wrong:** a webhook that does not verify the signature accepts fake "payment succeeded" events; a
checkout that takes the amount from the browser lets users choose their price.
**Check:** `grep -rn "constructEvent" supabase/functions/`. In Deno, Stripe needs `constructEventAsync` with the raw
request body and your webhook secret. Find where the amount is set: it must be read from your database or Stripe
prices on the server, not from the request.
**Fix:** verify the signature first and stop on failure; look up prices on the server.

## C. Launch and after

### 13. You can rebuild your database from the repository
**What goes wrong:** migrations that only work on the live database (out of order, edited by hand in the dashboard)
cannot recreate it after an accident.
**Check:** `supabase db start` on a fresh checkout (needs Docker). If it stops with an error, the migrations do not
rebuild your database.
**Fix:** rename migrations that run too early; move dashboard changes into migrations (`supabase db diff`).

### 14. You have your own copy of the data
**What goes wrong:** Supabase notes that database backups are not available for download on the Free Plan.
**Check:** [Database Backups](https://supabase.com/docs/guides/platform/backups) for your plan.
**Fix:** before launch and on a schedule, export with `supabase db dump`, and test restoring it once into a local
database.

### 15. Auth is set for real users
**Check:** the Auth section of Supabase's
[production security checklist](https://supabase.com/docs/guides/security/production-checklist): email
confirmations on, OTP and link expiry of 3600 seconds or lower, test phone numbers removed, your own SMTP. Also make
sure the Site URL and redirect URLs point at your real domain and not at a preview address.

### 16. Check again after every change
**What goes wrong:** the next prompt to your AI tool can undo a fix. "The AI said it's fixed" is not a check.
**Check:** rerun this list after changes to tables, policies, functions or payments;
[supabase-check](https://github.com/kodev-team/supabase-check) reruns most of the database part in one paste.

---

## What this list does not do
It does not test your live app for you, and an all-clear on this list is not a promise that nothing is wrong. It
covers common mistakes in AI-built Supabase apps; your app can have others (business rules, other
services, your frontend).

## About
Made by [KODEV](https://kodev.dev). We review AI-built apps, fix what matters and retest it, for a fixed price. This
list and its SQL are free under the MIT License. Corrections are welcome as
issues or pull requests; please never post real data or keys.
