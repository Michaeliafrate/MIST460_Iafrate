from get_db_connection import get_db_connection

def check_in(reservation_id: int):
    conn = get_db_connection()
    cursor = conn.cursor(as_dict=True)

    try:
        cursor.execute("exec procCheckIn %s", (reservation_id,))
        rows = cursor.fetchall()
        conn.commit()
        return {"status_message": rows[0]["StatusMessage"]}
    except Exception as e:
        conn.rollback()
        return {"status_message": f"Error occurred: {e}"}
    finally:
        cursor.close()
        conn.close()
