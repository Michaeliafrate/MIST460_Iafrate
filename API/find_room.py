from get_db_connection import get_db_connection

def find_room(floor: int = None, min_seats: int = None, whiteboard: bool = None):
    conn = get_db_connection()
    cursor = conn.cursor(as_dict=True)
    cursor.execute("exec procFindRoom %s, %s, %s", (floor, min_seats, whiteboard))
    rows = cursor.fetchall()
    cursor.close()
    conn.close()
    results = [{"RoomID": row["RoomID"], "RoomNumber": row["RoomNumber"],
                "Floor": row["Floor"], "Seats": row["Seats"],
                "Whiteboard": row["Whiteboard"], "CurrentStatus": row["CurrentStatus"]}
               for row in rows]
    return {"data": results}
