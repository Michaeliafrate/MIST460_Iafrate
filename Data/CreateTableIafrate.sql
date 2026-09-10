if(OBJECT_ID('RoomAvailability') is not null)
    drop table RoomAvailability;
if(OBJECT_ID('Reservation') is not null)
    drop table Reservation;
if(OBJECT_ID('Room') is not null)
    drop table Room;
if(OBJECT_ID('AppUser') is not null)
    drop table AppUser;

go

create table AppUser (
    AppUserID INT identity(1,1)
        constraint PK_AppUser PRIMARY KEY,
    FirstName NVARCHAR(50) NOT NULL,
    LastName NVARCHAR(50) NOT NULL,
    Email NVARCHAR(100) NOT NULL
        constraint UK_AppUser_Email UNIQUE,
    PasswordHash VARBINARY(256) NOT NULL,
    UserRole NVARCHAR(20) NOT NULL
        constraint CK_AppUser_UserRole CHECK (UserRole IN ('Student', 'Admin'))
);

go

create table Room (
    RoomID INT identity(1,1)
        constraint PK_Room PRIMARY KEY,
    RoomNumber NVARCHAR(10) NOT NULL
        constraint UK_Room_RoomNumber UNIQUE,
    Floor INT NOT NULL,
    Seats INT NOT NULL,
    Whiteboard BIT NOT NULL,
    CurrentStatus NVARCHAR(20) NOT NULL
        constraint CK_Room_CurrentStatus CHECK (CurrentStatus IN ('Available', 'In use', 'Closed'))
);

go

create table Reservation (
    ReservationID INT identity(1,1)
        constraint PK_Reservation PRIMARY KEY,
    AppUserID INT NOT NULL
        constraint FK_Reservation_AppUser FOREIGN KEY REFERENCES AppUser(AppUserID),
    DateTime DATETIME NOT NULL DEFAULT GETDATE(),
    CheckInDateTime DATETIME NULL,
    CheckOutDateTime DATETIME NULL,
    TotalTime INT NOT NULL
        constraint CK_Reservation_TotalTime CHECK (TotalTime > 0 AND TotalTime <= 120),
    ReservationStatus NVARCHAR(20) NOT NULL
        constraint CK_Reservation_Status CHECK (ReservationStatus IN ('Booked', 'CheckedIn', 'Completed', 'Cancelled'))
);

go

create table RoomAvailability (
    RoomAvailabilityID INT identity(1,1)
        constraint PK_RoomAvailability PRIMARY KEY,
    RoomID INT NOT NULL
        constraint FK_RoomAvailability_Room FOREIGN KEY REFERENCES Room(RoomID),
    Date DATE NOT NULL,
    StartTime TIME NOT NULL,
    EndTime TIME NOT NULL,
    AvailabilityStatus BIT NOT NULL,
    ReservationID INT NULL
        constraint FK_RoomAvailability_Reservation FOREIGN KEY REFERENCES Reservation(ReservationID),
    constraint UK_RoomAvailability_Slot UNIQUE (RoomID, Date, StartTime)
);
