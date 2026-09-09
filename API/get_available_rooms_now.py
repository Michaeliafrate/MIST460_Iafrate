from get_db_connection import get_db_connection

def get_available_rooms_now(minutes: int = 60, floor: int = None, min_seats: int = None):
    conn = get_db_connection()
    cursor = conn.cursor(as_dict=True)
    cursor.execute("exec procFindRoomAvailableNow %s, %s, %s", (minutes, floor, min_seats))
    searched = cursor.fetchall()
    rooms = []
    if cursor.nextset():
        rooms = cursor.fetchall()
    cursor.close()
    conn.close()
    return {"searched": searched[0] if searched else {}, "data": rooms}
