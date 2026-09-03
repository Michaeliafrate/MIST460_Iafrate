"""Verify the Azure SQL database is reachable and report server info and tables."""
import pyodbc

from azure_sql import DATABASE, get_connection

# A serverless database that has auto-paused rejects the first connection while
# it resumes (error 40613); the second attempt a few seconds later succeeds.
try:
    conn = get_connection()
except pyodbc.Error as exc:
    message = str(exc)
    if "40613" in message:
        raise SystemExit(
            "The database is resuming from its auto-paused state. "
            "Wait about a minute and run this again."
        )
    if "40615" in message or "not allowed to access" in message:
        raise SystemExit(
            "Blocked by the server firewall. In the Azure portal open the SQL "
            "server -> Networking and add your current client IP."
        )
    if "4060" in message and "Cannot open database" in message:
        # The login works but AZURE_SQL_DATABASE names something that is not
        # there -- ask master what the real database names are.
        with get_connection("master") as master:
            names = [
                row[0] for row in master.cursor().execute(
                    "SELECT name FROM sys.databases "
                    "WHERE name <> 'master' ORDER BY name"
                ).fetchall()
            ]
        raise SystemExit(
            f"There is no database named {DATABASE!r} on this server.\n"
            f"Databases on the server: {', '.join(names) or '(none)'}\n"
            "Put the right one in AZURE_SQL_DATABASE in .env."
        )
    raise

with conn:
    cur = conn.cursor()
    version = cur.execute("SELECT @@VERSION").fetchval()
    edition = cur.execute(
        "SELECT DATABASEPROPERTYEX(DB_NAME(), 'Edition')").fetchval()
    tables = [
        f"{schema}.{name}"
        for schema, name in cur.execute(
            "SELECT TABLE_SCHEMA, TABLE_NAME FROM INFORMATION_SCHEMA.TABLES "
            "WHERE TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_SCHEMA, TABLE_NAME"
        ).fetchall()
    ]

print(f"Connected to {DATABASE}")
print(f"  {version.splitlines()[0].strip()}")
print(f"  edition: {edition}")
print(f"  tables ({len(tables)}): {', '.join(tables) or '(none)'}")
