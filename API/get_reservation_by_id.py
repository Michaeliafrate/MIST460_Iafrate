from get_db_connection import get_db_connection

def get_reservation_by_id(reservation_id: int):
    conn = get_db_connection()
    cursor = conn.cursor(as_dict=True)
    cursor.execute("exec procGetReservationByID %s", (reservation_id,))
    rows = cursor.fetchall()
    cursor.close()
    conn.close()
    return {"data": rows}
