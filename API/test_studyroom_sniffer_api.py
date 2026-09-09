import os
import sys
from datetime import date, datetime, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fastapi.testclient import TestClient
from studyroom_sniffer_api import app

client = TestClient(app)
TODAY = date.today().isoformat()
YESTERDAY = (date.today() - timedelta(days=1)).isoformat()
IN_TWO_DAYS = (date.today() + timedelta(days=2)).isoformat()

passed = 0
failed = 0

def heading(text):
    print(f"\n{'=' * 68}\n{text}\n{'=' * 68}")

def check(label, condition, detail=""):
    global passed, failed
    if condition:
        passed += 1
        print(f"  [ok  ] {label}")
    else:
        failed += 1
        print(f"  [FAIL] {label}")
    if detail:
        print(f"         {detail}")

def get(endpoint, input_params=None):
    return client.get(f"/{endpoint}/", params=input_params or {})

def post(endpoint, input_params=None):
    return client.post(f"/{endpoint}/", params=input_params or {})

heading("Room.FindRoom -- rooms and their specifications")
rooms = get("find_room").json()["data"]
check("find_room returns all 5 rooms", len(rooms) == 5,
      f"{[row['RoomNumber'] for row in rooms]}")

filtered = [row["RoomNumber"] for row in
            get("find_room", {"floor": 4, "min_seats": 6, "whiteboard": True}).json()["data"]]
check("find_room filters by floor, seats, whiteboard", filtered == ["450"], f"{filtered}")

heading("RoomAvailability.CheckAvailability")
free = [row["RoomNumber"] for row in
        get("check_availability", {"start_date": TODAY, "start_time": "08:00:00",
                                   "end_time": "08:30:00"}).json()["data"]]
check("check_availability finds only the room free 08:00-08:30",
      free == ["450"], f"{free}  (130, 225, 230 and 335 are all booked then)")

rows = get("check_availability", {"start_date": TODAY, "end_date": IN_TWO_DAYS,
                                  "start_time": "08:00:00",
                                  "end_time": "08:30:00"}).json()["data"]
dates = sorted({str(row["Date"]) for row in rows})
check("check_availability over a date range returns only days that have slots",
      dates == [TODAY], f"dates: {dates}")

only = {row["RoomNumber"] for row in
        get("check_availability", {"start_date": TODAY, "start_time": "08:00:00",
                                   "end_time": "08:30:00",
                                   "room_number": "450"}).json()["data"]}
check("check_availability filters by room_number", only == {"450"}, f"{only}")

body = get("get_available_rooms_now").json()
check("get_available_rooms_now returns a window and a room list",
      "searched" in body and "data" in body,
      f"{body['searched'].get('FromTime')}-{body['searched'].get('ToTime')}, "
      f"{len(body['data'])} rooms free now")

slots = get("get_room_schedule", {"slot_date": TODAY, "room_id": 1}).json()["data"]
booked = [row for row in slots if row["SlotStatus"] == "Booked"]
check("get_room_schedule returns room 130's 5 slots",
      len(slots) == 5 and len(booked) == 4, f"{len(slots)} slots, {len(booked)} booked")

heading("Reading reservations")
reservations = get("get_all_reservations").json()["data"]
check("get_all_reservations returns the sample rows", len(reservations) >= 10,
      f"{len(reservations)} reservations")

row = get("get_reservation_by_id", {"reservation_id": 1}).json()["data"][0]
check("get_reservation_by_id reports TotalTime from the slots",
      row["TotalTimeFromSlots"] == 30, f"reservation 1 = {row['TotalTimeFromSlots']} minutes")

check("get_reservation_by_id returns an empty list when missing",
      get("get_reservation_by_id", {"reservation_id": 9999}).json()["data"] == [])

heading("The database refuses these, and the message comes back")
cases = [
    ("3 hours when the maximum is 2",
     {"app_user_id": 1, "room_id": 4, "slot_date": TODAY,
      "start_time": "09:00:00", "end_time": "12:00:00"},
     "longer than 2 hours"),
    ("08:00 to 08:20 is not a 15 minute increment",
     {"app_user_id": 1, "room_id": 4, "slot_date": TODAY,
      "start_time": "08:00:00", "end_time": "08:20:00"},
     "15 minute increments"),
    ("a date in the past",
     {"app_user_id": 1, "room_id": 4, "slot_date": YESTERDAY,
      "start_time": "08:00:00", "end_time": "08:30:00"},
     "in the past"),
    ("a room that is already taken",
     {"app_user_id": 2, "room_id": 1, "slot_date": TODAY,
      "start_time": "08:00:00", "end_time": "08:30:00"},
     "not free"),
    ("a user who does not exist",
     {"app_user_id": 999, "room_id": 5, "slot_date": TODAY,
      "start_time": "08:00:00", "end_time": "08:30:00"},
     "No such user"),
    ("a room that does not exist",
     {"app_user_id": 1, "room_id": 999, "slot_date": TODAY,
      "start_time": "08:00:00", "end_time": "08:30:00"},
     "No such room"),
    ("end time before start time",
     {"app_user_id": 1, "room_id": 5, "slot_date": TODAY,
      "start_time": "09:00:00", "end_time": "08:00:00"},
     "after start time"),
    ("one user holding two rooms at the same time",
     {"app_user_id": 1, "room_id": 5, "slot_date": TODAY,
      "start_time": "08:00:00", "end_time": "08:30:00"},
     "already has another room"),
]
for label, input_params, expected in cases:
    message = post("make_reservation", input_params).json()["status_message"]
    check(label, expected in message, message)

message = post("check_in", {"reservation_id": 9999}).json()["status_message"]
check("check in a reservation that does not exist", "No such reservation" in message, message)

check("FastAPI rejects a bad query parameter before SQL",
      get("find_room", {"floor": "not a number"}).status_code == 422)

heading("AppUser.RegisterUser")
new_email = f"testuser{datetime.now().strftime('%Y%m%d%H%M%S%f')}@mix.wvu.edu"
body = post("register_user", {"email": new_email, "password": "Mountaineers9!",
                              "first_name": "Test", "last_name": "User"}).json()
new_user_id = body.get("app_user_id")
check("register_user creates an account", new_user_id is not None, body["status_message"])

message = post("register_user", {"email": new_email,
                                 "password": "Mountaineers9!"}).json()["status_message"]
check("register_user refuses a duplicate email", "already registered" in message, message)

message = post("register_user", {"email": "someone@mix.wvu.edu", "password": "x",
                                 "user_role": "Wizard"}).json()["status_message"]
check("register_user refuses an invalid role", "Student or Admin" in message, message)

heading("Reservation.MakeReservation / UpdateReservation / Cancel")
body = post("make_reservation", {"app_user_id": new_user_id, "room_id": 3,
                                 "slot_date": TODAY, "start_time": "08:45:00",
                                 "end_time": "09:15:00"}).json()
new_id = body.get("reservation_id")
check("make_reservation books room 230 for 30 minutes", new_id is not None,
      body["status_message"])

message = post("update_reservation", {"reservation_id": new_id, "room_id": 3,
                                      "slot_date": TODAY, "start_time": "08:45:00",
                                      "end_time": "09:00:00"}).json()["status_message"]
check("update_reservation shortens it in place", "successfully" in message, message)

row = get("get_reservation_by_id", {"reservation_id": new_id}).json()["data"][0]
check("update_reservation rewrote TotalTime", row["TotalTimeStored"] == 15,
      f"TotalTime={row['TotalTimeStored']}, from slots={row['TotalTimeFromSlots']}")

message = post("update_reservation", {"reservation_id": new_id, "room_id": 5,
                                      "slot_date": TODAY, "start_time": "08:00:00",
                                      "end_time": "08:30:00"}).json()["status_message"]
check("update_reservation moves it to another room", "successfully" in message, message)

row = get("get_reservation_by_id", {"reservation_id": new_id}).json()["data"][0]
check("the moved reservation reports the new room",
      row["RoomNumber"] == "450" and row["TotalTimeStored"] == 30,
      f"room {row['RoomNumber']}, {row['TotalTimeStored']} minutes")

message = post("update_reservation", {"reservation_id": new_id, "room_id": 1,
                                      "slot_date": TODAY, "start_time": "08:00:00",
                                      "end_time": "08:30:00"}).json()["status_message"]
check("update_reservation refuses a room that is taken", "not free" in message, message)

row = get("get_reservation_by_id", {"reservation_id": new_id}).json()["data"][0]
check("the refused move left the reservation untouched",
      row["RoomNumber"] == "450" and row["TotalTimeStored"] == 30,
      f"still room {row['RoomNumber']}, {row['TotalTimeStored']} minutes")

message = post("update_reservation", {"reservation_id": 9999, "room_id": 1,
                                      "slot_date": TODAY, "start_time": "08:00:00",
                                      "end_time": "08:30:00"}).json()["status_message"]
check("update_reservation refuses a missing reservation",
      "No such reservation" in message, message)

message = post("check_in", {"reservation_id": new_id}).json()["status_message"]
check("check_in succeeds", "successfully" in message, message)

message = post("update_reservation", {"reservation_id": new_id, "room_id": 5,
                                      "slot_date": TODAY, "start_time": "08:00:00",
                                      "end_time": "08:15:00"}).json()["status_message"]
check("update_reservation refuses a checked-in reservation",
      "Only a booked reservation" in message, message)

message = post("check_out", {"reservation_id": new_id}).json()["status_message"]
check("check_out succeeds", "successfully" in message, message)

heading("Cleanup")
message = post("cancel_reservation", {"reservation_id": new_id}).json()["status_message"]
print(f"  {message}")
print(f"  test account {new_email} (AppUserID {new_user_id}) was left behind on purpose")

print(f"\n{'=' * 68}")
print(f"{passed} passed, {failed} failed")
print("Rerun 'python run_sql.py Data/InsertDataIafrate.sql' to reset row counts.")
sys.exit(1 if failed else 0)
