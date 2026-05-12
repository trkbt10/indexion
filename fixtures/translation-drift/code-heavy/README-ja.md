# sql-runner

パラメータ化文をサポートする軽量 SQL ランナー。

## 例

```sql
SELECT id, name, created_at
FROM users
WHERE created_at > $1
ORDER BY created_at DESC
LIMIT $2;
```

```sql
INSERT INTO audit_log (actor, event, payload)
VALUES ($1, $2, $3::jsonb);
```

```sql
UPDATE settings
SET value = $2, updated_at = NOW()
WHERE key = $1;
```

```sql
DELETE FROM sessions
WHERE last_seen < NOW() - INTERVAL '30 days';
```

## CLI

```bash
sql-runner --host=localhost --port=5432 query.sql
```
