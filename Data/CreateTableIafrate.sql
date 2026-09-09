if(OBJECT_ID('RoomAvailability') is not null)
    drop table RoomAvailability;
if(OBJECT_ID('Reservation') is not null)
    drop table Reservation;
if(OBJECT_ID('Room') is not null)
    drop table Room;
if(OBJECT_ID('AppUser') is not null)
    drop table AppUser;
GO

CREATE TABLE AppUser (
    AppUserID     INT           IDENTITY(1,1) NOT NULL,
    Email         NVARCHAR(255) NOT NULL,
    PasswordHash  VARBINARY(64) NOT NULL,
    FirstName     NVARCHAR(50)  NULL,
    LastName      NVARCHAR(50)  NULL,
    UserRole      VARCHAR(10)   NOT NULL CONSTRAINT DF_AppUser_UserRole DEFAULT 'Student',
    CreatedAt     DATETIME2(0)  NOT NULL CONSTRAINT DF_AppUser_CreatedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_AppUser PRIMARY KEY (AppUserID),
    CONSTRAINT UK_AppUser_Email UNIQUE (Email),
    CONSTRAINT CK_AppUser_UserRole CHECK (UserRole IN ('Student', 'Admin')),
    CONSTRAINT CK_AppUser_Email CHECK (Email LIKE '%_@_%._%')
);
GO

CREATE TABLE Room (
    RoomID        INT          IDENTITY(1,1) NOT NULL,
    RoomNumber    VARCHAR(10)  NOT NULL,
    Floor         INT          NOT NULL,
    Seats         INT          NOT NULL,
    Whiteboard    BIT          NOT NULL CONSTRAINT DF_Room_Whiteboard DEFAULT 0,
    CurrentStatus VARCHAR(10)  NOT NULL CONSTRAINT DF_Room_CurrentStatus DEFAULT 'Available',
    CONSTRAINT PK_Room PRIMARY KEY (RoomID),
    CONSTRAINT UK_Room_RoomNumber UNIQUE (RoomNumber),
    CONSTRAINT CK_Room_CurrentStatus CHECK (CurrentStatus IN ('Available', 'In use', 'Closed')),
    CONSTRAINT CK_Room_Seats CHECK (Seats > 0),
    CONSTRAINT CK_Room_Floor CHECK (Floor BETWEEN 1 AND 4)
);
GO

CREATE TABLE Reservation (
    ReservationID       INT          IDENTITY(1,1) NOT NULL,
    AppUserID           INT          NOT NULL,
    DateTime DATETIME2(0) NOT NULL CONSTRAINT DF_Reservation_DateTime DEFAULT SYSUTCDATETIME(),
    CheckInDateTime     DATETIME2(0) NULL,
    CheckOutDateTime    DATETIME2(0) NULL,
    TotalTime        INT          NOT NULL CONSTRAINT DF_Reservation_TotalTime DEFAULT 0,
    ReservationStatus   VARCHAR(12)  NOT NULL CONSTRAINT DF_Reservation_Status DEFAULT 'Booked',
    CONSTRAINT PK_Reservation PRIMARY KEY (ReservationID),
    CONSTRAINT FK_Reservation_AppUser FOREIGN KEY (AppUserID)
        REFERENCES AppUser (AppUserID),
    CONSTRAINT CK_Reservation_Status
        CHECK (ReservationStatus IN ('Booked', 'CheckedIn', 'Completed', 'Cancelled')),
    CONSTRAINT CK_Reservation_TotalTime
        CHECK (TotalTime BETWEEN 0 AND 120 AND TotalTime % 15 = 0),
    CONSTRAINT CK_Reservation_CheckOutAfterCheckIn
        CHECK (CheckOutDateTime IS NULL
               OR (CheckInDateTime IS NOT NULL AND CheckOutDateTime >= CheckInDateTime))
);
GO

CREATE TABLE RoomAvailability (
    RoomAvailabilityID INT      IDENTITY(1,1) NOT NULL,
    RoomID             INT      NOT NULL,
    Date           DATE     NOT NULL,
    StartTime          TIME(0)  NOT NULL,
    EndTime            TIME(0)  NOT NULL,
    AvailabilityStatus BIT      NOT NULL CONSTRAINT DF_RoomAvailability_Status DEFAULT 1,
    ReservationID      INT      NULL,
    CONSTRAINT PK_RoomAvailability PRIMARY KEY (RoomAvailabilityID),
    CONSTRAINT FK_RoomAvailability_Room FOREIGN KEY (RoomID)
        REFERENCES Room (RoomID) ON DELETE CASCADE,
    CONSTRAINT FK_RoomAvailability_Reservation FOREIGN KEY (ReservationID)
        REFERENCES Reservation (ReservationID),

    CONSTRAINT UK_RoomAvailability_Slot UNIQUE (RoomID, Date, StartTime),

    CONSTRAINT CK_RoomAvailability_QuarterHour
        CHECK (DATEDIFF(MINUTE, StartTime, EndTime) = 15
               AND DATEPART(MINUTE, StartTime) % 15 = 0
               AND DATEPART(SECOND, StartTime) = 0),

    CONSTRAINT CK_RoomAvailability_StatusMatchesReservation
        CHECK ((ReservationID IS NULL     AND AvailabilityStatus = 1)
            OR (ReservationID IS NOT NULL AND AvailabilityStatus = 0))
);
GO

CREATE INDEX IX_RoomAvailability_Search
    ON RoomAvailability (Date, StartTime, AvailabilityStatus)
    INCLUDE (RoomID, EndTime);
GO

CREATE INDEX IX_RoomAvailability_ReservationID
    ON RoomAvailability (ReservationID);
GO

CREATE INDEX IX_Reservation_AppUserID
    ON Reservation (AppUserID);
GO
