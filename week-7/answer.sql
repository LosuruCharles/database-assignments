STEP 1

**Test it**
```sql
INSERT INTO students VALUES (1, 'Amina', 'amina@example.com');
UPDATE students SET email = 'amina@school.edu' WHERE id = 1;
DELETE FROM students WHERE id = 1;

SELECT id, tbl, op, old_row, new_row, changed_by, at
FROM audit_log
ORDER BY id;
```

**What you should see**
| op | old_row | new_row |
|---|---|---|
| INSERT | NULL | full row JSON |
| UPDATE | row before (old email) | row after (new email) |
| DELETE | full row JSON | NULL |

You can also see only the fields that changed on an update:
```sql
SELECT id,
       old_row->>'email' AS old_email,
       new_row->>'email' AS new_email
FROM audit_log
WHERE op = 'UPDATE';
```

STEP 2
Here's what Step 2 does and what to expect.

**Before you run it**
- This assumes `students` has rows with `id = 1` and `id = 3`. If you deleted the test row from Step 1 or never inserted these, the statements will run without error but match 0 rows, and the audit log will get nothing new. Seed some data first if needed:
  ```sql
  INSERT INTO students VALUES
    (1, 'Amina', 'amina@example.com'),
    (2, 'Brian', 'brian@example.com'),
    (3, 'Chebet', 'chebet@example.com');
  ```
  If you re-use `id = 1` after Step 1's delete, that's fine, since the delete removed it.
- The `name` column must exist in `students`, because the query reads `old_row->>'name'`.

**What the query does**
- `->>` extracts a JSON field as text, so `was` is the value before the change and `now` is the value after.
- `ORDER BY at DESC` shows the newest changes first.

**What you should see (newest first)**

| tbl | op | was | now |
|---|---|---|---|
| students | DELETE | Chebet | NULL |
| students | UPDATE | Amina | Kofi M. |
| ... | ... | ... | ... |

Older rows from Step 1 and any seed inserts appear below these. Inserts show `was = NULL`, because there is no old row.

**Things to verify**
- The DELETE row has `now = NULL` and `was` holds the deleted student's name. This confirms the full row survives in the audit trail even though it is gone from `students`.
- The UPDATE row shows both the old and new name.
- Rows from the same statement may share nearly identical timestamps. If ordering looks odd, use `ORDER BY id DESC` instead. The identity `id` is strictly increasing, whereas `at` can tie.

**Optional check: only the changed columns on an update**
```sql
SELECT id,
       old_row->>'name' AS old_name,
       new_row->>'name' AS new_name
FROM audit_log
WHERE op = 'UPDATE'
  AND old_row->>'name' IS DISTINCT FROM new_row->>'name';
```
STEP 3
Here's what Step 3 does and what to expect.

**Before you run it**
- `SERIAL` generates ids 1 to 4 in insert order, which is why the hard-coded `parent_id` values (1, 2) work. This only holds on a fresh table. If you re-run the INSERT on an existing table, the ids will be different and the parents will point to the wrong rows (or fail the foreign key).
- Run the `CREATE TABLE` and `INSERT` first, then the recursive query as a separate statement.

**How the recursive CTE works**
- The **anchor** (first SELECT) picks the roots, rows where `parent_id IS NULL`, and starts `depth` at 0.
- The **recursive part** joins `categories` to the rows found so far, adding every child of a row already in `tree` and incrementing `depth`.
- It repeats until a pass returns no new rows, then the outer SELECT reads the full result.
- `repeat('  ', depth)` indents each name by two spaces per level.

**What you should see**

| tree |
|---|
| Electronics |
| ` Computers` (indented 2 spaces) |
| ` Phones` (indented 2 spaces) |
| `    Laptops` (indented 4 spaces) |

**Important: the ordering is not a true tree view**
`ORDER BY depth, name` sorts level by level, so you get all depth-0 rows, then all depth-1 rows, and so on. Here that gives Computers, Phones, Laptops. Laptops is a child of Computers, but Phones appears between them. The indentation shows the nesting, but the row order does not keep each child under its parent.

For a proper depth-first display, carry a path and sort by it:

```sql
WITH RECURSIVE tree AS (
  SELECT id, name, parent_id, 0 AS depth, name AS path
  FROM categories
  WHERE parent_id IS NULL

  UNION ALL

  SELECT c.id, c.name, c.parent_id, t.depth + 1, t.path || ' > ' || c.name
  FROM categories c
  JOIN tree t ON c.parent_id = t.id
)
SELECT repeat('  ', depth) || name AS tree, path
FROM tree
ORDER BY path;
```

Expected order: Electronics, Computers, Laptops, Phones, with `path` showing values like `Electronics > Computers > Laptops`.

**Things to verify**
- Four rows come back, one per category. If you see fewer, check the `parent_id` values in your inserts.
- `depth` for Laptops is 2, Computers and Phones are 1, Electronics is 0.

**Worth knowing**
- If a cycle ever existed (for example, setting Electronics' parent to Laptops), the recursion would never terminate. For real data, add a depth limit (`WHERE t.depth < 10`) or track visited ids in an array.
- Deleting a parent that still has children will fail because of the foreign key. That is the default `NO ACTION` behavior.
STEP 4
Here's what Step 4 does, how to set it up, and what to check.

**Before you run it**
- Flyway looks in `sql/` by default, not `migrations/`. Since your files are in `migrations/`, point to it explicitly:
  ```bash
  flyway -url=jdbc:postgresql://localhost/bootcamp \
         -user=postgres \
         -locations=filesystem:migrations \
         migrate
  ```
  Use the same `-locations` flag (and URL/user) with `flyway info`, or put them in `conf/flyway.conf` so every command picks them up:
  ```
  flyway.url=jdbc:postgresql://localhost/bootcamp
  flyway.user=postgres
  flyway.locations=filesystem:migrations
  ```
- The `bootcamp` database must exist, and you may need `-password=...` (or `flyway.password`) for the `postgres` user.
- Flyway needs the PostgreSQL JDBC driver, which ships with the standard distribution.
- File names must follow `V<version>__<description>.sql`: capital V, two underscores.

**What goes in each file**
- `V1__core_tables.sql`: your `students` table (the one the audit trigger attaches to).
- `V2__audit_log.sql`: the `audit_log` table, the `audit()` function and the `trg_audit` trigger from Step 1. This must come after V1, because the trigger references `students`.
- `V3__categories.sql`: the `categories` table and the seed INSERT from Step 3.

Put only DDL and seed data in the files, not the test statements from Step 2.

**Important: you already created these objects manually**
If you ran Steps 1 to 3 in the `bootcamp` database, `migrate` will fail with "relation already exists". Pick one:
1. **Clean slate (simplest):** drop the manual objects, or use a fresh database, then run `migrate`.
   ```sql
   DROP TABLE IF EXISTS categories, audit_log, students CASCADE;
   DROP FUNCTION IF EXISTS audit() CASCADE;
   ```
2. **Baseline:** `flyway baseline -baselineVersion=3` marks the existing schema as already at V3, and Flyway skips V1 to V3. Good for adopting Flyway on an existing database, but it would defeat the point of the lab here.

**What you should see**

`migrate` output ends with something like:
```
Successfully applied 3 migrations to schema "public", now at version v3
```

`flyway info` shows a table like:

| Version | Description | Type | State |
|---|---|---|---|
| 1 | core tables | SQL | Success |
| 2 | audit log | SQL | Success |
| 3 | categories | SQL | Success |

Flyway also creates a `flyway_schema_history` table recording each version, checksum, who applied it and when.

**Things to verify**
- All three rows show `Success`, none `Pending` or `Failed`.
- Re-run `flyway migrate`. It should report "Schema is up to date. No migration necessary." That confirms migrations are idempotent from Flyway's perspective.
- Query the history: `SELECT version, description, success FROM flyway_schema_history;`

**Worth knowing**
- **Never edit an applied migration.** Flyway stores a checksum, and changing V1 later makes `migrate` fail validation. Add a `V4__...` file for any new change.
- If a migration fails midway, PostgreSQL rolls back its DDL (it supports transactional DDL), so you can fix the file and re-run. If it's recorded as failed, use `flyway repair`.

STEP 5
Here's what Step 5 does, what it quietly gets wrong for least privilege, and how to test it.

**Before you run it**
- Run it as a superuser or the owner of the objects (the same `postgres` user that ran the migrations). Otherwise the GRANTs on tables you don't own will fail.
- The tables must already exist, because `ALL TABLES IN SCHEMA` only covers tables present at the moment you run it. Tables created later (a future `V4` migration) get no grants unless you add default privileges:
  ```sql
  ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO app_read;
  ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_write;
  ```
  Default privileges apply to objects created by the role that runs this statement, so run it as the role that runs your migrations.
- Replace `'strong-secret'` with a real password. In the lab it's fine, but never commit a literal password.

**What each statement does**
- `CREATE ROLE` makes two group-style roles with no login. They hold permissions only.
- `CONNECT` on the database and `USAGE` on the schema are both required before any table grant takes effect. Without `USAGE`, queries fail with "permission denied for schema public".
- `CREATE USER api ... IN ROLE app_write` makes a login role that inherits `app_write`'s privileges.

**Gaps against least privilege**
1. **`app_write` can modify `audit_log`.** `ALL TABLES` includes it, so `api` can UPDATE or DELETE audit rows and erase its own trail. Fix:
   ```sql
   REVOKE UPDATE, DELETE ON audit_log FROM app_write;
   REVOKE INSERT ON audit_log FROM app_write;
   ```
   Then make the trigger function run as its owner, so inserts into the log still work:
   ```sql
   ALTER FUNCTION audit() SECURITY DEFINER SET search_path = public;
   ```
   Without `SECURITY DEFINER`, the `INSERT INTO audit_log` inside the trigger runs with the caller's rights and fails once you revoke INSERT. With it, `changed_by` still records the real user, because `current_user` is evaluated in the audit table's column default... actually inside a `SECURITY DEFINER` function `current_user` returns the function owner, so use `session_user` in the default if you want the login role recorded:
   ```sql
   ALTER TABLE audit_log ALTER COLUMN changed_by SET DEFAULT session_user;
   ```
2. **`app_write` can modify `flyway_schema_history`.** Revoke all on it from both roles, since the application has no business touching migration history:
   ```sql
   REVOKE ALL ON flyway_schema_history FROM app_write, app_read;
   ```
3. **`app_read` can read `audit_log`** and the history table. Decide whether that's acceptable. If not, revoke SELECT on them too.
4. **No sequence privileges.** `categories.id` is `SERIAL`, so `api` inserting into it fails with "permission denied for sequence categories_id_seq". Add:
   ```sql
   GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO app_write;
   ```
5. **`PUBLIC` defaults.** By default every role can connect to a database. To make the grants meaningful, run `REVOKE CONNECT ON DATABASE bootcamp FROM PUBLIC;`. On PostgreSQL 14 and earlier, `PUBLIC` can also create objects in `public`, so run `REVOKE CREATE ON SCHEMA public FROM PUBLIC;` (15+ already restricts this).

**Test it**
```sql
-- as postgres: switch identity without a password
SET ROLE api;
SELECT * FROM students;                          -- works
INSERT INTO students VALUES (10, 'Test', 't@x.org');   -- works
DELETE FROM audit_log;                           -- should fail: permission denied
DROP TABLE students;                             -- should fail: must be owner
RESET ROLE;

SET ROLE app_read;
SELECT * FROM students;                          -- works
INSERT INTO students VALUES (11, 'X', 'x@x.org');      -- should fail
RESET ROLE;
```
You can also connect for real with `psql -h localhost -U api bootcamp`.

**What you should see**
- Allowed statements succeed, and denied ones return `ERROR: permission denied for table ...`.
- `\dp audit_log` in psql shows the privilege list. Check that `app_write` no longer has `a` (INSERT), `w` (UPDATE) or `d` (DELETE) on it.
- After the test insert, check that the audit row's `changed_by` shows `api` and not `postgres`.

**Worth knowing**
- Because roles are cluster-wide objects, not per database, re-running `CREATE ROLE` fails with "role already exists". Use `DROP ROLE` first if you are repeating the lab.
- Keep role creation out of your Flyway files if the same migrations run in several environments, or guard it with `DO $$ ... IF NOT EXISTS ... $$`.

