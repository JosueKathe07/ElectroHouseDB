/* =========================================================================
   1. CREAR BASE DE DATOS (SI NO EXISTE) Y USARLA
   ========================================================================= */
IF DB_ID('ElectroHouseDB') IS NULL
BEGIN
    CREATE DATABASE ElectroHouseDB;
END;
GO

USE ElectroHouseDB;
GO

/* =========================================================================
   2. ELIMINAR TABLAS SI YA EXISTEN (PARA EVITAR ERRORES AL REEJECUTAR)
   ========================================================================= */
IF OBJECT_ID('dbo.Ordenes', 'U') IS NOT NULL
    DROP TABLE dbo.Ordenes;
GO

IF OBJECT_ID('dbo.Productos', 'U') IS NOT NULL
    DROP TABLE dbo.Productos;
GO

IF OBJECT_ID('dbo.Clientes', 'U') IS NOT NULL
    DROP TABLE dbo.Clientes;
GO

/* =========================================================================
   3. CREAR TABLAS: CLIENTES, PRODUCTOS, ORDENES
   ========================================================================= */

-- Tabla Clientes
CREATE TABLE dbo.Clientes
(
    ClienteID      INT IDENTITY(1,1)      NOT NULL PRIMARY KEY,
    Nombre         NVARCHAR(100)          NOT NULL,
    Email          NVARCHAR(150)          NOT NULL UNIQUE,
    Telefono       NVARCHAR(20)           NULL,
    FechaRegistro  DATETIME               NOT NULL DEFAULT(GETDATE())
);
GO

-- Tabla Productos
CREATE TABLE dbo.Productos
(
    ProductoID     INT IDENTITY(1,1)      NOT NULL PRIMARY KEY,
    Nombre         NVARCHAR(100)          NOT NULL,
    Descripcion    NVARCHAR(255)          NULL,
    Precio         DECIMAL(10,2)          NOT NULL CHECK (Precio > 0),
    Stock          INT                    NOT NULL CHECK (Stock >= 0),
    Activo         BIT                    NOT NULL DEFAULT(1)
);
GO

-- Tabla Ordenes
CREATE TABLE dbo.Ordenes
(
    OrdenID        INT IDENTITY(1,1)      NOT NULL PRIMARY KEY,
    ClienteID      INT                    NOT NULL,
    ProductoID     INT                    NOT NULL,
    FechaOrden     DATETIME               NOT NULL DEFAULT(GETDATE()),
    Cantidad       INT                    NOT NULL CHECK (Cantidad > 0),
    PrecioUnitario DECIMAL(10,2)          NOT NULL CHECK (PrecioUnitario > 0),
    -- Total calculado como Cantidad * PrecioUnitario
    Total          AS (Cantidad * PrecioUnitario) PERSISTED
);
GO

-- Llaves foráneas
ALTER TABLE dbo.Ordenes
ADD CONSTRAINT FK_Ordenes_Clientes
    FOREIGN KEY (ClienteID)
    REFERENCES dbo.Clientes (ClienteID);

ALTER TABLE dbo.Ordenes
ADD CONSTRAINT FK_Ordenes_Productos
    FOREIGN KEY (ProductoID)
    REFERENCES dbo.Productos (ProductoID);
GO

/* =========================================================================
   4. INSERTAR DATOS INICIALES (INVENTARIO Y CLIENTES)
   ========================================================================= */

-- Clientes
INSERT INTO dbo.Clientes (Nombre, Email, Telefono)
VALUES
('Carlos Ramírez',     'carlos.ramirez@correo.com',   '8888-1111'),
('María Fernández',    'maria.fernandez@correo.com',  '8888-2222'),
('Luis Rodríguez',     'luis.rodriguez@correo.com',   '8888-3333'),
('Ana Gómez',          'ana.gomez@correo.com',        '8888-4444');
GO

-- Productos
INSERT INTO dbo.Productos (Nombre, Descripcion, Precio, Stock)
VALUES
('Televisor 50" 4K',      'Smart TV 50 pulgadas 4K UHD',              550.00, 20),
('Laptop Gamer',          'Laptop gaming 16GB RAM, RTX 4060',        1200.00, 10),
('Auriculares Bluetooth', 'Auriculares inalámbricos con micrófono',   45.00,  50),
('Teclado Mecánico',      'Teclado mecánico retroiluminado',          80.00,  30),
('Mouse Inalámbrico',     'Mouse óptico inalámbrico',                 25.00,  60);
GO

/* =========================================================================
   5. INSERTAR ALGUNAS ORDENES DE EJEMPLO
   ========================================================================= */

-- Para usar IDs ya creados (los datos anteriores deben existir)
-- Ejemplo: Cliente 1 compra Televisor y Mouse
INSERT INTO dbo.Ordenes (ClienteID, ProductoID, Cantidad, PrecioUnitario)
VALUES
(1, 1, 1, 550.00),    -- Carlos compra 1 TV 50"
(1, 5, 2, 25.00),     -- Carlos compra 2 mouse
(2, 2, 1, 1200.00),   -- María compra 1 Laptop
(3, 3, 3, 45.00);     -- Luis compra 3 auriculares
GO

/* =========================================================================
   6. CONSULTAS SELECT
      a) Todos los productos con precio mayor a cierto valor
      b) Clientes con órdenes registradas
   ========================================================================= */

-- a) Productos con precio mayor a cierto valor
DECLARE @PrecioMin DECIMAL(10,2) = 100.00;

SELECT 
    ProductoID,
    Nombre,
    Precio,
    Stock
FROM dbo.Productos
WHERE Precio > @PrecioMin;
GO

-- b) Clientes con órdenes registradas
SELECT DISTINCT
    c.ClienteID,
    c.Nombre,
    c.Email,
    c.Telefono,
    c.FechaRegistro
FROM dbo.Clientes c
INNER JOIN dbo.Ordenes o
    ON c.ClienteID = o.ClienteID;
GO

/* =========================================================================
   7. JOIN PARA COMBINAR INFORMACIÓN DE CLIENTES Y SUS ÓRDENES
   ========================================================================= */

SELECT
    o.OrdenID,
    o.FechaOrden,
    c.Nombre       AS NombreCliente,
    c.Email        AS EmailCliente,
    p.Nombre       AS NombreProducto,
    o.Cantidad,
    o.PrecioUnitario,
    o.Total
FROM dbo.Ordenes o
INNER JOIN dbo.Clientes c
    ON o.ClienteID = c.ClienteID
INNER JOIN dbo.Productos p
    ON o.ProductoID = p.ProductoID
ORDER BY o.FechaOrden DESC;
GO

/* =========================================================================
   8. TRANSACCIÓN QUE SIMULA UNA VENTA
      - Disminuir stock del producto
      - Registrar la orden
      - COMMIT si todo OK, ROLLBACK en caso de error
   ========================================================================= */

DECLARE @ClienteIDTrans   INT             = 4;      -- Ej: Ana Gómez
DECLARE @ProductoIDTrans  INT             = 2;      -- Ej: Laptop Gamer
DECLARE @CantidadTrans    INT             = 2;      -- Cantidad a comprar
DECLARE @PrecioUnitTrans  DECIMAL(10,2);           -- Se obtendrá del producto
DECLARE @StockActual      INT;

-- Validar existencia del producto y obtener precio
SELECT 
    @PrecioUnitTrans = Precio,
    @StockActual     = Stock
FROM dbo.Productos
WHERE ProductoID = @ProductoIDTrans;

IF @PrecioUnitTrans IS NULL
BEGIN
    RAISERROR('El producto especificado no existe.', 16, 1);
    RETURN;
END;

-- Validar existencia del cliente
IF NOT EXISTS (SELECT 1 FROM dbo.Clientes WHERE ClienteID = @ClienteIDTrans)
BEGIN
    RAISERROR('El cliente especificado no existe.', 16, 1);
    RETURN;
END;

BEGIN TRY
    BEGIN TRANSACTION;

    -- Verificar stock suficiente
    IF @StockActual < @CantidadTrans
    BEGIN
        RAISERROR('Stock insuficiente para realizar la venta.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END;

    -- 1) Disminuir el stock del producto
    UPDATE dbo.Productos
    SET Stock = Stock - @CantidadTrans
    WHERE ProductoID = @ProductoIDTrans;

    -- 2) Registrar la orden
    INSERT INTO dbo.Ordenes (ClienteID, ProductoID, Cantidad, PrecioUnitario)
    VALUES (@ClienteIDTrans, @ProductoIDTrans, @CantidadTrans, @PrecioUnitTrans);

    -- 3) Confirmar cambios
    COMMIT TRANSACTION;
    PRINT 'Transacción realizada correctamente. Venta registrada.';
END TRY
BEGIN CATCH
    -- En caso de error, revertir cambios
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    DECLARE 
        @ErrorMessage NVARCHAR(4000),
        @ErrorSeverity INT,
        @ErrorState INT;

    SELECT 
        @ErrorMessage = ERROR_MESSAGE(),
        @ErrorSeverity = ERROR_SEVERITY(),
        @ErrorState = ERROR_STATE();

    RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
END CATCH;
GO

/* =========================================================================
   9. CONSULTAR RESULTADOS DE LA TRANSACCIÓN
   ========================================================================= */

-- Ver stock del producto afectado
SELECT ProductoID, Nombre, Precio, Stock
FROM dbo.Productos
WHERE ProductoID = @ProductoIDTrans;

-- Ver últimas órdenes registradas (incluye la de la transacción si se hizo COMMIT)
SELECT TOP 10
    o.OrdenID,
    o.FechaOrden,
    c.Nombre AS NombreCliente,
    p.Nombre AS NombreProducto,
    o.Cantidad,
    o.PrecioUnitario,
    o.Total
FROM dbo.Ordenes o
INNER JOIN dbo.Clientes c ON o.ClienteID = c.ClienteID
INNER JOIN dbo.Productos p ON o.ProductoID = p.ProductoID
ORDER BY o.OrdenID DESC;
GO

