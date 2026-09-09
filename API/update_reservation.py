from get_db_connection import get_db_connection
from datetime import date, time

def update_reservation(
        reservation_id: int,
        room_id: int,
        slot_date: date,
        start_time: time,
        end_time: time
):
    conn = get_db_connection()
    cursor = conn.cursor(as_dict=True)

    try:
        cursor.execute("exec procUpdateReservation %s, %s, %s, %s, %s",
                       (reservation_id, room_id, slot_date,
                        str(start_time), str(end_time)))
        cursor.fetchall()
        conn.commit()
        return {"status_message": f"Reservation {reservation_id} updated successfully."}
    except Exception as e:
        conn.rollback()
        return {"status_message": f"Error occurred: {e}"}
    finally:
        cursor.close()
        conn.close()
