from get_db_connection import get_db_connection
from datetime import date, time

def make_reservation(
        app_user_id: int,
        room_id: int,
        slot_date: date,
        start_time: time,
        end_time: time
):
    conn = get_db_connection()
    cursor = conn.cursor(as_dict=True)

    try:
        cursor.execute("exec procMakeReservation %s, %s, %s, %s, %s",
                       (app_user_id, room_id, slot_date,
                        str(start_time), str(end_time)))
        rows = cursor.fetchall()
        conn.commit()
        reservation_id = rows[0]["ReservationID"]
        return {"status_message": rows[0]["StatusMessage"],
                "reservation_id": reservation_id if reservation_id else None}
    except Exception as e:
        conn.rollback()
        return {"status_message": f"Error occurred: {e}"}
    finally:
        cursor.close()
        conn.close()
