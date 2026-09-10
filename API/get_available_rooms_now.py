from get_db_connection import get_db_connection

def get_available_rooms_now(floor: int = None, min_seats: int = None):
    conn = get_db_connection()
    cursor = conn.cursor(as_dict=True)
    cursor.execute("exec procFindRoomAvailableNow %s, %s", (floor, min_seats))
    rows = cursor.fetchall()
    cursor.close()
    conn.close()
    return {"data": rows}
