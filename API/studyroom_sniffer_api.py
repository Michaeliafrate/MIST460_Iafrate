from fastapi import FastAPI
from find_room import find_room
from check_availability import check_availability
from get_available_rooms_now import get_available_rooms_now
from get_room_schedule import get_room_schedule
from get_all_reservations import get_all_reservations
from get_reservation_by_id import get_reservation_by_id
from register_user import register_user
from make_reservation import make_reservation
from update_reservation import update_reservation
from check_in import check_in
from check_out import check_out
from cancel_reservation import cancel_reservation
from datetime import date, time

app = FastAPI()

@app.get("/find_room/")
def find_room_api(floor: int = None, min_seats: int = None, whiteboard: bool = None):
    return find_room(floor=floor, min_seats=min_seats, whiteboard=whiteboard)

@app.get("/check_availability/")
def check_availability_api(
        start_date: date,
        start_time: time,
        end_time: time,
        end_date: date = None,
        room_number: str = None,
        floor: int = None,
        min_seats: int = None,
        whiteboard: bool = None
):
    return check_availability(
        start_date=start_date,
        start_time=start_time,
        end_time=end_time,
        end_date=end_date,
        room_number=room_number,
        floor=floor,
        min_seats=min_seats,
        whiteboard=whiteboard
    )

@app.get("/get_available_rooms_now/")
def get_available_rooms_now_api(floor: int = None, min_seats: int = None):
    return get_available_rooms_now(floor=floor, min_seats=min_seats)

@app.get("/get_room_schedule/")
def get_room_schedule_api(slot_date: date, room_id: int = None, free_only: bool = False):
    return get_room_schedule(slot_date=slot_date, room_id=room_id, free_only=free_only)

@app.get("/get_all_reservations/")
def get_all_reservations_api(app_user_id: int = None, reservation_status: str = None):
    return get_all_reservations(app_user_id=app_user_id, reservation_status=reservation_status)

@app.get("/get_reservation_by_id/")
def get_reservation_by_id_api(reservation_id: int):
    return get_reservation_by_id(reservation_id=reservation_id)

@app.post("/register_user/")
def register_user_api(
        first_name: str,
        last_name: str,
        email: str,
        password: str,
        user_role: str = "Student"
):
    return register_user(
        first_name=first_name,
        last_name=last_name,
        email=email,
        password=password,
        user_role=user_role
    )

@app.post("/make_reservation/")
def make_reservation_api(
        app_user_id: int,
        room_id: int,
        slot_date: date,
        start_time: time,
        end_time: time
):
    return make_reservation(
        app_user_id=app_user_id,
        room_id=room_id,
        slot_date=slot_date,
        start_time=start_time,
        end_time=end_time
    )

@app.post("/update_reservation/")
def update_reservation_api(
        reservation_id: int,
        room_id: int,
        slot_date: date,
        start_time: time,
        end_time: time
):
    return update_reservation(
        reservation_id=reservation_id,
        room_id=room_id,
        slot_date=slot_date,
        start_time=start_time,
        end_time=end_time
    )

@app.post("/check_in/")
def check_in_api(reservation_id: int):
    return check_in(reservation_id=reservation_id)

@app.post("/check_out/")
def check_out_api(reservation_id: int):
    return check_out(reservation_id=reservation_id)

@app.post("/cancel_reservation/")
def cancel_reservation_api(reservation_id: int):
    return cancel_reservation(reservation_id=reservation_id)
