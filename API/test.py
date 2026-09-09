"""Exercise the study room reservation database from application code.

Run after the three scripts in Data have been applied:
    python run_sql.py
    python API/test.py

Walks the eight student requirements in order, then deliberately breaks the
rules to prove the database defends itself.

Everything that writes happens inside a transaction that is rolled back, so
running this repeatedly leaves the data exactly as it found it.
"""
import os
import sys
from datetime import date, timedelta

# azure_sql.py lives at the project root, one level up from API/.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import pyodbc  # noqa: E402

from azure_sql import DATABASE, get_connection  # noqa: E402

TODAY = date.today()
YESTERDAY = TODAY - timedelta(days=1)


def heading(text):
    print(f"\n{'=' * 68}\n{text}\n{'=' * 68}")


def show(cur, limit=10):
    """Print the current result set, then any that follow it.

    A procedure can return several result sets (procFindRoomAvailableNow
    returns the times it searched, then the rooms). nextset() walks them.
    """
    while True:
        if cur.description:
            columns = [d[0] for d in cur.description]
            rows = cur.fetchall()
            print("  " + " | ".join(columns))
            print("  " + "-" * 60)
            for row in rows[:limit]:
                print("  " + " | ".join("" if v is None else str(v) for v in row))
            if not rows:
                print("  (no rows)")
            elif len(rows) > limit:
                print(f"  ... {len(rows) - limit} more")
        if not cur.nextset():
            break


def expect_error(conn, label, sql, *params):
    """Run something that SHOULD fail, and report the error it raised.

    Each failure is followed by a rollback: a trigger that calls ROLLBACK
    TRANSACTION has already killed the transaction, and the connection needs
    to be put back into a clean state before the next test.

    Draining the result sets with nextset() is essential and easy to miss.
    pyodbc reports an error from a LATER statement in a multi-statement
    batch only once you advance past the earlier statements' results. A
    batch that books a room (returning a row) and then breaks a rule looks
    like a total success until you walk to the end of the results -- which
    is exactly how a broken rule can appear to pass.
    """
    try:
        probe = conn.cursor()
        probe.execute(sql, *params)
        while probe.nextset():
            pass
        print(f"  {label}\n     NO ERROR -- the rule did not hold!")
    except pyodbc.Error as exc:
        message = str(exc)
        detail = message.split("]")[-1].split("(")[0].strip() or message[:90]
        print(f"  {label}\n     blocked: {detail}")
    finally:
        try:
            conn.rollback()
        except pyodbc.Error:
            pass


with get_connection() as conn:
    conn.autocommit = False          # nothing is permanent until commit()
    cur = conn.cursor()
    print(f"Connected to {DATABASE}")

    # ---------------------------------------------------------------
    heading("Requirements 2 & 3 -- room specifications")
    cur.execute(
        "SELECT RoomNumber, Floor, Seats, "
        "       CASE WHEN Whiteboard = 1 THEN 'yes' ELSE 'no' END AS Whiteboard, "
        "       CurrentStatus "
        "FROM Room ORDER BY Floor, RoomNumber"
    )
    show(cur, limit=10)

    # ---------------------------------------------------------------
    heading("Requirement 1 -- 4th floor rooms free today, 8:00 to 8:30")
    print("  EXEC procCheckAvailability @StartDate, '08:00', '08:30', @Floor=4")
    cur.execute(
        "EXEC procCheckAvailability @StartDate = ?, @StartTime = '08:00:00', "
        "@EndTime = '08:30:00', @Floor = 4",
        TODAY,
    )
    show(cur)

    heading("Requirement 1 -- same window, but only rooms seating 6+ with a whiteboard")
    cur.execute(
        "EXEC procCheckAvailability @StartDate = ?, @StartTime = '08:00:00', "
        "@EndTime = '08:30:00', @MinSeats = 6, @NeedsWhiteboard = 1",
        TODAY,
    )
    show(cur)

    # ---------------------------------------------------------------
    heading("Requirement 4 -- today's schedule for room 130 (all 5 slots)")
    cur.execute(
        "SELECT TOP 5 RoomNumber, Date, StartTime, EndTime, SlotStatus, "
        "       ISNULL(BookedByEmail, '') AS BookedBy "
        "FROM viewRoomSchedule "
        "WHERE RoomNumber = '130' AND Date = ? "
        "ORDER BY StartTime",
        TODAY,
    )
    show(cur, limit=12)

    # ---------------------------------------------------------------
    heading("Requirement 8 -- find me a room available now (next 60 minutes)")
    cur.execute("EXEC procFindRoomAvailableNow 60")
    show(cur, limit=6)

    # ---------------------------------------------------------------
    heading("Existing reservations (viewReservationDetail)")
    cur.execute(
        "SELECT ReservationID, UserName, ISNULL(RoomNumber, '-') AS Room, "
        "       Date, StartTime, EndTime, TotalTimeComputed, ReservationStatus "
        "FROM viewReservationDetail ORDER BY ReservationID"
    )
    show(cur)

    # The function computes the truth from the slots; the column is a cache.
    total = cur.execute("SELECT dbo.fnReservationMinutes(?)", 1).fetchval()
    stored = cur.execute(
        "SELECT TotalTime FROM Reservation WHERE ReservationID = 1"
    ).fetchval()
    print(f"\n  fnReservationMinutes(1) = {total} min   (stored column says {stored})")

    free = cur.execute(
        "SELECT dbo.fnIsRoomFree(1, ?, '08:00:00', '08:30:00')", TODAY
    ).fetchval()
    print(f"  fnIsRoomFree(room 130, today 8:00-8:30) = {free}   (0 because it is booked)")

    # ---------------------------------------------------------------
    heading("Requirements 5 & 7 -- book a room, check in, check out")

    new_id = cur.execute(
        "DECLARE @id INT; "
        "EXEC procMakeReservation ?, ?, ?, ?, ?, @id OUTPUT; "
        "SELECT @id;",
        5, 3, TODAY, "08:45:00", "09:15:00",   # user 5, room 230, 30 minutes
    ).fetchval()
    print(f"  procMakeReservation -> reservation #{new_id} "
          f"(room 230, {TODAY}, 08:45-09:15)")

    minutes = cur.execute("SELECT dbo.fnReservationMinutes(?)", new_id).fetchval()
    print(f"  fnReservationMinutes({new_id}) = {minutes} min = "
          f"{minutes // 15} slots of 15 minutes")

    cur.execute("EXEC procCheckIn ?", new_id)
    status, room_state = cur.execute(
        "SELECT r.ReservationStatus, rm.CurrentStatus "
        "FROM Reservation AS r "
        "JOIN RoomAvailability AS a ON a.ReservationID = r.ReservationID "
        "JOIN Room AS rm ON rm.RoomID = a.RoomID "
        "WHERE r.ReservationID = ?", new_id
    ).fetchone()
    print(f"  procCheckIn  -> reservation is '{status}', room reads '{room_state}'")

    cur.execute("EXEC procCheckOut ?", new_id)
    status, room_state = cur.execute(
        "SELECT r.ReservationStatus, rm.CurrentStatus "
        "FROM Reservation AS r "
        "JOIN RoomAvailability AS a ON a.ReservationID = r.ReservationID "
        "JOIN Room AS rm ON rm.RoomID = a.RoomID "
        "WHERE r.ReservationID = ?", new_id
    ).fetchone()
    print(f"  procCheckOut -> reservation is '{status}', room reads '{room_state}'")

    conn.rollback()
    print("  rolled back -- the test reservation was not kept")

    # ---------------------------------------------------------------
    heading("Now break the rules on purpose -- the database should refuse")

    expect_error(
        conn,
        "Requirement 5: booking 3 hours (max is 2)",
        "DECLARE @id INT; EXEC procMakeReservation ?, ?, ?, ?, ?, @id OUTPUT;",
        1, 4, TODAY, "09:00:00", "12:00:00",
    )

    expect_error(
        conn,
        "Requirement 5: booking 08:00 to 08:20 (not a 15 minute increment)",
        "DECLARE @id INT; EXEC procMakeReservation ?, ?, ?, ?, ?, @id OUTPUT;",
        1, 4, TODAY, "08:00:00", "08:20:00",
    )

    expect_error(
        conn,
        "Booking a room that is already taken (room 130 today 8:00-8:30)",
        "DECLARE @id INT; EXEC procMakeReservation ?, ?, ?, ?, ?, @id OUTPUT;",
        2, 1, TODAY, "08:00:00", "08:30:00",
    )

    expect_error(
        conn,
        "Booking a date in the past",
        "DECLARE @id INT; EXEC procMakeReservation ?, ?, ?, ?, ?, @id OUTPUT;",
        1, 4, YESTERDAY, "08:00:00", "08:30:00",
    )

    expect_error(
        conn,
        "Requirement 6: one user, two DIFFERENT rooms at the same time",
        # Book room 130 first, then try room 230 at the same moment for the
        # same student. The trigger rolls back both.
        "DECLARE @a INT, @b INT; "
        "EXEC procMakeReservation ?, 1, ?, '09:00:00', '09:15:00', @a OUTPUT; "
        "EXEC procMakeReservation ?, 3, ?, '09:00:00', '09:15:00', @b OUTPUT;",
        2, TODAY, 2, TODAY,
    )

    expect_error(
        conn,
        "Reopening a cancelled reservation (#5 in the sample data)",
        "UPDATE Reservation SET ReservationStatus = 'Booked' WHERE ReservationID = 5",
    )

    expect_error(
        conn,
        "Slots from two different rooms in one reservation",
        "UPDATE RoomAvailability SET ReservationID = 1, AvailabilityStatus = 0 "
        "WHERE RoomID = 2 AND Date = ? AND StartTime = '08:30:00'",
        TODAY,
    )

    # ---------------------------------------------------------------
    heading("Requirement 6 -- but the SAME user, SAME day, different times is fine")
    cur.execute(
        "SELECT ReservationID, UserName, RoomNumber, Date, StartTime, EndTime "
        "FROM viewReservationDetail "
        "WHERE AppUserID = 1 AND Date = ? ORDER BY StartTime",
        TODAY,
    )
    show(cur)
    print("  Three reservations, one day, no overlap -- exactly what rule 6 allows.")

    conn.rollback()

print("\nDone. Nothing was permanently changed.")
