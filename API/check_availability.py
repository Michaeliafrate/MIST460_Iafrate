from get_db_connection import get_db_connection
from datetime import date, time

def check_availability(
        start_date: date,
        start_time: time,
        end_time: time,
        end_date: date = None,
        room_number: str = None,
        floor: int = None,
        min_seats: int = None,
        whiteboard: bool = None
):
    conn = get_db_connection()
    cursor = conn.cursor(as_dict=True)
    cursor.execute("exec procCheckAvailability %s, %s, %s, %s, %s, %s, %s, %s",
                   (start_date, end_date, str(start_time), str(end_time),
                    room_number, floor, min_seats, whiteboard))
    rows = cursor.fetchall()
    cursor.close()
    conn.close()
    return {"data": rows}
