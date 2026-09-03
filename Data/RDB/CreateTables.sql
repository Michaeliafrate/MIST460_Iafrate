/*
    CreateTables.sql -- relational schema for the MIST 460 project.

    Target: Azure SQL Database. There is no USE statement because Azure SQL
    does not allow switching databases on a connection; run this while
    connected to the project database.

    Drop order is the reverse of create order so foreign keys never block a
    rerun. The whole script is idempotent -- run it as many times as you like.
*/

DROP TABLE IF EXISTS dbo.OrderLine;
DROP TABLE IF EXISTS dbo.CustomerOrder;
DROP TABLE IF EXISTS dbo.Product;
DROP TABLE IF EXISTS dbo.Customer;
GO

CREATE TABLE dbo.Customer (
    CustomerID   INT           IDENTITY(1,1) NOT NULL,
    FirstName    NVARCHAR(50)  NOT NULL,
    LastName     NVARCHAR(50)  NOT NULL,
    Email        NVARCHAR(255) NOT NULL,
    City         NVARCHAR(100) NULL,
    State        CHAR(2)       NULL,
    CreatedAt    DATETIME2(0)  NOT NULL CONSTRAINT DF_Customer_CreatedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Customer PRIMARY KEY (CustomerID),
    CONSTRAINT UQ_Customer_Email UNIQUE (Email)
);
GO

CREATE TABLE dbo.Product (
    ProductID    INT            IDENTITY(1,1) NOT NULL,
    SKU          VARCHAR(20)    NOT NULL,
    ProductName  NVARCHAR(120)  NOT NULL,
    UnitPrice    DECIMAL(10,2)  NOT NULL,
    Discontinued BIT            NOT NULL CONSTRAINT DF_Product_Discontinued DEFAULT 0,
    CONSTRAINT PK_Product PRIMARY KEY (ProductID),
    CONSTRAINT UQ_Product_SKU UNIQUE (SKU),
    CONSTRAINT CK_Product_UnitPrice CHECK (UnitPrice >= 0)
);
GO

CREATE TABLE dbo.CustomerOrder (
    OrderID     INT          IDENTITY(1,1) NOT NULL,
    CustomerID  INT          NOT NULL,
    OrderDate   DATE         NOT NULL CONSTRAINT DF_CustomerOrder_OrderDate DEFAULT CAST(SYSUTCDATETIME() AS DATE),
    Status      VARCHAR(20)  NOT NULL CONSTRAINT DF_CustomerOrder_Status DEFAULT 'Open',
    CONSTRAINT PK_CustomerOrder PRIMARY KEY (OrderID),
    CONSTRAINT FK_CustomerOrder_Customer FOREIGN KEY (CustomerID)
        REFERENCES dbo.Customer (CustomerID),
    CONSTRAINT CK_CustomerOrder_Status CHECK (Status IN ('Open', 'Shipped', 'Cancelled'))
);
GO

-- The composite key means a product can appear on an order only once; change
-- the quantity instead of adding a second line for the same product.
CREATE TABLE dbo.OrderLine (
    OrderID    INT           NOT NULL,
    ProductID  INT           NOT NULL,
    Quantity   INT           NOT NULL,
    UnitPrice  DECIMAL(10,2) NOT NULL,
    CONSTRAINT PK_OrderLine PRIMARY KEY (OrderID, ProductID),
    CONSTRAINT FK_OrderLine_Order FOREIGN KEY (OrderID)
        REFERENCES dbo.CustomerOrder (OrderID) ON DELETE CASCADE,
    CONSTRAINT FK_OrderLine_Product FOREIGN KEY (ProductID)
        REFERENCES dbo.Product (ProductID),
    CONSTRAINT CK_OrderLine_Quantity CHECK (Quantity > 0)
);
GO

CREATE INDEX IX_CustomerOrder_CustomerID ON dbo.CustomerOrder (CustomerID);
GO
