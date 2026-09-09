from get_db_connection import get_db_connection

def register_user(
        email: str,
        password: str,
        first_name: str = None,
        last_name: str = None,
        user_role: str = "Student"
):
    conn = get_db_connection()
    cursor = conn.cursor(as_dict=True)

    try:
        cursor.execute("exec procRegisterUser %s, %s, %s, %s, %s",
                       (email, password, first_name, last_name, user_role))
        rows = cursor.fetchall()
        conn.commit()
        app_user_id = int(rows[0]["AppUserID"]) if rows else None
        return {"status_message": f"User {app_user_id} registered successfully.",
                "app_user_id": app_user_id}
    except Exception as e:
        conn.rollback()
        return {"status_message": f"Error occurred: {e}"}
    finally:
        cursor.close()
        conn.close()
