/*
    ProgrammingObjects.sql -- views, functions, stored procedures, and triggers.

    Run after CreateTables.sql. Every object is dropped first so the script is
    rerunnable. CREATE VIEW / FUNCTION / PROCEDURE / TRIGGER each have to be the
    first statement in their batch, which is what the GO separators are for.
*/

DROP TRIGGER IF EXISTS dbo.TR_OrderLine_BlockDiscontinued;
DROP PROCEDURE IF EXISTS dbo.usp_PlaceOrder;
DROP FUNCTION IF EXISTS dbo.fn_OrderTotal;
DROP VIEW IF EXISTS dbo.vw_OrderSummary;
GO

/* ---------- View: one row per order with its customer and total ---------- */
CREATE VIEW dbo.vw_OrderSummary
AS
SELECT
    o.OrderID,
    o.OrderDate,
    o.Status,
    c.CustomerID,
    c.FirstName + ' ' + c.LastName AS CustomerName,
    COUNT(ol.ProductID)                        AS LineCount,
    ISNULL(SUM(ol.Quantity * ol.UnitPrice), 0) AS OrderTotal
FROM dbo.CustomerOrder AS o
JOIN dbo.Customer AS c
    ON c.CustomerID = o.CustomerID
LEFT JOIN dbo.OrderLine AS ol
    ON ol.OrderID = o.OrderID
GROUP BY o.OrderID, o.OrderDate, o.Status, c.CustomerID, c.FirstName, c.LastName;
GO

/* ---------- Scalar function: total for a single order ---------- */
CREATE FUNCTION dbo.fn_OrderTotal (@OrderID INT)
RETURNS DECIMAL(12,2)
AS
BEGIN
    DECLARE @Total DECIMAL(12,2);

    SELECT @Total = SUM(Quantity * UnitPrice)
    FROM dbo.OrderLine
    WHERE OrderID = @OrderID;

    RETURN ISNULL(@Total, 0);
END;
GO

/* ---------- Stored procedure: create an order and its first line ----------
    Wrapped in a transaction so a bad line cannot leave a headerless order
    behind. XACT_ABORT guarantees the rollback even on errors that would
    otherwise let the batch continue.
*/
CREATE PROCEDURE dbo.usp_PlaceOrder
    @CustomerID INT,
    @ProductID  INT,
    @Quantity   INT,
    @OrderID    INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Customer WHERE CustomerID = @CustomerID)
    BEGIN
        THROW 50001, 'No such customer.', 1;
    END;

    IF @Quantity <= 0
    BEGIN
        THROW 50002, 'Quantity must be greater than zero.', 1;
    END;

    BEGIN TRANSACTION;

        INSERT INTO dbo.CustomerOrder (CustomerID)
        VALUES (@CustomerID);

        SET @OrderID = SCOPE_IDENTITY();

        -- Price is read from the product now and stored on the line.
        INSERT INTO dbo.OrderLine (OrderID, ProductID, Quantity, UnitPrice)
        SELECT @OrderID, ProductID, @Quantity, UnitPrice
        FROM dbo.Product
        WHERE ProductID = @ProductID;

        IF @@ROWCOUNT = 0
        BEGIN
            THROW 50003, 'No such product.', 1;
        END;

    COMMIT TRANSACTION;
END;
GO

/* ---------- Trigger: keep discontinued products off new order lines ----------
    AFTER trigger on a set of rows, not a row-at-a-time trigger: it tests
    "does inserted contain any discontinued product" rather than assuming a
    single row was inserted.
*/
CREATE TRIGGER dbo.TR_OrderLine_BlockDiscontinued
ON dbo.OrderLine
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted AS i
        JOIN dbo.Product AS p ON p.ProductID = i.ProductID
        WHERE p.Discontinued = 1
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50004, 'That product is discontinued and cannot be ordered.', 1;
    END;
END;
GO
