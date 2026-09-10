from get_db_connection import get_db_connection

def register_user(
        first_name: str,
        last_name: str,
        email: str,
        password: str,
        user_role: str = "Student"
):
    conn = get_db_connection()
    cursor = conn.cursor(as_dict=True)

    try:
        cursor.execute("exec procRegisterUser %s, %s, %s, %s, %s",
                       (first_name, last_name, email, password, user_role))
        rows = cursor.fetchall()
        conn.commit()
        app_user_id = rows[0]["AppUserID"]
        return {"status_message": rows[0]["StatusMessage"],
                "app_user_id": app_user_id if app_user_id else None}
    except Exception as e:
        conn.rollback()
        return {"status_message": f"Error occurred: {e}"}
    finally:
        cursor.close()
        conn.close()
