from get_db_connection import get_db_connection
from datetime import date

def get_room_schedule(slot_date: date, room_id: int = None, free_only: bool = False):
    conn = get_db_connection()
    cursor = conn.cursor(as_dict=True)
    cursor.execute("exec procGetRoomSchedule %s, %s, %s", (slot_date, room_id, free_only))
    rows = cursor.fetchall()
    cursor.close()
    conn.close()
    return {"data": rows}
