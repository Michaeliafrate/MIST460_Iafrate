DELETE FROM RoomAvailability;
DELETE FROM Reservation;
DELETE FROM Room;
DELETE FROM AppUser;
GO

SET IDENTITY_INSERT AppUser ON;

INSERT INTO AppUser (AppUserID, Email, PasswordHash, FirstName, LastName, UserRole) VALUES
    (1, 'miafrate@mix.wvu.edu',   0x01, 'Michael',  'Iafrate',   'Student'),
    (2, 'ccarter@mix.wvu.edu',    0x01, 'Carter',   'Reed',      'Student'),
    (3, 'dwhitfield@mix.wvu.edu', 0x01, 'Dana',     'Whitfield', 'Student'),
    (4, 'praman@mix.wvu.edu',     0x01, 'Priya',    'Raman',     'Student'),
    (5, 'jbennett@mail.wvu.edu',  0x01, 'Jordan',   'Bennett',   'Admin');

SET IDENTITY_INSERT AppUser OFF;
DBCC CHECKIDENT ('AppUser', RESEED) WITH NO_INFOMSGS;
GO

SET IDENTITY_INSERT Room ON;

INSERT INTO Room (RoomID, RoomNumber, Floor, Seats, Whiteboard, CurrentStatus) VALUES
    (1, '130', 1,  4, 1, 'Available'),
    (2, '225', 2,  6, 1, 'Available'),
    (3, '230', 2,  4, 0, 'Available'),
    (4, '335', 3,  8, 1, 'Available'),
    (5, '450', 4, 12, 1, 'Available');

SET IDENTITY_INSERT Room OFF;
DBCC CHECKIDENT ('Room', RESEED) WITH NO_INFOMSGS;
GO

DECLARE @Today DATE = CAST(SYSDATETIME() AS DATE);

WITH SlotNo AS (
    SELECT TOP (5) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS N
    FROM sys.all_objects
)
INSERT INTO RoomAvailability (RoomID, Date, StartTime, EndTime, AvailabilityStatus)
SELECT
    r.RoomID,
    @Today,
    CAST(DATEADD(MINUTE, 15 *  s.N,      CAST('08:00:00' AS TIME(0))) AS TIME(0)),
    CAST(DATEADD(MINUTE, 15 * (s.N + 1), CAST('08:00:00' AS TIME(0))) AS TIME(0)),
    1
FROM Room r
CROSS JOIN SlotNo s;

SET IDENTITY_INSERT Reservation ON;

INSERT INTO Reservation (ReservationID, AppUserID, DateTime, CheckInDateTime, CheckOutDateTime, TotalTime, ReservationStatus) VALUES
    (1,  1, SYSUTCDATETIME(), NULL, NULL, 30, 'Booked'),
    (2,  2, SYSUTCDATETIME(), NULL, NULL, 30, 'Booked'),
    (3,  1, SYSUTCDATETIME(), NULL, NULL, 30, 'Booked'),
    (4,  3, SYSUTCDATETIME(), SYSUTCDATETIME(), NULL, 45, 'CheckedIn'),
    (5,  4, SYSUTCDATETIME(), NULL, NULL, 30, 'Cancelled'),
    (6,  5, SYSUTCDATETIME(), NULL, NULL, 30, 'Booked'),
    (7,  2, SYSUTCDATETIME(), DATEADD(HOUR, -3, SYSUTCDATETIME()),
                              DATEADD(HOUR, -2, SYSUTCDATETIME()), 30, 'Completed'),
    (8,  3, SYSUTCDATETIME(), NULL, NULL, 30, 'Booked'),
    (9,  4, SYSUTCDATETIME(), NULL, NULL, 30, 'Booked'),
    (10, 1, SYSUTCDATETIME(), NULL, NULL, 15, 'Booked');

SET IDENTITY_INSERT Reservation OFF;
DBCC CHECKIDENT ('Reservation', RESEED) WITH NO_INFOMSGS;

UPDATE RoomAvailability SET ReservationID = 1, AvailabilityStatus = 0
WHERE RoomID = 1 AND Date = @Today
  AND StartTime >= '08:00:00' AND StartTime < '08:30:00';

UPDATE RoomAvailability SET ReservationID = 2, AvailabilityStatus = 0
WHERE RoomID = 2 AND Date = @Today
  AND StartTime >= '08:00:00' AND StartTime < '08:30:00';

UPDATE RoomAvailability SET ReservationID = 3, AvailabilityStatus = 0
WHERE RoomID = 1 AND Date = @Today
  AND StartTime >= '08:30:00' AND StartTime < '09:00:00';

UPDATE RoomAvailability SET ReservationID = 4, AvailabilityStatus = 0
WHERE RoomID = 3 AND Date = @Today
  AND StartTime >= '08:00:00' AND StartTime < '08:45:00';

UPDATE RoomAvailability SET ReservationID = 6, AvailabilityStatus = 0
WHERE RoomID = 4 AND Date = @Today
  AND StartTime >= '08:00:00' AND StartTime < '08:30:00';

UPDATE RoomAvailability SET ReservationID = 7, AvailabilityStatus = 0
WHERE RoomID = 5 AND Date = @Today
  AND StartTime >= '08:30:00' AND StartTime < '09:00:00';

UPDATE RoomAvailability SET ReservationID = 8, AvailabilityStatus = 0
WHERE RoomID = 2 AND Date = @Today
  AND StartTime >= '08:45:00' AND StartTime < '09:15:00';

UPDATE RoomAvailability SET ReservationID = 9, AvailabilityStatus = 0
WHERE RoomID = 4 AND Date = @Today
  AND StartTime >= '08:30:00' AND StartTime < '09:00:00';

UPDATE RoomAvailability SET ReservationID = 10, AvailabilityStatus = 0
WHERE RoomID = 5 AND Date = @Today
  AND StartTime >= '09:00:00' AND StartTime < '09:15:00';

UPDATE Room SET CurrentStatus = 'In use' WHERE RoomID = 3;
GO

SELECT 'AppUser' AS TableName, COUNT(*) AS RowTotal FROM AppUser
UNION ALL SELECT 'Room',              COUNT(*) FROM Room
UNION ALL SELECT 'Reservation',       COUNT(*) FROM Reservation
UNION ALL SELECT 'RoomAvailability',  COUNT(*) FROM RoomAvailability
UNION ALL SELECT '  ...booked slots', COUNT(*) FROM RoomAvailability WHERE AvailabilityStatus = 0
UNION ALL SELECT '  ...free slots',   COUNT(*) FROM RoomAvailability WHERE AvailabilityStatus = 1;
GO
