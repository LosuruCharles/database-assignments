Here's the lab step by step, with the places it commonly breaks. I'm assuming Linux with PostgreSQL 12 or later, run as the `postgres` user where noted.

## Step 1: Logical backup
The commands work as written. Compare the restored copy to the original to confirm it's good:

```bash
psql -d bootcamp -c "SELECT count(*) FROM students;"
psql -d bootcamp_check -c "SELECT count(*) FROM students;"
```

## Step 2: WAL archiving
**Problem:** the server runs as the `postgres` OS user, so `/home/$USER/...` won't point to your home directory. Use an absolute path that `postgres` owns:

```bash
sudo mkdir -p /var/lib/postgresql/backups/wal
sudo chown -R postgres:postgres /var/lib/postgresql/backups
```

```
wal_level = replica
archive_mode = on
archive_command = 'test ! -f /var/lib/postgresql/backups/wal/%f && cp %p /var/lib/postgresql/backups/wal/%f'
```

Restart, then force a segment switch and confirm archiving works:

```sql
SELECT pg_switch_wal();
SELECT archived_count, failed_count, last_archived_wal FROM pg_stat_archiver;
```

`failed_count` should stay at 0. Then take the base backup as `postgres` into a new directory, because `-D` must not already exist or must be empty:

```bash
sudo -u postgres pg_basebackup -D /var/lib/postgresql/backups/base -Ft -z -Xs -P
```

This produces `base.tar.gz` and `pg_wal.tar.gz`.

## Step 3: Disaster and PITR
1. Record the time first. Run `SELECT now();`, note the timestamp with its timezone, then run the `DELETE`.
2. Force the delete into the archive with `SELECT pg_switch_wal();`. Otherwise the segment containing it may not be archived yet.
3. Stop PostgreSQL: `sudo systemctl stop postgresql`.
4. Move the old data directory aside instead of deleting it:
   ```bash
   sudo mv /var/lib/postgresql/16/main /var/lib/postgresql/16/main.old
   sudo -u postgres mkdir -m 700 /var/lib/postgresql/16/main
   sudo -u postgres tar -xzf /var/lib/postgresql/backups/base/base.tar.gz -C /var/lib/postgresql/16/main
   sudo -u postgres tar -xzf /var/lib/postgresql/backups/base/pg_wal.tar.gz -C /var/lib/postgresql/16/main/pg_wal
   ```
   Adjust `16/main` to your version and path.
5. Set the recovery options. The lab's snippet is incomplete, and `~` isn't reliable here, so use absolute paths:
   ```
   restore_command = 'cp /var/lib/postgresql/backups/wal/%f %p'
   recovery_target_time = '2025-06-01 10:00:00+00'
   recovery_target_action = 'promote'
   ```
6. **Create the signal file. Without it, PostgreSQL 12+ skips recovery entirely:**
   ```bash
   sudo -u postgres touch /var/lib/postgresql/16/main/recovery.signal
   ```
7. Start PostgreSQL and watch the log. It should say it is recovering to the target time and then promote.
8. Verify with `SELECT count(*) FROM students;`. The rows should be back.

The target time must be after the base backup finished and before the `DELETE`.

## Step 4: Streaming standby
- The `pg_hba.conf` line is fine, but reload it with `SELECT pg_reload_conf();`.
- The standby runs on the same machine, so it needs a different port. Avoid a password prompt by using `PGPASSWORD=reppass` in front of the command:
  ```bash
  PGPASSWORD=reppass pg_basebackup -h 127.0.0.1 -U replicator -D ~/standby -R -P
  chmod 700 ~/standby
  ```
  `-R` creates `standby.signal` and the `primary_conninfo` setting for you.
- Add `port = 5433` to `~/standby/postgresql.auto.conf`, then start it:
  ```bash
  pg_ctl -D ~/standby -o "-p 5433" start
  ```
- On Debian/Ubuntu, the config files live in `/etc/postgresql/...`, not in the data directory. If `pg_ctl` complains about a missing config, add `-o "-c config_file=/etc/postgresql/16/main/postgresql.conf -p 5433"`.

## Step 5: Monitor
On the primary, `state` should read `streaming` and `lag_bytes` should be near 0. Then prove replication works:

```sql
-- primary (port 5432)
INSERT INTO students ... ;   -- any test row
```
```bash
# standby
psql -p 5433 -d bootcamp -c "SELECT pg_is_in_recovery();"   # true
psql -p 5433 -d bootcamp -c "SELECT count(*) FROM students;" # includes the new row
```

Writes on the standby should fail with a read-only error, which confirms it's a true replica.

Which step are you on, and do you have an error message? I can troubleshoot it, or help write up the lab report.
