CREATE OR ALTER VIEW viewRoomSchedule
AS
SELECT
    a.RoomAvailabilityID,
    r.RoomID,
    r.RoomNumber,
    r.Floor,
    r.Seats,
    r.Whiteboard,
    a.Date,
    a.StartTime,
    a.EndTime,
    a.AvailabilityStatus,
    CASE WHEN a.AvailabilityStatus = 1 THEN 'Free' ELSE 'Booked' END AS SlotStatus,
    a.ReservationID,
    u.Email       AS BookedByEmail,
    res.ReservationStatus
FROM RoomAvailability a
JOIN Room r
    ON r.RoomID = a.RoomID
LEFT JOIN Reservation res
    ON res.ReservationID = a.ReservationID
LEFT JOIN AppUser u
    ON u.AppUserID = res.AppUserID;
GO

CREATE OR ALTER VIEW viewReservationDetail
AS
SELECT
    res.ReservationID,
    res.AppUserID,
    u.Email                              AS UserEmail,
    u.FirstName + ' ' + u.LastName       AS UserName,
    rm.RoomID,
    rm.RoomNumber,
    rm.Floor,
    rm.Seats,
    s.Date,
    s.StartTime,
    s.EndTime,
    s.SlotCount,
    s.SlotCount * 15                     AS TotalTimeComputed,
    res.TotalTime                     AS TotalTimeStored,
    res.ReservationStatus,
    res.DateTime,
    res.CheckInDateTime,
    res.CheckOutDateTime
FROM Reservation res
JOIN AppUser u
    ON u.AppUserID = res.AppUserID
OUTER APPLY (
    SELECT
        MIN(a.Date)  AS Date,
        MIN(a.StartTime) AS StartTime,
        MAX(a.EndTime)   AS EndTime,
        COUNT(*)         AS SlotCount,
        MIN(a.RoomID)    AS RoomID
    FROM RoomAvailability a
    WHERE a.ReservationID = res.ReservationID
) AS s
LEFT JOIN Room rm
    ON rm.RoomID = s.RoomID;
GO

CREATE OR ALTER FUNCTION dbo.fnReservationMinutes (@ReservationID INT)
RETURNS INT
AS
BEGIN
    DECLARE @Slots INT;

    SELECT @Slots = COUNT(*)
    FROM RoomAvailability
    WHERE ReservationID = @ReservationID;

    RETURN ISNULL(@Slots, 0) * 15;
END;
GO

CREATE OR ALTER FUNCTION dbo.fnIsRoomFree
(
    @RoomID    INT,
    @Date  DATE,
    @StartTime TIME(0),
    @EndTime   TIME(0)
)
RETURNS BIT
AS
BEGIN
    DECLARE @Needed INT = DATEDIFF(MINUTE, @StartTime, @EndTime) / 15;
    DECLARE @Free   INT;

    IF @Needed <= 0
        RETURN 0;

    SELECT @Free = COUNT(*)
    FROM RoomAvailability
    WHERE RoomID = @RoomID
      AND Date = @Date
      AND StartTime >= @StartTime
      AND StartTime <  @EndTime
      AND AvailabilityStatus = 1;

    RETURN CASE WHEN @Free = @Needed THEN 1 ELSE 0 END;
END;
GO

CREATE OR ALTER PROCEDURE procGenerateSlots
    @FromDate  DATE,
    @Days      INT     = 7,
    @OpenTime  TIME(0) = '08:00:00',
    @CloseTime TIME(0) = '20:00:00'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PerDay INT = DATEDIFF(MINUTE, @OpenTime, @CloseTime) / 15;

    IF @PerDay <= 0
        THROW 50003, 'Closing time must be after opening time.', 1;

    ;WITH SlotNo AS (
        SELECT TOP (@PerDay) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS N
        FROM sys.all_objects
    ),
    DayNo AS (
        SELECT TOP (@Days) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS N
        FROM sys.all_objects
    )
    INSERT INTO RoomAvailability (RoomID, Date, StartTime, EndTime, AvailabilityStatus)
    SELECT
        r.RoomID,
        DATEADD(DAY, d.N, @FromDate),
        CAST(DATEADD(MINUTE, 15 *  s.N,      @OpenTime) AS TIME(0)),
        CAST(DATEADD(MINUTE, 15 * (s.N + 1), @OpenTime) AS TIME(0)),
        1
    FROM Room r
    CROSS JOIN DayNo d
    CROSS JOIN SlotNo s
    WHERE NOT EXISTS (
        SELECT 1 FROM RoomAvailability x
        WHERE x.RoomID    = r.RoomID
          AND x.Date  = DATEADD(DAY, d.N, @FromDate)
          AND x.StartTime = CAST(DATEADD(MINUTE, 15 * s.N, @OpenTime) AS TIME(0))
    );

    SELECT @@ROWCOUNT AS SlotsCreated;
END;
GO

CREATE OR ALTER PROCEDURE procCheckAvailability
    @StartDate       DATE,
    @EndDate         DATE = NULL,
    @StartTime       TIME(0),
    @EndTime         TIME(0),
    @RoomNumber      VARCHAR(10) = NULL,
    @Floor           INT = NULL,
    @MinSeats        INT = NULL,
    @NeedsWhiteboard BIT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @EndDate IS NULL
        SET @EndDate = @StartDate;

    DECLARE @Minutes INT = DATEDIFF(MINUTE, @StartTime, @EndTime);

    IF @Minutes <= 0
        THROW 50003, 'End time must be after start time.', 1;
    IF @Minutes % 15 <> 0
        THROW 50004, 'Times must fall on 15 minute increments.', 1;
    IF @EndDate < @StartDate
        THROW 50009, 'End date must not be before start date.', 1;

    DECLARE @Needed INT = @Minutes / 15;

    SELECT
        d.Date,
        r.RoomID,
        r.RoomNumber,
        r.Floor,
        r.Seats,
        r.Whiteboard,
        r.CurrentStatus,
        @Minutes AS MinutesRequested
    FROM Room r
    CROSS JOIN (
        SELECT DISTINCT a.Date
        FROM RoomAvailability a
        WHERE a.Date BETWEEN @StartDate AND @EndDate
    ) d
    WHERE (@RoomNumber      IS NULL OR r.RoomNumber = @RoomNumber)
      AND (@Floor           IS NULL OR r.Floor      =  @Floor)
      AND (@MinSeats        IS NULL OR r.Seats      >= @MinSeats)
      AND (@NeedsWhiteboard IS NULL OR r.Whiteboard =  @NeedsWhiteboard)
      AND (
            SELECT COUNT(*)
            FROM RoomAvailability a
            WHERE a.RoomID      = r.RoomID
              AND a.Date        = d.Date
              AND a.StartTime  >= @StartTime
              AND a.StartTime   < @EndTime
              AND a.AvailabilityStatus = 1
          ) = @Needed
    ORDER BY d.Date, r.Floor, r.RoomNumber;
END;
GO

CREATE OR ALTER PROCEDURE procFindRoomAvailableNow
    @Minutes  INT = 60,
    @Floor    INT = NULL,
    @MinSeats INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @NowLocal DATETIME2(0) =
        CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC'
                              AT TIME ZONE 'Eastern Standard Time' AS DATETIME2(0));

    DECLARE @Date  DATE    = CAST(@NowLocal AS DATE);
    DECLARE @Clock TIME(0) = CAST(@NowLocal AS TIME(0));

    DECLARE @Start TIME(0) = CAST(DATEADD(
            MINUTE,
            (DATEDIFF(MINUTE, CAST('00:00:00' AS TIME(0)), @Clock) / 15) * 15,
            CAST('00:00:00' AS TIME(0))) AS TIME(0));

    DECLARE @End TIME(0) = CAST(DATEADD(MINUTE, @Minutes, @Start) AS TIME(0));

    SELECT @NowLocal AS LocalNow, @Date AS SearchDate,
           @Start AS FromTime, @End AS ToTime;

    EXEC procCheckAvailability @Date, @Date, @Start, @End, NULL, @Floor, @MinSeats, NULL;
END;
GO

CREATE OR ALTER PROCEDURE procRegisterUser
    @Email     NVARCHAR(255),
    @Password  NVARCHAR(200),
    @FirstName NVARCHAR(50) = NULL,
    @LastName  NVARCHAR(50) = NULL,
    @UserRole  VARCHAR(10)  = 'Student'
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM AppUser WHERE Email = @Email)
        THROW 50018, 'That email is already registered.', 1;

    IF @UserRole NOT IN ('Student', 'Admin')
        THROW 50019, 'UserRole must be Student or Admin.', 1;

    INSERT INTO AppUser (Email, PasswordHash, FirstName, LastName, UserRole)
    VALUES (
        @Email,
        HASHBYTES('SHA2_256', CAST(@Email + '|' + @Password AS VARCHAR(500))),
        @FirstName,
        @LastName,
        @UserRole
    );

    SELECT SCOPE_IDENTITY() AS AppUserID;
END;
GO

CREATE OR ALTER PROCEDURE procFindRoom
    @Floor           INT = NULL,
    @MinSeats        INT = NULL,
    @NeedsWhiteboard BIT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT RoomID, RoomNumber, Floor, Seats, Whiteboard, CurrentStatus
    FROM Room
    WHERE (@Floor           IS NULL OR Floor      =  @Floor)
      AND (@MinSeats        IS NULL OR Seats      >= @MinSeats)
      AND (@NeedsWhiteboard IS NULL OR Whiteboard =  @NeedsWhiteboard)
    ORDER BY Floor, RoomNumber;
END;
GO

CREATE OR ALTER PROCEDURE procGetRoomSchedule
    @Date DATE,
    @RoomID   INT = NULL,
    @FreeOnly BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    SELECT RoomID, RoomNumber, Floor, Seats, Date, StartTime, EndTime,
           SlotStatus, ReservationID, BookedByEmail, ReservationStatus
    FROM viewRoomSchedule
    WHERE Date = @Date
      AND (@RoomID IS NULL OR RoomID = @RoomID)
      AND (@FreeOnly = 0 OR AvailabilityStatus = 1)
    ORDER BY RoomNumber, StartTime;
END;
GO

CREATE OR ALTER PROCEDURE procGetAllReservations
    @AppUserID         INT = NULL,
    @ReservationStatus VARCHAR(12) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT *
    FROM viewReservationDetail
    WHERE (@AppUserID         IS NULL OR AppUserID         = @AppUserID)
      AND (@ReservationStatus IS NULL OR ReservationStatus = @ReservationStatus)
    ORDER BY ReservationID DESC;
END;
GO

CREATE OR ALTER PROCEDURE procGetReservationByID
    @ReservationID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT *, dbo.fnReservationMinutes(@ReservationID) AS TotalTimeFromSlots
    FROM viewReservationDetail
    WHERE ReservationID = @ReservationID;
END;
GO

CREATE OR ALTER PROCEDURE procMakeReservation
    @AppUserID     INT,
    @RoomID        INT,
    @Date          DATE,
    @StartTime     TIME(0),
    @EndTime       TIME(0),
    @ReservationID INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM AppUser WHERE AppUserID = @AppUserID)
        THROW 50001, 'No such user.', 1;

    IF NOT EXISTS (SELECT 1 FROM Room WHERE RoomID = @RoomID)
        THROW 50002, 'No such room.', 1;

    DECLARE @Minutes INT = DATEDIFF(MINUTE, @StartTime, @EndTime);

    IF @Minutes <= 0
        THROW 50003, 'End time must be after start time.', 1;

    IF @Minutes % 15 <> 0
        THROW 50004, 'Reservations must be in 15 minute increments.', 1;

    IF @Minutes > 120
        THROW 50005, 'A reservation cannot be longer than 2 hours.', 1;

    IF @Date < CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC'
                        AT TIME ZONE 'Eastern Standard Time' AS DATE)
        THROW 50006, 'That date is in the past.', 1;

    IF dbo.fnIsRoomFree(@RoomID, @Date, @StartTime, @EndTime) = 0
        THROW 50007, 'That room is not free for the whole time requested.', 1;

    DECLARE @Needed INT = @Minutes / 15;

    BEGIN TRANSACTION;

        INSERT INTO Reservation (AppUserID, TotalTime, ReservationStatus)
        VALUES (@AppUserID, @Minutes, 'Booked');

        SET @ReservationID = SCOPE_IDENTITY();

        UPDATE RoomAvailability
        SET ReservationID      = @ReservationID,
            AvailabilityStatus = 0
        WHERE RoomID    = @RoomID
          AND Date      = @Date
          AND StartTime >= @StartTime
          AND StartTime <  @EndTime
          AND AvailabilityStatus = 1;

        IF @@ROWCOUNT <> @Needed
            THROW 50008, 'Someone booked part of that time first. Try again.', 1;

    COMMIT TRANSACTION;

    SELECT @ReservationID AS ReservationID;
END;
GO

CREATE OR ALTER PROCEDURE procUpdateReservation
    @ReservationID INT,
    @RoomID        INT,
    @Date          DATE,
    @StartTime     TIME(0),
    @EndTime       TIME(0)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM Reservation WHERE ReservationID = @ReservationID)
        THROW 50017, 'No such reservation.', 1;

    IF NOT EXISTS (SELECT 1 FROM Room WHERE RoomID = @RoomID)
        THROW 50002, 'No such room.', 1;

    IF (SELECT ReservationStatus FROM Reservation WHERE ReservationID = @ReservationID) <> 'Booked'
        THROW 50016, 'Only a booked reservation can be updated.', 1;

    DECLARE @Minutes INT = DATEDIFF(MINUTE, @StartTime, @EndTime);

    IF @Minutes <= 0
        THROW 50003, 'End time must be after start time.', 1;

    IF @Minutes % 15 <> 0
        THROW 50004, 'Reservations must be in 15 minute increments.', 1;

    IF @Minutes > 120
        THROW 50005, 'A reservation cannot be longer than 2 hours.', 1;

    IF @Date < CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC'
                        AT TIME ZONE 'Eastern Standard Time' AS DATE)
        THROW 50006, 'That date is in the past.', 1;

    DECLARE @Needed INT = @Minutes / 15;

    BEGIN TRANSACTION;

        UPDATE RoomAvailability
        SET ReservationID      = NULL,
            AvailabilityStatus = 1
        WHERE ReservationID = @ReservationID;

        UPDATE RoomAvailability
        SET ReservationID      = @ReservationID,
            AvailabilityStatus = 0
        WHERE RoomID    = @RoomID
          AND Date      = @Date
          AND StartTime >= @StartTime
          AND StartTime <  @EndTime
          AND AvailabilityStatus = 1;

        IF @@ROWCOUNT <> @Needed
            THROW 50007, 'That room is not free for the whole time requested.', 1;

        UPDATE Reservation
        SET TotalTime = @Minutes
        WHERE ReservationID = @ReservationID;

    COMMIT TRANSACTION;

    SELECT @ReservationID AS ReservationID;
END;
GO

CREATE OR ALTER PROCEDURE procCancelReservation
    @ReservationID INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM Reservation WHERE ReservationID = @ReservationID)
        THROW 50017, 'No such reservation.', 1;

    IF EXISTS (SELECT 1 FROM Reservation
               WHERE ReservationID = @ReservationID AND ReservationStatus = 'Cancelled')
        THROW 50016, 'That reservation is already cancelled.', 1;

    BEGIN TRANSACTION;

        UPDATE RoomAvailability
        SET ReservationID      = NULL,
            AvailabilityStatus = 1
        WHERE ReservationID = @ReservationID;

        UPDATE Reservation
        SET ReservationStatus = 'Cancelled'
        WHERE ReservationID = @ReservationID;

    COMMIT TRANSACTION;
END;
GO

CREATE OR ALTER PROCEDURE procCheckIn
    @ReservationID INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM Reservation WHERE ReservationID = @ReservationID)
        THROW 50017, 'No such reservation.', 1;

    IF NOT EXISTS (SELECT 1 FROM Reservation
                   WHERE ReservationID = @ReservationID AND ReservationStatus = 'Booked')
        THROW 50016, 'Only a booked reservation can be checked in.', 1;

    BEGIN TRANSACTION;

        UPDATE Reservation
        SET CheckInDateTime   = SYSUTCDATETIME(),
            ReservationStatus = 'CheckedIn'
        WHERE ReservationID = @ReservationID;

        UPDATE r
        SET r.CurrentStatus = 'In use'
        FROM Room r
        WHERE r.RoomID IN (
            SELECT a.RoomID FROM RoomAvailability a
            WHERE a.ReservationID = @ReservationID
        );

    COMMIT TRANSACTION;
END;
GO

CREATE OR ALTER PROCEDURE procCheckOut
    @ReservationID INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM Reservation WHERE ReservationID = @ReservationID)
        THROW 50017, 'No such reservation.', 1;

    IF NOT EXISTS (SELECT 1 FROM Reservation
                   WHERE ReservationID = @ReservationID AND ReservationStatus = 'CheckedIn')
        THROW 50016, 'Only a checked-in reservation can be checked out.', 1;

    BEGIN TRANSACTION;

        UPDATE Reservation
        SET CheckOutDateTime  = SYSUTCDATETIME(),
            ReservationStatus = 'Completed'
        WHERE ReservationID = @ReservationID;

        UPDATE r
        SET r.CurrentStatus = 'Available'
        FROM Room r
        WHERE r.RoomID IN (
            SELECT a.RoomID FROM RoomAvailability a
            WHERE a.ReservationID = @ReservationID
        );

    COMMIT TRANSACTION;
END;
GO

CREATE OR ALTER TRIGGER trgEnforceReservationRules
ON RoomAvailability
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM inserted WHERE ReservationID IS NOT NULL)
       AND NOT EXISTS (SELECT 1 FROM deleted WHERE ReservationID IS NOT NULL)
        RETURN;

    ;WITH Affected AS (
        SELECT ReservationID FROM inserted WHERE ReservationID IS NOT NULL
        UNION
        SELECT ReservationID FROM deleted  WHERE ReservationID IS NOT NULL
    ),
    Shape AS (
        SELECT
            a.ReservationID,
            COUNT(*)                    AS SlotCount,
            COUNT(DISTINCT a.RoomID)    AS RoomCount,
            COUNT(DISTINCT a.Date)  AS DayCount,
            MIN(a.StartTime)            AS MinStart,
            MAX(a.StartTime)            AS MaxStart
        FROM RoomAvailability a
        JOIN Affected f ON f.ReservationID = a.ReservationID
        GROUP BY a.ReservationID
    )
    SELECT *
    INTO #Shape
    FROM Shape;

    IF EXISTS (SELECT 1 FROM #Shape WHERE RoomCount > 1)
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50010, 'All slots in a reservation must be in the same room.', 1;
    END;

    IF EXISTS (SELECT 1 FROM #Shape WHERE DayCount > 1)
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50011, 'A reservation cannot span more than one day.', 1;
    END;

    IF EXISTS (SELECT 1 FROM #Shape WHERE SlotCount > 8)
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50012, 'A reservation cannot be longer than 2 hours.', 1;
    END;

    IF EXISTS (
        SELECT 1 FROM #Shape
        WHERE DATEDIFF(MINUTE, MinStart, MaxStart) <> (SlotCount - 1) * 15
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50013, 'The slots in a reservation must be consecutive.', 1;
    END;

    IF EXISTS (
        SELECT 1
        FROM RoomAvailability mine
        JOIN #Shape       AS f  ON f.ReservationID = mine.ReservationID
        JOIN Reservation r1 ON r1.ReservationID = mine.ReservationID
        JOIN RoomAvailability other
             ON  other.Date  = mine.Date
             AND other.StartTime = mine.StartTime
             AND other.ReservationID IS NOT NULL
             AND other.ReservationID <> mine.ReservationID
        JOIN Reservation r2 ON r2.ReservationID = other.ReservationID
        WHERE r1.AppUserID = r2.AppUserID
          AND r1.ReservationStatus <> 'Cancelled'
          AND r2.ReservationStatus <> 'Cancelled'
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50014, 'That user already has another room booked at the same time.', 1;
    END;

    DROP TABLE #Shape;
END;
GO

CREATE OR ALTER TRIGGER trgProtectCancelledReservation
ON Reservation
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM deleted d
        JOIN inserted i ON i.ReservationID = d.ReservationID
        WHERE d.ReservationStatus = 'Cancelled'
          AND i.ReservationStatus <> 'Cancelled'
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50015, 'A cancelled reservation cannot be reopened. Make a new one.', 1;
    END;
END;
GO
