-- Programming objects for StudyroomSniffer.
-- Every procedure that changes data returns a StatusMessage column so the
-- API can show the reason back to the student.

create or alter procedure procRegisterUser
(
    @FirstName NVARCHAR(50),
    @LastName NVARCHAR(50),
    @Email NVARCHAR(100),
    @Password NVARCHAR(100),
    @UserRole NVARCHAR(20) = 'Student'
)
as
begin
    declare @Existing INT;
    declare @NewAppUserID INT;

    select @Existing = count(*) from AppUser where Email = @Email;

    if (@Existing > 0)
    begin
        select 0 as AppUserID, 'That email is already registered.' as StatusMessage;
        return;
    end

    if (@UserRole <> 'Student' and @UserRole <> 'Admin')
    begin
        select 0 as AppUserID, 'UserRole must be Student or Admin.' as StatusMessage;
        return;
    end

    insert into AppUser (FirstName, LastName, Email, PasswordHash, UserRole)
    values (@FirstName, @LastName, @Email, convert(VARBINARY(256), @Password), @UserRole);

    select @NewAppUserID = max(AppUserID) from AppUser;

    select @NewAppUserID as AppUserID, 'User registered successfully.' as StatusMessage;
end

GO

-- Requirements 2 and 3: how many people fit, and what the room has.
create or alter procedure procFindRoom
(
    @Floor INT = NULL,
    @MinSeats INT = NULL,
    @Whiteboard BIT = NULL
)
as
begin
    select RoomID, RoomNumber, Floor, Seats, Whiteboard, CurrentStatus
    from Room
    where (@Floor IS NULL OR Floor = @Floor)
      and (@MinSeats IS NULL OR Seats >= @MinSeats)
      and (@Whiteboard IS NULL OR Whiteboard = @Whiteboard)
    order by Floor, RoomNumber;
end

GO

-- Requirements 1 and 4: which rooms are free for a whole time window.
-- A room qualifies when every slot it has in that window is free, which is
-- what min(AvailabilityStatus) = 1 checks.
create or alter procedure procCheckAvailability
(
    @StartDate DATE,
    @EndDate DATE = NULL,
    @StartTime TIME,
    @EndTime TIME,
    @RoomNumber NVARCHAR(10) = NULL,
    @Floor INT = NULL,
    @MinSeats INT = NULL,
    @Whiteboard BIT = NULL
)
as
begin
    if (@EndDate IS NULL)
        set @EndDate = @StartDate;

    select a.RoomID, r.RoomNumber, r.Floor, r.Seats, r.Whiteboard, r.CurrentStatus, a.Date
    from RoomAvailability a
    inner join Room r on r.RoomID = a.RoomID
    where a.Date >= @StartDate
      and a.Date <= @EndDate
      and a.StartTime >= @StartTime
      and a.StartTime < @EndTime
      and (@RoomNumber IS NULL OR r.RoomNumber = @RoomNumber)
      and (@Floor IS NULL OR r.Floor = @Floor)
      and (@MinSeats IS NULL OR r.Seats >= @MinSeats)
      and (@Whiteboard IS NULL OR r.Whiteboard = @Whiteboard)
    group by a.RoomID, r.RoomNumber, r.Floor, r.Seats, r.Whiteboard, r.CurrentStatus, a.Date
    having min(cast(a.AvailabilityStatus as INT)) = 1
    order by a.Date, r.Floor, r.RoomNumber;
end

GO

-- Requirement 8: find me a room available now. Lists the free slots left
-- today from the current time onward.
create or alter procedure procFindRoomAvailableNow
(
    @Floor INT = NULL,
    @MinSeats INT = NULL
)
as
begin
    declare @Today DATE;
    declare @Now TIME;

    set @Today = cast(GETDATE() as DATE);
    set @Now = cast(GETDATE() as TIME);

    select a.RoomID, r.RoomNumber, r.Floor, r.Seats, r.Whiteboard,
           a.Date, a.StartTime, a.EndTime
    from RoomAvailability a
    inner join Room r on r.RoomID = a.RoomID
    where a.Date = @Today
      and a.StartTime >= @Now
      and a.AvailabilityStatus = 1
      and (@Floor IS NULL OR r.Floor = @Floor)
      and (@MinSeats IS NULL OR r.Seats >= @MinSeats)
    order by a.StartTime, r.RoomNumber;
end

GO

-- Requirement 4: the slot by slot picture for a day.
create or alter procedure procGetRoomSchedule
(
    @Date DATE,
    @RoomID INT = NULL,
    @FreeOnly BIT = 0
)
as
begin
    select r.RoomID, r.RoomNumber, r.Floor, r.Seats,
           a.Date, a.StartTime, a.EndTime,
           a.AvailabilityStatus,
           a.ReservationID, u.Email as BookedByEmail, res.ReservationStatus
    from RoomAvailability a
    inner join Room r on r.RoomID = a.RoomID
    left join Reservation res on res.ReservationID = a.ReservationID
    left join AppUser u on u.AppUserID = res.AppUserID
    where a.Date = @Date
      and (@RoomID IS NULL OR a.RoomID = @RoomID)
      and (@FreeOnly = 0 OR a.AvailabilityStatus = 1)
    order by r.RoomNumber, a.StartTime;
end

GO

-- One row per reservation. Cancelled reservations hold no slots, so the
-- joins to RoomAvailability and Room have to be left joins.
create or alter procedure procGetAllReservations
(
    @AppUserID INT = NULL,
    @ReservationStatus NVARCHAR(20) = NULL
)
as
begin
    select res.ReservationID, res.AppUserID, u.Email as UserEmail,
           u.FirstName + ' ' + u.LastName as UserName,
           max(r.RoomNumber) as RoomNumber,
           max(a.Date) as Date,
           min(a.StartTime) as StartTime,
           max(a.EndTime) as EndTime,
           count(a.RoomAvailabilityID) as SlotCount,
           res.TotalTime, res.ReservationStatus,
           res.DateTime, res.CheckInDateTime, res.CheckOutDateTime
    from Reservation res
    inner join AppUser u on u.AppUserID = res.AppUserID
    left join RoomAvailability a on a.ReservationID = res.ReservationID
    left join Room r on r.RoomID = a.RoomID
    where (@AppUserID IS NULL OR res.AppUserID = @AppUserID)
      and (@ReservationStatus IS NULL OR res.ReservationStatus = @ReservationStatus)
    group by res.ReservationID, res.AppUserID, u.Email, u.FirstName, u.LastName,
             res.TotalTime, res.ReservationStatus,
             res.DateTime, res.CheckInDateTime, res.CheckOutDateTime
    order by res.ReservationID;
end

GO

create or alter procedure procGetReservationByID
(
    @ReservationID INT
)
as
begin
    select res.ReservationID, res.AppUserID, u.Email as UserEmail,
           u.FirstName + ' ' + u.LastName as UserName,
           max(r.RoomNumber) as RoomNumber,
           max(a.Date) as Date,
           min(a.StartTime) as StartTime,
           max(a.EndTime) as EndTime,
           count(a.RoomAvailabilityID) as SlotCount,
           count(a.RoomAvailabilityID) * 15 as TotalTimeFromSlots,
           res.TotalTime, res.ReservationStatus,
           res.DateTime, res.CheckInDateTime, res.CheckOutDateTime
    from Reservation res
    inner join AppUser u on u.AppUserID = res.AppUserID
    left join RoomAvailability a on a.ReservationID = res.ReservationID
    left join Room r on r.RoomID = a.RoomID
    where res.ReservationID = @ReservationID
    group by res.ReservationID, res.AppUserID, u.Email, u.FirstName, u.LastName,
             res.TotalTime, res.ReservationStatus,
             res.DateTime, res.CheckInDateTime, res.CheckOutDateTime;
end

GO

-- Requirements 5 and 6: book a room in 15 minute steps, at most 2 hours, and
-- never two rooms at the same moment for the same student.
create or alter procedure procMakeReservation
(
    @AppUserID INT,
    @RoomID INT,
    @Date DATE,
    @StartTime TIME,
    @EndTime TIME
)
as
begin
    declare @UserCount INT;
    declare @RoomCount INT;
    declare @TotalTime INT;
    declare @NeededSlots INT;
    declare @FreeSlots INT;
    declare @Conflicts INT;
    declare @ReservationID INT;

    select @UserCount = count(*) from AppUser where AppUserID = @AppUserID;
    if (@UserCount = 0)
    begin
        select 0 as ReservationID, 'No such user.' as StatusMessage;
        return;
    end

    select @RoomCount = count(*) from Room where RoomID = @RoomID;
    if (@RoomCount = 0)
    begin
        select 0 as ReservationID, 'No such room.' as StatusMessage;
        return;
    end

    set @TotalTime = datediff(minute, @StartTime, @EndTime);

    if (@TotalTime <= 0)
    begin
        select 0 as ReservationID, 'End time must be after start time.' as StatusMessage;
        return;
    end

    if (@TotalTime % 15 <> 0)
    begin
        select 0 as ReservationID, 'Reservations must be in 15 minute increments.' as StatusMessage;
        return;
    end

    if (@TotalTime > 120)
    begin
        select 0 as ReservationID, 'A reservation cannot be longer than 2 hours.' as StatusMessage;
        return;
    end

    if (@Date < cast(GETDATE() as DATE))
    begin
        select 0 as ReservationID, 'That date is in the past.' as StatusMessage;
        return;
    end

    set @NeededSlots = @TotalTime / 15;

    select @FreeSlots = count(*)
    from RoomAvailability
    where RoomID = @RoomID
      and Date = @Date
      and StartTime >= @StartTime
      and StartTime < @EndTime
      and AvailabilityStatus = 1;

    if (@FreeSlots <> @NeededSlots)
    begin
        select 0 as ReservationID, 'That room is not free for the whole time requested.' as StatusMessage;
        return;
    end

    select @Conflicts = count(*)
    from RoomAvailability a
    inner join Reservation res on res.ReservationID = a.ReservationID
    where a.Date = @Date
      and a.StartTime >= @StartTime
      and a.StartTime < @EndTime
      and res.AppUserID = @AppUserID
      and res.ReservationStatus <> 'Cancelled';

    if (@Conflicts > 0)
    begin
        select 0 as ReservationID, 'That user already has another room booked at the same time.' as StatusMessage;
        return;
    end

    insert into Reservation (AppUserID, TotalTime, ReservationStatus)
    values (@AppUserID, @TotalTime, 'Booked');

    select @ReservationID = max(ReservationID) from Reservation;

    update RoomAvailability
    set ReservationID = @ReservationID,
        AvailabilityStatus = 0
    where RoomID = @RoomID
      and Date = @Date
      and StartTime >= @StartTime
      and StartTime < @EndTime;

    select @ReservationID as ReservationID, 'Reservation created successfully.' as StatusMessage;
end

GO

-- Move or resize a booking. The old slots are released first so a booking
-- can be extended in the room it already sits in.
create or alter procedure procUpdateReservation
(
    @ReservationID INT,
    @RoomID INT,
    @Date DATE,
    @StartTime TIME,
    @EndTime TIME
)
as
begin
    declare @Status NVARCHAR(20);
    declare @AppUserID INT;
    declare @RoomCount INT;
    declare @TotalTime INT;
    declare @NeededSlots INT;
    declare @FreeSlots INT;
    declare @Conflicts INT;

    select @Status = ReservationStatus, @AppUserID = AppUserID
    from Reservation where ReservationID = @ReservationID;

    if (@Status IS NULL)
    begin
        select 'No such reservation.' as StatusMessage;
        return;
    end

    if (@Status <> 'Booked')
    begin
        select 'Only a booked reservation can be updated.' as StatusMessage;
        return;
    end

    select @RoomCount = count(*) from Room where RoomID = @RoomID;
    if (@RoomCount = 0)
    begin
        select 'No such room.' as StatusMessage;
        return;
    end

    set @TotalTime = datediff(minute, @StartTime, @EndTime);

    if (@TotalTime <= 0)
    begin
        select 'End time must be after start time.' as StatusMessage;
        return;
    end

    if (@TotalTime % 15 <> 0)
    begin
        select 'Reservations must be in 15 minute increments.' as StatusMessage;
        return;
    end

    if (@TotalTime > 120)
    begin
        select 'A reservation cannot be longer than 2 hours.' as StatusMessage;
        return;
    end

    set @NeededSlots = @TotalTime / 15;

    -- Count the slots this reservation could take: free ones, plus the ones
    -- it already holds itself.
    select @FreeSlots = count(*)
    from RoomAvailability
    where RoomID = @RoomID
      and Date = @Date
      and StartTime >= @StartTime
      and StartTime < @EndTime
      and (AvailabilityStatus = 1 OR ReservationID = @ReservationID);

    if (@FreeSlots <> @NeededSlots)
    begin
        select 'That room is not free for the whole time requested.' as StatusMessage;
        return;
    end

    -- Any other reservation this student holds at the same time blocks the
    -- move. The reservation being changed is excluded from the count.
    select @Conflicts = count(*)
    from RoomAvailability a
    inner join Reservation res on res.ReservationID = a.ReservationID
    where a.Date = @Date
      and a.StartTime >= @StartTime
      and a.StartTime < @EndTime
      and res.AppUserID = @AppUserID
      and res.ReservationID <> @ReservationID
      and res.ReservationStatus <> 'Cancelled';

    if (@Conflicts > 0)
    begin
        select 'That user already has another room booked at the same time.' as StatusMessage;
        return;
    end

    update RoomAvailability
    set ReservationID = NULL,
        AvailabilityStatus = 1
    where ReservationID = @ReservationID;

    update RoomAvailability
    set ReservationID = @ReservationID,
        AvailabilityStatus = 0
    where RoomID = @RoomID
      and Date = @Date
      and StartTime >= @StartTime
      and StartTime < @EndTime;

    update Reservation
    set TotalTime = @TotalTime
    where ReservationID = @ReservationID;

    select 'Reservation updated successfully.' as StatusMessage;
end

GO

-- Cancelling frees the slots but keeps the reservation row as history.
create or alter procedure procCancelReservation
(
    @ReservationID INT
)
as
begin
    declare @Status NVARCHAR(20);
    declare @RoomID INT;

    select @Status = ReservationStatus from Reservation where ReservationID = @ReservationID;

    if (@Status IS NULL)
    begin
        select 'No such reservation.' as StatusMessage;
        return;
    end

    if (@Status = 'Cancelled')
    begin
        select 'That reservation is already cancelled.' as StatusMessage;
        return;
    end

    select @RoomID = max(RoomID) from RoomAvailability where ReservationID = @ReservationID;

    update RoomAvailability
    set ReservationID = NULL,
        AvailabilityStatus = 1
    where ReservationID = @ReservationID;

    update Reservation
    set ReservationStatus = 'Cancelled'
    where ReservationID = @ReservationID;

    if (@RoomID IS NOT NULL)
        update Room set CurrentStatus = 'Available' where RoomID = @RoomID;

    select 'Reservation cancelled successfully.' as StatusMessage;
end

GO

-- Requirement 7, first half.
create or alter procedure procCheckIn
(
    @ReservationID INT
)
as
begin
    declare @Status NVARCHAR(20);
    declare @RoomID INT;

    select @Status = ReservationStatus from Reservation where ReservationID = @ReservationID;

    if (@Status IS NULL)
    begin
        select 'No such reservation.' as StatusMessage;
        return;
    end

    if (@Status <> 'Booked')
    begin
        select 'Only a booked reservation can be checked in.' as StatusMessage;
        return;
    end

    update Reservation
    set ReservationStatus = 'CheckedIn',
        CheckInDateTime = GETDATE()
    where ReservationID = @ReservationID;

    select @RoomID = max(RoomID) from RoomAvailability where ReservationID = @ReservationID;

    if (@RoomID IS NOT NULL)
        update Room set CurrentStatus = 'In use' where RoomID = @RoomID;

    select 'Reservation checked in successfully.' as StatusMessage;
end

GO

-- Requirement 7, second half.
create or alter procedure procCheckOut
(
    @ReservationID INT
)
as
begin
    declare @Status NVARCHAR(20);
    declare @RoomID INT;

    select @Status = ReservationStatus from Reservation where ReservationID = @ReservationID;

    if (@Status IS NULL)
    begin
        select 'No such reservation.' as StatusMessage;
        return;
    end

    if (@Status <> 'CheckedIn')
    begin
        select 'Only a checked-in reservation can be checked out.' as StatusMessage;
        return;
    end

    update Reservation
    set ReservationStatus = 'Completed',
        CheckOutDateTime = GETDATE()
    where ReservationID = @ReservationID;

    select @RoomID = max(RoomID) from RoomAvailability where ReservationID = @ReservationID;

    if (@RoomID IS NOT NULL)
        update Room set CurrentStatus = 'Available' where RoomID = @RoomID;

    select 'Reservation checked out successfully.' as StatusMessage;
end

GO

GO

-- A cancelled reservation is history. Cancelling already handed its slots
-- back to the pool, so putting the status back to 'Booked' would leave two
-- students holding the same room. rollback transaction undoes whichever
-- update set the trigger off.
create or alter trigger trgProtectCancelledReservation
on Reservation
after update
as
begin
    declare @OldStatus NVARCHAR(20);
    declare @NewStatus NVARCHAR(20);

    select @OldStatus = ReservationStatus from deleted;
    select @NewStatus = ReservationStatus from inserted;

    if (@OldStatus = 'Cancelled' and @NewStatus <> 'Cancelled')
        rollback transaction;
end
