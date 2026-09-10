-- Run CreateTableIafrate.sql first. That drops and recreates the tables, so
-- the identity numbers below always start at 1.

insert into AppUser (FirstName, LastName, Email, PasswordHash, UserRole)
values ('Michael', 'Iafrate',   'miafrate@mix.wvu.edu',   0x01, 'Student'),
       ('Carter',  'Reed',      'ccarter@mix.wvu.edu',    0x01, 'Student'),
       ('Dana',    'Whitfield', 'dwhitfield@mix.wvu.edu', 0x01, 'Student'),
       ('Priya',   'Raman',     'praman@mix.wvu.edu',     0x01, 'Student'),
       ('Jordan',  'Bennett',   'jbennett@mail.wvu.edu',  0x01, 'Admin');

go

-- Room 230 reads 'In use' because reservation 4 below is checked in.
insert into Room (RoomNumber, Floor, Seats, Whiteboard, CurrentStatus)
values ('130', 1,  4, 1, 'Available'),
       ('225', 2,  6, 1, 'Available'),
       ('230', 2,  4, 0, 'In use'),
       ('335', 3,  8, 1, 'Available'),
       ('450', 4, 12, 1, 'Available');

go

-- Reservation 5 is cancelled, so no availability rows point at it below.
insert into Reservation (AppUserID, CheckInDateTime, CheckOutDateTime, TotalTime, ReservationStatus)
values (1, NULL,      NULL,      30, 'Booked'),
       (2, NULL,      NULL,      30, 'Booked'),
       (1, NULL,      NULL,      30, 'Booked'),
       (3, GETDATE(), NULL,      45, 'CheckedIn'),
       (4, NULL,      NULL,      30, 'Cancelled'),
       (5, NULL,      NULL,      30, 'Booked'),
       (2, GETDATE(), GETDATE(), 30, 'Completed'),
       (3, NULL,      NULL,      30, 'Booked'),
       (4, NULL,      NULL,      30, 'Booked'),
       (1, NULL,      NULL,      15, 'Booked');

go

-- Five 15 minute slots per room for today, 08:00 to 09:15.
-- AvailabilityStatus 1 means free, 0 means taken by the reservation named.
declare @Today DATE = cast(GETDATE() as DATE);

insert into RoomAvailability (RoomID, Date, StartTime, EndTime, AvailabilityStatus, ReservationID)
values (1, @Today, '08:00', '08:15', 0, 1),
       (1, @Today, '08:15', '08:30', 0, 1),
       (1, @Today, '08:30', '08:45', 0, 3),
       (1, @Today, '08:45', '09:00', 0, 3),
       (1, @Today, '09:00', '09:15', 1, NULL),

       (2, @Today, '08:00', '08:15', 0, 2),
       (2, @Today, '08:15', '08:30', 0, 2),
       (2, @Today, '08:30', '08:45', 1, NULL),
       (2, @Today, '08:45', '09:00', 0, 8),
       (2, @Today, '09:00', '09:15', 0, 8),

       (3, @Today, '08:00', '08:15', 0, 4),
       (3, @Today, '08:15', '08:30', 0, 4),
       (3, @Today, '08:30', '08:45', 0, 4),
       (3, @Today, '08:45', '09:00', 1, NULL),
       (3, @Today, '09:00', '09:15', 1, NULL),

       (4, @Today, '08:00', '08:15', 0, 6),
       (4, @Today, '08:15', '08:30', 0, 6),
       (4, @Today, '08:30', '08:45', 0, 9),
       (4, @Today, '08:45', '09:00', 0, 9),
       (4, @Today, '09:00', '09:15', 1, NULL),

       (5, @Today, '08:00', '08:15', 1, NULL),
       (5, @Today, '08:15', '08:30', 1, NULL),
       (5, @Today, '08:30', '08:45', 0, 7),
       (5, @Today, '08:45', '09:00', 0, 7),
       (5, @Today, '09:00', '09:15', 0, 10);

go

select count(*) as AppUserRows from AppUser;
select count(*) as RoomRows from Room;
select count(*) as RoomAvailabilityRows from RoomAvailability;
select count(*) as ReservationRows from Reservation;
