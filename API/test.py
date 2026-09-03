"""Exercise the schema and programming objects against Azure SQL.

Run after the three scripts in Data/RDB have been applied. Reads the summary
view, calls the scalar function, and places an order through the stored
procedure inside a transaction that is rolled back, so running this repeatedly
leaves the data as it found it.
"""
import os
import sys

# azure_sql.py lives at the project root, one level up from API/.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from azure_sql import DATABASE, get_connection  # noqa: E402

with get_connection() as conn:
    conn.autocommit = False
    cur = conn.cursor()

    print(f"Connected to {DATABASE}\n")

    print("vw_OrderSummary")
    for row in cur.execute(
        "SELECT OrderID, CustomerName, Status, LineCount, OrderTotal "
        "FROM dbo.vw_OrderSummary ORDER BY OrderID"
    ).fetchall():
        print(f"  #{row.OrderID}  {row.CustomerName:<18} {row.Status:<10} "
              f"lines={row.LineCount}  ${row.OrderTotal}")

    total = cur.execute("SELECT dbo.fn_OrderTotal(?)", 1).fetchval()
    print(f"\nfn_OrderTotal(1) = ${total}")

    print("\nusp_PlaceOrder(customer=2, product=3, qty=2)")
    new_id = cur.execute(
        "DECLARE @id INT; EXEC dbo.usp_PlaceOrder ?, ?, ?, @id OUTPUT; "
        "SELECT @id;", 2, 3, 2
    ).fetchval()
    print(f"  created order #{new_id}, total ${cur.execute('SELECT dbo.fn_OrderTotal(?)', new_id).fetchval()}")

    conn.rollback()
    print("  rolled back -- the test order was not kept")
