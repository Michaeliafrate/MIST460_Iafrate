"""Apply the project's .sql scripts to Azure SQL from the command line.

The Azure portal query editor works, but it means pasting four files by hand
every time the schema changes. This runs them in the right order instead:

    python run_sql.py            # CreateTables, InsertData, ProgrammingObjects
    python run_sql.py Data/InsertDataIafrate.sql      # just one file

Why the file needs splitting: GO is NOT a SQL statement. It is a separator
that client tools (SSMS, sqlcmd) understand to mean "send everything above
as one batch". pyodbc has never heard of it, so sending a whole file at once
fails on the first CREATE VIEW -- which must be the first statement in its
batch. So this splits on GO and sends each batch separately.
"""
import os
import re
import sys

import pyodbc

from azure_sql import DATABASE, get_connection

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "Data")

# The order matters: tables, then the rows, then the objects built on both.
DEFAULT_SCRIPTS = [
    os.path.join(DATA, "CreateTableIafrate.sql"),
    os.path.join(DATA, "InsertDataIafrate.sql"),
    os.path.join(DATA, "DatabaseProgrammingObjectsIafrate.sql"),
]

# A line containing only GO (any case, optional whitespace) ends a batch.
GO = re.compile(r"^\s*GO\s*;?\s*$", re.IGNORECASE | re.MULTILINE)


def split_batches(script):
    return [b for b in GO.split(script) if b.strip()]


def run_script(conn, path, label=None):
    """Send one .sql file batch by batch, printing any result sets."""
    with open(path, encoding="utf-8") as handle:
        script = handle.read()

    batches = split_batches(script)
    name = label or os.path.basename(path)
    print(f"\n=== {name}  ({len(batches)} batches) ===")

    cur = conn.cursor()
    for number, batch in enumerate(batches, start=1):
        try:
            cur.execute(batch)
            # A batch may return several result sets (the receipt SELECTs).
            while True:
                if cur.description:
                    columns = [d[0] for d in cur.description]
                    rows = cur.fetchall()
                    print(f"  [{number}] {', '.join(columns)}")
                    for row in rows[:15]:
                        print("      " + " | ".join("" if v is None else str(v) for v in row))
                    if len(rows) > 15:
                        print(f"      ... {len(rows) - 15} more rows")
                if not cur.nextset():
                    break
        except pyodbc.Error as exc:
            # Show the batch that failed -- "incorrect syntax near ')'" is
            # useless without knowing which of 40 batches it came from.
            first_line = batch.strip().splitlines()[0][:70]
            print(f"  [{number}] FAILED near: {first_line}")
            raise SystemExit(f"\n{name} batch {number} failed:\n{exc}")

    print(f"  {name}: OK")


def main():
    scripts = [os.path.abspath(a) for a in sys.argv[1:]] or DEFAULT_SCRIPTS

    with get_connection() as conn:
        # DDL and the DBCC reseeds want to commit as they go; without this
        # a failure halfway leaves the connection holding an open
        # transaction and the whole run rolls back on disconnect.
        conn.autocommit = True
        print(f"Connected to {DATABASE}")
        for path in scripts:
            if not os.path.exists(path):
                raise SystemExit(f"No such script: {path}")
            run_script(conn, path)

    print("\nAll scripts applied.")


if __name__ == "__main__":
    main()
