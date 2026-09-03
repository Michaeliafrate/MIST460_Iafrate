/*
    InsertData.sql -- sample data for the MIST 460 project.

    Run after CreateTables.sql. Deletes existing rows first (children before
    parents) so the script can be rerun without duplicate-key errors, and
    reseeds the IDENTITY columns so the generated IDs stay predictable.
*/

DELETE FROM dbo.OrderLine;
DELETE FROM dbo.CustomerOrder;
DELETE FROM dbo.Product;
DELETE FROM dbo.Customer;
GO

DBCC CHECKIDENT ('dbo.CustomerOrder', RESEED, 0) WITH NO_INFOMSGS;
DBCC CHECKIDENT ('dbo.Product', RESEED, 0) WITH NO_INFOMSGS;
DBCC CHECKIDENT ('dbo.Customer', RESEED, 0) WITH NO_INFOMSGS;
GO

INSERT INTO dbo.Customer (FirstName, LastName, Email, City, State) VALUES
    ('Michael', 'Iafrate',  'miafrate@example.com',  'Morgantown', 'WV'),
    ('Dana',    'Whitfield','dwhitfield@example.com','Pittsburgh', 'PA'),
    ('Luis',    'Ortega',   'lortega@example.com',   'Columbus',   'OH'),
    ('Priya',   'Raman',    'praman@example.com',    'Charleston', 'WV');
GO

INSERT INTO dbo.Product (SKU, ProductName, UnitPrice, Discontinued) VALUES
    ('KB-1001', 'Mechanical Keyboard',   89.99, 0),
    ('MS-2002', 'Wireless Mouse',        24.50, 0),
    ('MN-3003', '27in 1440p Monitor',   279.00, 0),
    ('DK-4004', 'USB-C Docking Station',149.95, 0),
    ('HS-5005', 'Wired Headset',         39.00, 1);
GO

INSERT INTO dbo.CustomerOrder (CustomerID, OrderDate, Status) VALUES
    (1, '2026-08-14', 'Shipped'),
    (1, '2026-08-29', 'Open'),
    (2, '2026-08-30', 'Open'),
    (3, '2026-07-02', 'Cancelled');
GO

-- No line references the discontinued product (HS-5005): once
-- ProgrammingObjects.sql is applied its trigger rejects those, and this
-- script has to stay rerunnable. Use it to test the trigger instead.
-- UnitPrice is copied onto the line on purpose: an order keeps the price that
-- was charged at the time, even if dbo.Product is repriced later.
INSERT INTO dbo.OrderLine (OrderID, ProductID, Quantity, UnitPrice) VALUES
    (1, 1, 1,  89.99),
    (1, 2, 2,  24.50),
    (2, 3, 1, 279.00),
    (3, 4, 1, 149.95),
    (3, 2, 1,  24.50),
    (4, 1, 1,  89.99);
GO

SELECT 'Customer' AS TableName, COUNT(*) AS RowTotal FROM dbo.Customer
UNION ALL SELECT 'Product',       COUNT(*) FROM dbo.Product
UNION ALL SELECT 'CustomerOrder', COUNT(*) FROM dbo.CustomerOrder
UNION ALL SELECT 'OrderLine',     COUNT(*) FROM dbo.OrderLine;
GO
