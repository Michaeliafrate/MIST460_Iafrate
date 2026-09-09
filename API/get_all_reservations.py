from get_db_connection import get_db_connection

def get_all_reservations(app_user_id: int = None, reservation_status: str = None):
    conn = get_db_connection()
    cursor = conn.cursor(as_dict=True)
    cursor.execute("exec procGetAllReservations %s, %s", (app_user_id, reservation_status))
    rows = cursor.fetchall()
    cursor.close()
    conn.close()
    return {"data": rows}
