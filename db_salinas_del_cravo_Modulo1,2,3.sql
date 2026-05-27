-- ============================================================
-- 1. CREACIÓN DE LA BASE DE DATOS
-- ============================================================
DROP DATABASE IF EXISTS salinas_del_cravo_v2;
CREATE DATABASE salinas_del_cravo_v2
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE salinas_del_cravo_v2;


-- ============================================================
-- 2. DDL — CREACIÓN DE TABLAS
-- ============================================================

-- ------------------------------------------------------------
-- 2.1  CLIENTE
-- Veterinarias y ganaderos que realizan compras de sal.
-- ------------------------------------------------------------
CREATE TABLE cliente (
    id_cliente          INT             NOT NULL AUTO_INCREMENT PRIMARY KEY,
    nit_cedula          VARCHAR(25)     NOT NULL,
    nombre_cliente      VARCHAR(150)    NOT NULL,
    telefono            VARCHAR(20)         NULL,
    email               VARCHAR(100)        NULL,
    direccion_entrega   VARCHAR(255)        NULL,
    tipo                ENUM('VETERINARIA','GANADERO') NOT NULL DEFAULT 'VETERINARIA',
    estado_activo       TINYINT(1)      NOT NULL DEFAULT 1,
    CONSTRAINT uq_cliente_nit   UNIQUE (nit_cedula),
    CONSTRAINT uq_cliente_email UNIQUE (email)
);

-- ------------------------------------------------------------
-- 2.2  USUARIO
-- Tabla base de la jerarquía Administrador / Vendedor.
-- Herencia implementada con tablas especializadas (1:1).
-- ------------------------------------------------------------
CREATE TABLE usuario (
    id_usuario          INT             NOT NULL AUTO_INCREMENT PRIMARY KEY,
    nombre_completo     VARCHAR(150)    NOT NULL,
    username            VARCHAR(60)     NOT NULL,
    email               VARCHAR(100)    NOT NULL,
    password_hash       VARCHAR(255)    NOT NULL,
    rol                 ENUM('ADMIN','VENDEDOR') NOT NULL,
    estado_activo       TINYINT(1)      NOT NULL DEFAULT 1,
    CONSTRAINT uq_usuario_username  UNIQUE (username),
    CONSTRAINT uq_usuario_email     UNIQUE (email)
);

-- ------------------------------------------------------------
-- 2.3  ADMINISTRADOR
-- Especialización de usuario con rol ADMIN.
-- PK es también FK hacia usuario (sin AUTO_INCREMENT).
-- ------------------------------------------------------------
CREATE TABLE administrador (
    id_usuario              INT         NOT NULL PRIMARY KEY,
    ultimo_acceso_admin     DATETIME        NULL,
    CONSTRAINT fk_admin_usuario
        FOREIGN KEY (id_usuario) REFERENCES usuario (id_usuario)
        ON UPDATE CASCADE ON DELETE CASCADE
);

-- ------------------------------------------------------------
-- 2.4  VENDEDOR
-- Especialización de usuario con rol VENDEDOR.
-- PK es también FK hacia usuario (sin AUTO_INCREMENT).
-- ------------------------------------------------------------
CREATE TABLE vendedor (
    id_usuario          INT             NOT NULL PRIMARY KEY,
    codigo_terminal     VARCHAR(20)     NOT NULL,
    ventas_mes_actual   INT             NOT NULL DEFAULT 0,
    CONSTRAINT uq_vendedor_terminal UNIQUE (codigo_terminal),
    CONSTRAINT fk_vendedor_usuario
        FOREIGN KEY (id_usuario) REFERENCES usuario (id_usuario)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT ck_ventas_mes
        CHECK (ventas_mes_actual >= 0)
);

-- ------------------------------------------------------------
-- 2.5  CATEGORIA
-- Catálogo de líneas de sal mineralizada según % de fósforo.
-- ------------------------------------------------------------
CREATE TABLE categoria (
    id_categoria        INT             NOT NULL AUTO_INCREMENT PRIMARY KEY,
    nombre_categoria    VARCHAR(100)    NOT NULL,
    descripcion_uso     VARCHAR(255)    NOT NULL,
    porcentaje_fosforo  DECIMAL(5,2)    NOT NULL,
    CONSTRAINT uq_categoria_nombre  UNIQUE (nombre_categoria),
    CONSTRAINT ck_fosforo_rango
        CHECK (porcentaje_fosforo BETWEEN 0 AND 100)
);

-- ------------------------------------------------------------
-- 2.6  PRODUCTO
-- Cada SKU: combinación de concentración y presentación.
-- ------------------------------------------------------------
CREATE TABLE producto (
    id_producto             INT             NOT NULL AUTO_INCREMENT PRIMARY KEY,
    id_categoria            INT             NOT NULL,
    nombre_sal_mineralizada VARCHAR(150)    NOT NULL,
    peso_bulto_kg           DECIMAL(7,2)    NOT NULL,
    unidad_medida           VARCHAR(50)     NOT NULL  COMMENT 'Ej: 1kg, 5kg, granel, mochila',
    descontinuado           TINYINT(1)      NOT NULL  DEFAULT 0,
    CONSTRAINT ck_peso_positivo
        CHECK (peso_bulto_kg > 0),
    CONSTRAINT fk_producto_categoria
        FOREIGN KEY (id_categoria) REFERENCES categoria (id_categoria)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

-- ------------------------------------------------------------
-- 2.7  BODEGA
-- Sedes físicas donde se almacena el inventario.
-- ------------------------------------------------------------
CREATE TABLE bodega (
    id_bodega               INT             NOT NULL AUTO_INCREMENT PRIMARY KEY,
    nombre_bodega           VARCHAR(100)    NOT NULL,
    direccion_fisica        VARCHAR(255)    NOT NULL,
    capacidad_maxima_bultos INT             NOT NULL,
    estado_activo           TINYINT(1)      NOT NULL DEFAULT 1,
    CONSTRAINT ck_capacidad_positiva
        CHECK (capacidad_maxima_bultos > 0)
);

-- ------------------------------------------------------------
-- 2.8  STOCK
-- Nivel actual de existencias de cada producto en cada bodega.
-- Es el nodo central que entradas, salidas y devoluciones actualizan.
-- ------------------------------------------------------------
CREATE TABLE stock (
    id_stock                INT             NOT NULL AUTO_INCREMENT PRIMARY KEY,
    id_producto             INT             NOT NULL,
    id_bodega               INT             NOT NULL,
    cantidad_actual         INT             NOT NULL DEFAULT 0,
    stock_minimo_seguridad  INT             NOT NULL DEFAULT 0,
    fecha_ultima_auditoria  DATETIME        NOT NULL,
    CONSTRAINT uq_stock_prod_bod    UNIQUE (id_producto, id_bodega),
    CONSTRAINT ck_cantidad_no_neg   CHECK (cantidad_actual >= 0),
    CONSTRAINT ck_minimo_no_neg     CHECK (stock_minimo_seguridad >= 0),
    CONSTRAINT fk_stock_producto
        FOREIGN KEY (id_producto) REFERENCES producto (id_producto)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_stock_bodega
        FOREIGN KEY (id_bodega) REFERENCES bodega (id_bodega)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

-- ------------------------------------------------------------
-- 2.9  MOVIMIENTO_INVENTARIO
-- Registro maestro de toda transacción sobre el inventario.
-- id_reporte es NULL hasta que se genera el reporte asociado.
-- ------------------------------------------------------------
CREATE TABLE movimiento_inventario (
    id_movimiento       INT             NOT NULL AUTO_INCREMENT PRIMARY KEY,
    id_producto         INT             NOT NULL,
    id_usuario          INT             NOT NULL,
    id_bodega           INT             NOT NULL,
    id_reporte          INT                 NULL  COMMENT 'Se asigna al generar el reporte',
    fecha_movimiento    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    tipo_movimiento     ENUM('ENTRADA','SALIDA','AJUSTE','DEVOLUCION') NOT NULL,
    cantidad_bultos     INT             NOT NULL,
    observaciones       TEXT                NULL,
    CONSTRAINT ck_mov_cantidad_pos
        CHECK (cantidad_bultos > 0),
    CONSTRAINT fk_mov_producto
        FOREIGN KEY (id_producto) REFERENCES producto (id_producto)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_mov_usuario
        FOREIGN KEY (id_usuario) REFERENCES usuario (id_usuario)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_mov_bodega
        FOREIGN KEY (id_bodega) REFERENCES bodega (id_bodega)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

-- ------------------------------------------------------------
-- 2.10  REPORTE
-- Agrupa movimientos en períodos para análisis gerencial.
-- La FK hacia movimiento_inventario se añade con ALTER TABLE
-- para romper la dependencia circular entre ambas tablas.
-- ------------------------------------------------------------
CREATE TABLE reporte (
    id_reporte          INT             NOT NULL AUTO_INCREMENT PRIMARY KEY,
    id_usuario          INT             NOT NULL  COMMENT 'Usuario que generó el reporte',
    fecha_emision       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    rango_fechas        VARCHAR(100)        NULL  COMMENT 'Ej: 2026-01-01 / 2026-03-31',
    tipo_reporte        ENUM('STOCK','SALIDAS','ENTRADAS','HISTORIAL','PERDIDAS') NOT NULL,
    resumen             TEXT                NULL,
    CONSTRAINT fk_reporte_usuario
        FOREIGN KEY (id_usuario) REFERENCES usuario (id_usuario)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

-- FK de movimiento_inventario hacia reporte (rompe ciclo de dependencia).
ALTER TABLE movimiento_inventario
    ADD CONSTRAINT fk_mov_reporte
        FOREIGN KEY (id_reporte) REFERENCES reporte (id_reporte)
        ON UPDATE CASCADE ON DELETE SET NULL;

-- ------------------------------------------------------------
-- 2.11  ENTRADA
-- Registro detallado de ingresos de mercancía a una bodega.
-- Cada entrada incrementa el stock correspondiente.
-- ------------------------------------------------------------
CREATE TABLE entrada (
    id_entrada          INT             NOT NULL AUTO_INCREMENT PRIMARY KEY,
    id_stock            INT             NOT NULL  COMMENT 'Stock que se incrementa',
    id_usuario          INT             NOT NULL  COMMENT 'Usuario que registra la entrada',
    id_bodega           INT             NOT NULL,
    id_movimiento       INT             NOT NULL  COMMENT 'Movimiento maestro asociado',
    id_proveedor        INT                 NULL  COMMENT 'Referencia externa al proveedor',
    fecha_entrada       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    cantidad_ingresada  INT             NOT NULL,
    tipo_ingreso        VARCHAR(80)     NOT NULL  COMMENT 'Ej: compra, reposición, donación',
    numero_lote         VARCHAR(50)         NULL  COMMENT 'Trazabilidad por número de lote',
    observaciones       TEXT                NULL,
    CONSTRAINT ck_entrada_cantidad
        CHECK (cantidad_ingresada > 0),
    CONSTRAINT fk_entrada_stock
        FOREIGN KEY (id_stock) REFERENCES stock (id_stock)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_entrada_usuario
        FOREIGN KEY (id_usuario) REFERENCES usuario (id_usuario)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_entrada_bodega
        FOREIGN KEY (id_bodega) REFERENCES bodega (id_bodega)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_entrada_movimiento
        FOREIGN KEY (id_movimiento) REFERENCES movimiento_inventario (id_movimiento)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

-- ------------------------------------------------------------
-- 2.12  SALIDA
-- Despacho de bultos a un cliente.
-- Cada salida decrementa el stock de la bodega de origen.
-- ------------------------------------------------------------
CREATE TABLE salida (
    id_salida           INT             NOT NULL AUTO_INCREMENT PRIMARY KEY,
    id_cliente          INT             NOT NULL,
    id_usuario          INT             NOT NULL  COMMENT 'Vendedor que registra la salida',
    id_stock            INT             NOT NULL  COMMENT 'Stock que se decrementa',
    id_movimiento       INT             NOT NULL  COMMENT 'Movimiento maestro asociado',
    fecha_salida        DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    cantidad_salida     INT             NOT NULL,
    destino_bodega      VARCHAR(150)        NULL  COMMENT 'Bodega o dirección de destino',
    tipo_mov_salida     VARCHAR(80)         NULL  COMMENT 'Ej: venta, consignación',
    motivo_salida       VARCHAR(255)        NULL,
    observaciones       TEXT                NULL,
    CONSTRAINT ck_salida_cantidad
        CHECK (cantidad_salida > 0),
    CONSTRAINT fk_salida_cliente
        FOREIGN KEY (id_cliente) REFERENCES cliente (id_cliente)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_salida_usuario
        FOREIGN KEY (id_usuario) REFERENCES usuario (id_usuario)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_salida_stock
        FOREIGN KEY (id_stock) REFERENCES stock (id_stock)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_salida_movimiento
        FOREIGN KEY (id_movimiento) REFERENCES movimiento_inventario (id_movimiento)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

-- ------------------------------------------------------------
-- 2.13  DEVOLUCION
-- Mercancía devuelta por un cliente.
-- Si genera_entrada = 1, el stock fue reincorporado.
-- ------------------------------------------------------------
CREATE TABLE devolucion (
    id_devolucion               INT             NOT NULL AUTO_INCREMENT PRIMARY KEY,
    id_stock                    INT             NOT NULL  COMMENT 'Stock al que se reincorpora',
    id_movimiento_relacionado   INT             NOT NULL  COMMENT 'Movimiento de salida original',
    id_bodega                   INT             NOT NULL,
    id_cliente                  INT             NOT NULL  COMMENT 'Cliente que devuelve',
    id_usuario                  INT             NOT NULL  COMMENT 'Usuario que registra la devolución',
    fecha_devolucion            DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    cantidad_devuelta           INT             NOT NULL,
    motivo_devolucion           VARCHAR(255)        NULL,
    estado_producto             ENUM('BUENO','DAÑADO','PARCIAL') NOT NULL DEFAULT 'BUENO',
    genera_entrada              TINYINT(1)      NOT NULL DEFAULT 0 COMMENT '1 si se reincorporó al stock',
    observaciones               TEXT                NULL,
    CONSTRAINT ck_dev_cantidad
        CHECK (cantidad_devuelta > 0),
    CONSTRAINT fk_dev_stock
        FOREIGN KEY (id_stock) REFERENCES stock (id_stock)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_dev_movimiento
        FOREIGN KEY (id_movimiento_relacionado) REFERENCES movimiento_inventario (id_movimiento)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_dev_bodega
        FOREIGN KEY (id_bodega) REFERENCES bodega (id_bodega)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_dev_cliente
        FOREIGN KEY (id_cliente) REFERENCES cliente (id_cliente)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_dev_usuario
        FOREIGN KEY (id_usuario) REFERENCES usuario (id_usuario)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

-- ============================================================
-- DML COMPLETO — salinas_del_cravo_v2
-- Generado automáticamente
-- ============================================================


INSERT INTO categoria (nombre_categoria, descripcion_uso, porcentaje_fosforo) VALUES
('Sal Mineralizada 12%', 'Especial para ganado de leche', 12.0),
('Sal Mineralizada 8%', 'Ganado doble propósito', 8.0),
('Sal Mineralizada 4%', 'Ganado de ceba', 4.0);


INSERT INTO producto (id_categoria,nombre_sal_mineralizada,peso_bulto_kg,unidad_medida,descontinuado)
VALUES (1,'Sal Mineralizada 12% - Bulto 50kg 1kg',50,'1kg',0);


INSERT INTO producto (id_categoria,nombre_sal_mineralizada,peso_bulto_kg,unidad_medida,descontinuado)
VALUES (1,'Sal Mineralizada 12% - Bulto 50kg 5kg',50,'5kg',0);


INSERT INTO producto (id_categoria,nombre_sal_mineralizada,peso_bulto_kg,unidad_medida,descontinuado)
VALUES (1,'Sal Mineralizada 12% - Bulto 40kg Granel',40,'granel',0);


INSERT INTO producto (id_categoria,nombre_sal_mineralizada,peso_bulto_kg,unidad_medida,descontinuado)
VALUES (1,'Sal Mineralizada 12% - Mochila 10kg',10,'mochila',0);


INSERT INTO producto (id_categoria,nombre_sal_mineralizada,peso_bulto_kg,unidad_medida,descontinuado)
VALUES (2,'Sal Mineralizada 8% - Bulto 50kg 1kg',50,'1kg',0);


INSERT INTO producto (id_categoria,nombre_sal_mineralizada,peso_bulto_kg,unidad_medida,descontinuado)
VALUES (2,'Sal Mineralizada 8% - Bulto 50kg 5kg',50,'5kg',0);


INSERT INTO producto (id_categoria,nombre_sal_mineralizada,peso_bulto_kg,unidad_medida,descontinuado)
VALUES (2,'Sal Mineralizada 8% - Bulto 40kg Granel',40,'granel',0);


INSERT INTO producto (id_categoria,nombre_sal_mineralizada,peso_bulto_kg,unidad_medida,descontinuado)
VALUES (2,'Sal Mineralizada 8% - Mochila 10kg',10,'mochila',0);


INSERT INTO producto (id_categoria,nombre_sal_mineralizada,peso_bulto_kg,unidad_medida,descontinuado)
VALUES (3,'Sal Mineralizada 4% - Bulto 50kg 1kg',50,'1kg',0);


INSERT INTO producto (id_categoria,nombre_sal_mineralizada,peso_bulto_kg,unidad_medida,descontinuado)
VALUES (3,'Sal Mineralizada 4% - Bulto 50kg 5kg',50,'5kg',0);


INSERT INTO producto (id_categoria,nombre_sal_mineralizada,peso_bulto_kg,unidad_medida,descontinuado)
VALUES (3,'Sal Mineralizada 4% - Bulto 40kg Granel',40,'granel',0);


INSERT INTO producto (id_categoria,nombre_sal_mineralizada,peso_bulto_kg,unidad_medida,descontinuado)
VALUES (3,'Sal Mineralizada 4% - Mochila 10kg',10,'mochila',0);


INSERT INTO bodega (nombre_bodega,direccion_fisica,capacidad_maxima_bultos,estado_activo) VALUES
('Bodega Principal Sogamoso','Calle 14 #12-35 Sogamoso',2000,1),
('Bodega Norte Duitama','Carrera 10 #8-22 Duitama',1200,1),
('Bodega Tunja','Calle 9 #6-10 Tunja',900,1);


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (1,1,407,13,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (1,2,92,33,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (1,3,220,17,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (2,1,194,14,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (2,2,457,13,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (2,3,426,33,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (3,1,359,12,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (3,2,382,23,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (3,3,96,10,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (4,1,127,16,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (4,2,199,26,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (4,3,388,10,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (5,1,367,16,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (5,2,446,30,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (5,3,439,27,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (6,1,294,17,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (6,2,309,28,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (6,3,222,35,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (7,1,83,34,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (7,2,492,15,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (7,3,437,23,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (8,1,254,18,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (8,2,159,16,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (8,3,470,20,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (9,1,132,12,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (9,2,274,13,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (9,3,263,37,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (10,1,256,29,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (10,2,215,35,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (10,3,102,33,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (11,1,315,27,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (11,2,143,39,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (11,3,273,12,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (12,1,362,19,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (12,2,401,29,'2026-04-01 08:00:00');


INSERT INTO stock (id_producto,id_bodega,cantidad_actual,stock_minimo_seguridad,fecha_ultima_auditoria)
VALUES (12,3,265,28,'2026-04-01 08:00:00');


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo) VALUES
('Carlos Andres Rondon','carondons','carondons@salinas.com',SHA2('Admin2026!',256),'ADMIN',1),
('Luz Marina Vargas','lmvargas','lmvargas@salinas.com',SHA2('Admin2026!',256),'ADMIN',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 3','vend3','vend3@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 4','vend4','vend4@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 5','vend5','vend5@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 6','vend6','vend6@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 7','vend7','vend7@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 8','vend8','vend8@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 9','vend9','vend9@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 10','vend10','vend10@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 11','vend11','vend11@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 12','vend12','vend12@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 13','vend13','vend13@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 14','vend14','vend14@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 15','vend15','vend15@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 16','vend16','vend16@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 17','vend17','vend17@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 18','vend18','vend18@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 19','vend19','vend19@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 20','vend20','vend20@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 21','vend21','vend21@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 22','vend22','vend22@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 23','vend23','vend23@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 24','vend24','vend24@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 25','vend25','vend25@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 26','vend26','vend26@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 27','vend27','vend27@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 28','vend28','vend28@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 29','vend29','vend29@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 30','vend30','vend30@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 31','vend31','vend31@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 32','vend32','vend32@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 33','vend33','vend33@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 34','vend34','vend34@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 35','vend35','vend35@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 36','vend36','vend36@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 37','vend37','vend37@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 38','vend38','vend38@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 39','vend39','vend39@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 40','vend40','vend40@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 41','vend41','vend41@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 42','vend42','vend42@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 43','vend43','vend43@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 44','vend44','vend44@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 45','vend45','vend45@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 46','vend46','vend46@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 47','vend47','vend47@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 48','vend48','vend48@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 49','vend49','vend49@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 50','vend50','vend50@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 51','vend51','vend51@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO usuario (nombre_completo,username,email,password_hash,rol,estado_activo)
VALUES ('Vendedor 52','vend52','vend52@salinas.com',SHA2('Vend2026#',256),'VENDEDOR',1);


INSERT INTO administrador (id_usuario,ultimo_acceso_admin) VALUES
(1,'2026-04-20 08:00:00'),
(2,'2026-04-20 09:00:00');


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (3,'TRM-003',17);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (4,'TRM-004',9);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (5,'TRM-005',7);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (6,'TRM-006',19);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (7,'TRM-007',23);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (8,'TRM-008',10);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (9,'TRM-009',19);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (10,'TRM-010',11);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (11,'TRM-011',29);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (12,'TRM-012',22);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (13,'TRM-013',34);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (14,'TRM-014',28);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (15,'TRM-015',15);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (16,'TRM-016',28);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (17,'TRM-017',27);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (18,'TRM-018',18);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (19,'TRM-019',22);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (20,'TRM-020',9);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (21,'TRM-021',15);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (22,'TRM-022',39);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (23,'TRM-023',20);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (24,'TRM-024',15);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (25,'TRM-025',34);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (26,'TRM-026',29);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (27,'TRM-027',22);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (28,'TRM-028',40);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (29,'TRM-029',19);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (30,'TRM-030',25);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (31,'TRM-031',8);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (32,'TRM-032',19);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (33,'TRM-033',7);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (34,'TRM-034',25);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (35,'TRM-035',30);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (36,'TRM-036',22);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (37,'TRM-037',9);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (38,'TRM-038',18);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (39,'TRM-039',25);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (40,'TRM-040',18);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (41,'TRM-041',36);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (42,'TRM-042',30);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (43,'TRM-043',34);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (44,'TRM-044',14);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (45,'TRM-045',21);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (46,'TRM-046',13);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (47,'TRM-047',20);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (48,'TRM-048',40);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (49,'TRM-049',39);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (50,'TRM-050',21);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (51,'TRM-051',32);


INSERT INTO vendedor (id_usuario,codigo_terminal,ventas_mes_actual)
VALUES (52,'TRM-052',30);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000001-1','Cliente Agropecuario 1','3488690725',
'cliente1@correo.com','Direccion 1 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000002-2','Cliente Agropecuario 2','3335493870',
'cliente2@correo.com','Direccion 2 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000003-3','Cliente Agropecuario 3','3248532577',
'cliente3@correo.com','Direccion 3 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000004-4','Cliente Agropecuario 4','3647099690',
'cliente4@correo.com','Direccion 4 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000005-5','Cliente Agropecuario 5','3629908599',
'cliente5@correo.com','Direccion 5 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000006-6','Cliente Agropecuario 6','3197613238',
'cliente6@correo.com','Direccion 6 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000007-7','Cliente Agropecuario 7','3911514914',
'cliente7@correo.com','Direccion 7 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000008-8','Cliente Agropecuario 8','3150590821',
'cliente8@correo.com','Direccion 8 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000009-0','Cliente Agropecuario 9','3217734861',
'cliente9@correo.com','Direccion 9 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000010-1','Cliente Agropecuario 10','3264112119',
'cliente10@correo.com','Direccion 10 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000011-2','Cliente Agropecuario 11','3773715057',
'cliente11@correo.com','Direccion 11 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000012-3','Cliente Agropecuario 12','3271779360',
'cliente12@correo.com','Direccion 12 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000013-4','Cliente Agropecuario 13','3950488739',
'cliente13@correo.com','Direccion 13 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000014-5','Cliente Agropecuario 14','3830661141',
'cliente14@correo.com','Direccion 14 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000015-6','Cliente Agropecuario 15','3553290810',
'cliente15@correo.com','Direccion 15 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000016-7','Cliente Agropecuario 16','3740389325',
'cliente16@correo.com','Direccion 16 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000017-8','Cliente Agropecuario 17','3168212356',
'cliente17@correo.com','Direccion 17 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000018-0','Cliente Agropecuario 18','3513140753',
'cliente18@correo.com','Direccion 18 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000019-1','Cliente Agropecuario 19','3509760584',
'cliente19@correo.com','Direccion 19 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000020-2','Cliente Agropecuario 20','3739830322',
'cliente20@correo.com','Direccion 20 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000021-3','Cliente Agropecuario 21','3602564736',
'cliente21@correo.com','Direccion 21 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000022-4','Cliente Agropecuario 22','3668132202',
'cliente22@correo.com','Direccion 22 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000023-5','Cliente Agropecuario 23','3369953851',
'cliente23@correo.com','Direccion 23 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000024-6','Cliente Agropecuario 24','3694021782',
'cliente24@correo.com','Direccion 24 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000025-7','Cliente Agropecuario 25','3112327652',
'cliente25@correo.com','Direccion 25 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000026-8','Cliente Agropecuario 26','3830448745',
'cliente26@correo.com','Direccion 26 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000027-0','Cliente Agropecuario 27','3873869166',
'cliente27@correo.com','Direccion 27 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000028-1','Cliente Agropecuario 28','3222998994',
'cliente28@correo.com','Direccion 28 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000029-2','Cliente Agropecuario 29','3831980933',
'cliente29@correo.com','Direccion 29 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000030-3','Cliente Agropecuario 30','3676567501',
'cliente30@correo.com','Direccion 30 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000031-4','Cliente Agropecuario 31','3906248900',
'cliente31@correo.com','Direccion 31 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000032-5','Cliente Agropecuario 32','3386501362',
'cliente32@correo.com','Direccion 32 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000033-6','Cliente Agropecuario 33','3925276600',
'cliente33@correo.com','Direccion 33 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000034-7','Cliente Agropecuario 34','3788227492',
'cliente34@correo.com','Direccion 34 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000035-8','Cliente Agropecuario 35','3465260635',
'cliente35@correo.com','Direccion 35 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000036-0','Cliente Agropecuario 36','3219778234',
'cliente36@correo.com','Direccion 36 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000037-1','Cliente Agropecuario 37','3415143362',
'cliente37@correo.com','Direccion 37 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000038-2','Cliente Agropecuario 38','3566825638',
'cliente38@correo.com','Direccion 38 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000039-3','Cliente Agropecuario 39','3269820594',
'cliente39@correo.com','Direccion 39 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000040-4','Cliente Agropecuario 40','3587182120',
'cliente40@correo.com','Direccion 40 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000041-5','Cliente Agropecuario 41','3103484630',
'cliente41@correo.com','Direccion 41 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000042-6','Cliente Agropecuario 42','3875340444',
'cliente42@correo.com','Direccion 42 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000043-7','Cliente Agropecuario 43','3872751234',
'cliente43@correo.com','Direccion 43 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000044-8','Cliente Agropecuario 44','3382811832',
'cliente44@correo.com','Direccion 44 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000045-0','Cliente Agropecuario 45','3637500247',
'cliente45@correo.com','Direccion 45 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000046-1','Cliente Agropecuario 46','3918150683',
'cliente46@correo.com','Direccion 46 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000047-2','Cliente Agropecuario 47','3291825997',
'cliente47@correo.com','Direccion 47 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000048-3','Cliente Agropecuario 48','3645119047',
'cliente48@correo.com','Direccion 48 Boyaca','VETERINARIA',1);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000049-4','Cliente Agropecuario 49','3214257751',
'cliente49@correo.com','Direccion 49 Boyaca','VETERINARIA',0);


INSERT INTO cliente (nit_cedula,nombre_cliente,telefono,email,direccion_entrega,tipo,estado_activo)
VALUES ('900000050-5','Cliente Agropecuario 50','3771410971',
'cliente50@correo.com','Direccion 50 Boyaca','VETERINARIA',0);


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (5,1,3,'2026-02-17 00:00:00',
'ENTRADA',59,'Reposicion de inventario lote 1');


INSERT INTO entrada
(id_stock,id_usuario,id_bodega,id_movimiento,id_proveedor,fecha_entrada,cantidad_ingresada,tipo_ingreso,numero_lote,observaciones)
VALUES (15,1,3,1,NULL,
'2026-02-17 00:00:00',59,
'Compra','LOTE-2026-001','Ingreso automatico');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (3,1,3,'2026-02-11 00:00:00',
'ENTRADA',116,'Reposicion de inventario lote 2');


INSERT INTO entrada
(id_stock,id_usuario,id_bodega,id_movimiento,id_proveedor,fecha_entrada,cantidad_ingresada,tipo_ingreso,numero_lote,observaciones)
VALUES (9,1,3,2,NULL,
'2026-02-11 00:00:00',116,
'Compra','LOTE-2026-002','Ingreso automatico');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (8,1,1,'2026-02-09 00:00:00',
'ENTRADA',86,'Reposicion de inventario lote 3');


INSERT INTO entrada
(id_stock,id_usuario,id_bodega,id_movimiento,id_proveedor,fecha_entrada,cantidad_ingresada,tipo_ingreso,numero_lote,observaciones)
VALUES (22,1,1,3,NULL,
'2026-02-09 00:00:00',86,
'Compra','LOTE-2026-003','Ingreso automatico');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (4,1,1,'2026-01-11 00:00:00',
'ENTRADA',112,'Reposicion de inventario lote 4');


INSERT INTO entrada
(id_stock,id_usuario,id_bodega,id_movimiento,id_proveedor,fecha_entrada,cantidad_ingresada,tipo_ingreso,numero_lote,observaciones)
VALUES (10,1,1,4,NULL,
'2026-01-11 00:00:00',112,
'Compra','LOTE-2026-004','Ingreso automatico');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (2,2,3,'2026-01-09 00:00:00',
'ENTRADA',144,'Reposicion de inventario lote 5');


INSERT INTO entrada
(id_stock,id_usuario,id_bodega,id_movimiento,id_proveedor,fecha_entrada,cantidad_ingresada,tipo_ingreso,numero_lote,observaciones)
VALUES (6,2,3,5,NULL,
'2026-01-09 00:00:00',144,
'Compra','LOTE-2026-005','Ingreso automatico');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (9,1,1,'2026-03-02 00:00:00',
'ENTRADA',124,'Reposicion de inventario lote 6');


INSERT INTO entrada
(id_stock,id_usuario,id_bodega,id_movimiento,id_proveedor,fecha_entrada,cantidad_ingresada,tipo_ingreso,numero_lote,observaciones)
VALUES (25,1,1,6,NULL,
'2026-03-02 00:00:00',124,
'Compra','LOTE-2026-006','Ingreso automatico');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (9,2,1,'2026-03-19 00:00:00',
'ENTRADA',107,'Reposicion de inventario lote 7');


INSERT INTO entrada
(id_stock,id_usuario,id_bodega,id_movimiento,id_proveedor,fecha_entrada,cantidad_ingresada,tipo_ingreso,numero_lote,observaciones)
VALUES (25,2,1,7,NULL,
'2026-03-19 00:00:00',107,
'Compra','LOTE-2026-007','Ingreso automatico');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (7,1,1,'2026-02-09 00:00:00',
'ENTRADA',131,'Reposicion de inventario lote 8');


INSERT INTO entrada
(id_stock,id_usuario,id_bodega,id_movimiento,id_proveedor,fecha_entrada,cantidad_ingresada,tipo_ingreso,numero_lote,observaciones)
VALUES (19,1,1,8,NULL,
'2026-02-09 00:00:00',131,
'Compra','LOTE-2026-008','Ingreso automatico');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (7,2,3,'2026-03-08 00:00:00',
'ENTRADA',96,'Reposicion de inventario lote 9');


INSERT INTO entrada
(id_stock,id_usuario,id_bodega,id_movimiento,id_proveedor,fecha_entrada,cantidad_ingresada,tipo_ingreso,numero_lote,observaciones)
VALUES (21,2,3,9,NULL,
'2026-03-08 00:00:00',96,
'Compra','LOTE-2026-009','Ingreso automatico');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (8,1,1,'2026-01-09 00:00:00',
'ENTRADA',68,'Reposicion de inventario lote 10');


INSERT INTO entrada
(id_stock,id_usuario,id_bodega,id_movimiento,id_proveedor,fecha_entrada,cantidad_ingresada,tipo_ingreso,numero_lote,observaciones)
VALUES (22,1,1,10,NULL,
'2026-01-09 00:00:00',68,
'Compra','LOTE-2026-010','Ingreso automatico');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (6,1,1,'2026-01-29 00:00:00',
'ENTRADA',115,'Reposicion de inventario lote 11');


INSERT INTO entrada
(id_stock,id_usuario,id_bodega,id_movimiento,id_proveedor,fecha_entrada,cantidad_ingresada,tipo_ingreso,numero_lote,observaciones)
VALUES (16,1,1,11,NULL,
'2026-01-29 00:00:00',115,
'Compra','LOTE-2026-011','Ingreso automatico');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (1,1,1,'2026-01-09 00:00:00',
'ENTRADA',69,'Reposicion de inventario lote 12');


INSERT INTO entrada
(id_stock,id_usuario,id_bodega,id_movimiento,id_proveedor,fecha_entrada,cantidad_ingresada,tipo_ingreso,numero_lote,observaciones)
VALUES (1,1,1,12,NULL,
'2026-01-09 00:00:00',69,
'Compra','LOTE-2026-012','Ingreso automatico');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (1,1,2,'2026-01-31 00:00:00',
'ENTRADA',105,'Reposicion de inventario lote 13');


INSERT INTO entrada
(id_stock,id_usuario,id_bodega,id_movimiento,id_proveedor,fecha_entrada,cantidad_ingresada,tipo_ingreso,numero_lote,observaciones)
VALUES (2,1,2,13,NULL,
'2026-01-31 00:00:00',105,
'Compra','LOTE-2026-013','Ingreso automatico');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (5,2,3,'2026-03-11 00:00:00',
'ENTRADA',67,'Reposicion de inventario lote 14');


INSERT INTO entrada
(id_stock,id_usuario,id_bodega,id_movimiento,id_proveedor,fecha_entrada,cantidad_ingresada,tipo_ingreso,numero_lote,observaciones)
VALUES (15,2,3,14,NULL,
'2026-03-11 00:00:00',67,
'Compra','LOTE-2026-014','Ingreso automatico');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (3,2,3,'2026-03-02 00:00:00',
'ENTRADA',71,'Reposicion de inventario lote 15');


INSERT INTO entrada
(id_stock,id_usuario,id_bodega,id_movimiento,id_proveedor,fecha_entrada,cantidad_ingresada,tipo_ingreso,numero_lote,observaciones)
VALUES (9,2,3,15,NULL,
'2026-03-02 00:00:00',71,
'Compra','LOTE-2026-015','Ingreso automatico');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (7,1,1,'2026-03-26 00:00:00',
'ENTRADA',52,'Reposicion de inventario lote 16');


INSERT INTO entrada
(id_stock,id_usuario,id_bodega,id_movimiento,id_proveedor,fecha_entrada,cantidad_ingresada,tipo_ingreso,numero_lote,observaciones)
VALUES (19,1,1,16,NULL,
'2026-03-26 00:00:00',52,
'Compra','LOTE-2026-016','Ingreso automatico');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (7,2,2,'2026-03-01 00:00:00',
'ENTRADA',92,'Reposicion de inventario lote 17');


INSERT INTO entrada
(id_stock,id_usuario,id_bodega,id_movimiento,id_proveedor,fecha_entrada,cantidad_ingresada,tipo_ingreso,numero_lote,observaciones)
VALUES (20,2,2,17,NULL,
'2026-03-01 00:00:00',92,
'Compra','LOTE-2026-017','Ingreso automatico');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (12,1,1,'2026-02-21 00:00:00',
'ENTRADA',47,'Reposicion de inventario lote 18');


INSERT INTO entrada
(id_stock,id_usuario,id_bodega,id_movimiento,id_proveedor,fecha_entrada,cantidad_ingresada,tipo_ingreso,numero_lote,observaciones)
VALUES (34,1,1,18,NULL,
'2026-02-21 00:00:00',47,
'Compra','LOTE-2026-018','Ingreso automatico');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (12,1,2,'2026-01-25 00:00:00',
'ENTRADA',71,'Reposicion de inventario lote 19');


INSERT INTO entrada
(id_stock,id_usuario,id_bodega,id_movimiento,id_proveedor,fecha_entrada,cantidad_ingresada,tipo_ingreso,numero_lote,observaciones)
VALUES (35,1,2,19,NULL,
'2026-01-25 00:00:00',71,
'Compra','LOTE-2026-019','Ingreso automatico');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (4,2,3,'2026-02-24 00:00:00',
'ENTRADA',57,'Reposicion de inventario lote 20');


INSERT INTO entrada
(id_stock,id_usuario,id_bodega,id_movimiento,id_proveedor,fecha_entrada,cantidad_ingresada,tipo_ingreso,numero_lote,observaciones)
VALUES (12,2,3,20,NULL,
'2026-02-24 00:00:00',57,
'Compra','LOTE-2026-020','Ingreso automatico');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (3,2,2,'2026-01-10 00:00:00',
'ENTRADA',71,'Reposicion de inventario lote 21');


INSERT INTO entrada
(id_stock,id_usuario,id_bodega,id_movimiento,id_proveedor,fecha_entrada,cantidad_ingresada,tipo_ingreso,numero_lote,observaciones)
VALUES (8,2,2,21,NULL,
'2026-01-10 00:00:00',71,
'Compra','LOTE-2026-021','Ingreso automatico');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (8,1,3,'2026-03-25 00:00:00',
'ENTRADA',46,'Reposicion de inventario lote 22');


INSERT INTO entrada
(id_stock,id_usuario,id_bodega,id_movimiento,id_proveedor,fecha_entrada,cantidad_ingresada,tipo_ingreso,numero_lote,observaciones)
VALUES (24,1,3,22,NULL,
'2026-03-25 00:00:00',46,
'Compra','LOTE-2026-022','Ingreso automatico');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (9,1,1,'2026-01-31 00:00:00',
'ENTRADA',136,'Reposicion de inventario lote 23');


INSERT INTO entrada
(id_stock,id_usuario,id_bodega,id_movimiento,id_proveedor,fecha_entrada,cantidad_ingresada,tipo_ingreso,numero_lote,observaciones)
VALUES (25,1,1,23,NULL,
'2026-01-31 00:00:00',136,
'Compra','LOTE-2026-023','Ingreso automatico');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (3,2,2,'2026-01-28 00:00:00',
'ENTRADA',101,'Reposicion de inventario lote 24');


INSERT INTO entrada
(id_stock,id_usuario,id_bodega,id_movimiento,id_proveedor,fecha_entrada,cantidad_ingresada,tipo_ingreso,numero_lote,observaciones)
VALUES (8,2,2,24,NULL,
'2026-01-28 00:00:00',101,
'Compra','LOTE-2026-024','Ingreso automatico');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (7,1,1,'2026-01-01 00:00:00',
'ENTRADA',88,'Reposicion de inventario lote 25');


INSERT INTO entrada
(id_stock,id_usuario,id_bodega,id_movimiento,id_proveedor,fecha_entrada,cantidad_ingresada,tipo_ingreso,numero_lote,observaciones)
VALUES (19,1,1,25,NULL,
'2026-01-01 00:00:00',88,
'Compra','LOTE-2026-025','Ingreso automatico');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (7,2,2,'2026-02-24 00:00:00',
'ENTRADA',76,'Reposicion de inventario lote 26');


INSERT INTO entrada
(id_stock,id_usuario,id_bodega,id_movimiento,id_proveedor,fecha_entrada,cantidad_ingresada,tipo_ingreso,numero_lote,observaciones)
VALUES (20,2,2,26,NULL,
'2026-02-24 00:00:00',76,
'Compra','LOTE-2026-026','Ingreso automatico');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (12,2,3,'2026-01-25 00:00:00',
'ENTRADA',59,'Reposicion de inventario lote 27');


INSERT INTO entrada
(id_stock,id_usuario,id_bodega,id_movimiento,id_proveedor,fecha_entrada,cantidad_ingresada,tipo_ingreso,numero_lote,observaciones)
VALUES (36,2,3,27,NULL,
'2026-01-25 00:00:00',59,
'Compra','LOTE-2026-027','Ingreso automatico');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (5,1,1,'2026-03-11 00:00:00',
'ENTRADA',114,'Reposicion de inventario lote 28');


INSERT INTO entrada
(id_stock,id_usuario,id_bodega,id_movimiento,id_proveedor,fecha_entrada,cantidad_ingresada,tipo_ingreso,numero_lote,observaciones)
VALUES (13,1,1,28,NULL,
'2026-03-11 00:00:00',114,
'Compra','LOTE-2026-028','Ingreso automatico');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (1,2,3,'2026-01-07 00:00:00',
'ENTRADA',47,'Reposicion de inventario lote 29');


INSERT INTO entrada
(id_stock,id_usuario,id_bodega,id_movimiento,id_proveedor,fecha_entrada,cantidad_ingresada,tipo_ingreso,numero_lote,observaciones)
VALUES (3,2,3,29,NULL,
'2026-01-07 00:00:00',47,
'Compra','LOTE-2026-029','Ingreso automatico');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (10,1,2,'2026-03-07 00:00:00',
'ENTRADA',47,'Reposicion de inventario lote 30');


INSERT INTO entrada
(id_stock,id_usuario,id_bodega,id_movimiento,id_proveedor,fecha_entrada,cantidad_ingresada,tipo_ingreso,numero_lote,observaciones)
VALUES (29,1,2,30,NULL,
'2026-03-07 00:00:00',47,
'Compra','LOTE-2026-030','Ingreso automatico');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (2,7,1,'2026-03-28 00:00:00',
'SALIDA',7,'Venta comercial #1');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (39,7,4,31,
'2026-03-28 00:00:00',7,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (4,10,2,'2026-03-16 00:00:00',
'SALIDA',12,'Venta comercial #2');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (37,10,11,32,
'2026-03-16 00:00:00',12,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (10,42,1,'2026-03-26 00:00:00',
'SALIDA',18,'Venta comercial #3');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (6,42,28,33,
'2026-03-26 00:00:00',18,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (10,36,3,'2026-01-27 00:00:00',
'SALIDA',13,'Venta comercial #4');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (21,36,30,34,
'2026-01-27 00:00:00',13,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (11,23,3,'2026-02-20 00:00:00',
'SALIDA',13,'Venta comercial #5');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (16,23,33,35,
'2026-02-20 00:00:00',13,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (3,44,3,'2026-02-10 00:00:00',
'SALIDA',19,'Venta comercial #6');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (20,44,9,36,
'2026-02-10 00:00:00',19,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (2,32,1,'2026-01-13 00:00:00',
'SALIDA',23,'Venta comercial #7');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (40,32,4,37,
'2026-01-13 00:00:00',23,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (2,16,3,'2026-01-17 00:00:00',
'SALIDA',13,'Venta comercial #8');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (33,16,6,38,
'2026-01-17 00:00:00',13,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (6,18,1,'2026-01-21 00:00:00',
'SALIDA',14,'Venta comercial #9');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (24,18,16,39,
'2026-01-21 00:00:00',14,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (8,48,3,'2026-04-14 00:00:00',
'SALIDA',24,'Venta comercial #10');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (20,48,24,40,
'2026-04-14 00:00:00',24,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (11,3,3,'2026-02-08 00:00:00',
'SALIDA',22,'Venta comercial #11');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (43,3,33,41,
'2026-02-08 00:00:00',22,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (11,11,1,'2026-04-24 00:00:00',
'SALIDA',8,'Venta comercial #12');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (17,11,31,42,
'2026-04-24 00:00:00',8,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (2,38,3,'2026-02-06 00:00:00',
'SALIDA',13,'Venta comercial #13');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (10,38,6,43,
'2026-02-06 00:00:00',13,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (10,48,1,'2026-03-29 00:00:00',
'SALIDA',11,'Venta comercial #14');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (22,48,28,44,
'2026-03-29 00:00:00',11,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (11,35,2,'2026-04-26 00:00:00',
'SALIDA',13,'Venta comercial #15');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (32,35,32,45,
'2026-04-26 00:00:00',13,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (1,43,1,'2026-01-06 00:00:00',
'SALIDA',13,'Venta comercial #16');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (28,43,1,46,
'2026-01-06 00:00:00',13,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (1,52,2,'2026-02-03 00:00:00',
'SALIDA',25,'Venta comercial #17');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (9,52,2,47,
'2026-02-03 00:00:00',25,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (3,31,3,'2026-02-24 00:00:00',
'SALIDA',27,'Venta comercial #18');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (36,31,9,48,
'2026-02-24 00:00:00',27,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (9,10,1,'2026-04-26 00:00:00',
'SALIDA',27,'Venta comercial #19');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (5,10,25,49,
'2026-04-26 00:00:00',27,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (3,5,3,'2026-03-12 00:00:00',
'SALIDA',23,'Venta comercial #20');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (24,5,9,50,
'2026-03-12 00:00:00',23,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (3,11,2,'2026-02-16 00:00:00',
'SALIDA',14,'Venta comercial #21');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (3,11,8,51,
'2026-02-16 00:00:00',14,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (1,16,2,'2026-03-27 00:00:00',
'SALIDA',12,'Venta comercial #22');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (44,16,2,52,
'2026-03-27 00:00:00',12,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (2,52,2,'2026-03-21 00:00:00',
'SALIDA',18,'Venta comercial #23');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (36,52,5,53,
'2026-03-21 00:00:00',18,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (12,18,1,'2026-04-14 00:00:00',
'SALIDA',30,'Venta comercial #24');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (11,18,34,54,
'2026-04-14 00:00:00',30,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (3,4,2,'2026-04-29 00:00:00',
'SALIDA',28,'Venta comercial #25');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (12,4,8,55,
'2026-04-29 00:00:00',28,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (6,45,2,'2026-02-01 00:00:00',
'SALIDA',30,'Venta comercial #26');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (48,45,17,56,
'2026-02-01 00:00:00',30,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (5,47,1,'2026-04-22 00:00:00',
'SALIDA',17,'Venta comercial #27');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (7,47,13,57,
'2026-04-22 00:00:00',17,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (1,17,2,'2026-02-14 00:00:00',
'SALIDA',19,'Venta comercial #28');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (13,17,2,58,
'2026-02-14 00:00:00',19,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (5,17,1,'2026-01-25 00:00:00',
'SALIDA',26,'Venta comercial #29');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (2,17,13,59,
'2026-01-25 00:00:00',26,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (7,20,2,'2026-02-05 00:00:00',
'SALIDA',29,'Venta comercial #30');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (5,20,20,60,
'2026-02-05 00:00:00',29,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (6,35,3,'2026-04-18 00:00:00',
'SALIDA',26,'Venta comercial #31');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (26,35,18,61,
'2026-04-18 00:00:00',26,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (9,4,2,'2026-01-23 00:00:00',
'SALIDA',13,'Venta comercial #32');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (8,4,26,62,
'2026-01-23 00:00:00',13,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (10,5,2,'2026-02-25 00:00:00',
'SALIDA',24,'Venta comercial #33');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (7,5,29,63,
'2026-02-25 00:00:00',24,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (6,23,3,'2026-03-07 00:00:00',
'SALIDA',24,'Venta comercial #34');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (28,23,18,64,
'2026-03-07 00:00:00',24,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (2,39,2,'2026-01-06 00:00:00',
'SALIDA',13,'Venta comercial #35');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (13,39,5,65,
'2026-01-06 00:00:00',13,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (12,3,2,'2026-03-10 00:00:00',
'SALIDA',30,'Venta comercial #36');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (34,3,35,66,
'2026-03-10 00:00:00',30,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (11,50,3,'2026-01-26 00:00:00',
'SALIDA',26,'Venta comercial #37');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (48,50,33,67,
'2026-01-26 00:00:00',26,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (6,7,2,'2026-03-21 00:00:00',
'SALIDA',15,'Venta comercial #38');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (43,7,17,68,
'2026-03-21 00:00:00',15,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (6,10,3,'2026-03-06 00:00:00',
'SALIDA',14,'Venta comercial #39');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (47,10,18,69,
'2026-03-06 00:00:00',14,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (5,29,3,'2026-03-31 00:00:00',
'SALIDA',17,'Venta comercial #40');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (21,29,15,70,
'2026-03-31 00:00:00',17,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (5,11,3,'2026-03-27 00:00:00',
'SALIDA',18,'Venta comercial #41');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (13,11,15,71,
'2026-03-27 00:00:00',18,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (7,50,3,'2026-03-14 00:00:00',
'SALIDA',24,'Venta comercial #42');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (12,50,21,72,
'2026-03-14 00:00:00',24,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (5,38,2,'2026-02-06 00:00:00',
'SALIDA',14,'Venta comercial #43');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (1,38,14,73,
'2026-02-06 00:00:00',14,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (4,40,2,'2026-02-11 00:00:00',
'SALIDA',25,'Venta comercial #44');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (39,40,11,74,
'2026-02-11 00:00:00',25,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (8,31,2,'2026-03-07 00:00:00',
'SALIDA',11,'Venta comercial #45');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (44,31,23,75,
'2026-03-07 00:00:00',11,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (8,13,3,'2026-02-06 00:00:00',
'SALIDA',7,'Venta comercial #46');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (43,13,24,76,
'2026-02-06 00:00:00',7,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (9,43,3,'2026-01-12 00:00:00',
'SALIDA',15,'Venta comercial #47');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (40,43,27,77,
'2026-01-12 00:00:00',15,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (4,22,3,'2026-01-26 00:00:00',
'SALIDA',30,'Venta comercial #48');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (15,22,12,78,
'2026-01-26 00:00:00',30,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (3,5,1,'2026-03-20 00:00:00',
'SALIDA',20,'Venta comercial #49');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (16,5,7,79,
'2026-03-20 00:00:00',20,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (2,29,2,'2026-01-25 00:00:00',
'SALIDA',23,'Venta comercial #50');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (41,29,5,80,
'2026-01-25 00:00:00',23,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (12,27,3,'2026-02-01 00:00:00',
'SALIDA',17,'Venta comercial #51');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (32,27,36,81,
'2026-02-01 00:00:00',17,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (3,47,3,'2026-04-21 00:00:00',
'SALIDA',29,'Venta comercial #52');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (1,47,9,82,
'2026-04-21 00:00:00',29,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (2,17,2,'2026-03-31 00:00:00',
'SALIDA',30,'Venta comercial #53');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (12,17,5,83,
'2026-03-31 00:00:00',30,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (9,6,2,'2026-04-28 00:00:00',
'SALIDA',12,'Venta comercial #54');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (36,6,26,84,
'2026-04-28 00:00:00',12,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (2,11,2,'2026-03-09 00:00:00',
'SALIDA',26,'Venta comercial #55');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (30,11,5,85,
'2026-03-09 00:00:00',26,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (9,23,3,'2026-03-20 00:00:00',
'SALIDA',19,'Venta comercial #56');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (49,23,27,86,
'2026-03-20 00:00:00',19,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (12,30,3,'2026-04-25 00:00:00',
'SALIDA',19,'Venta comercial #57');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (36,30,36,87,
'2026-04-25 00:00:00',19,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (3,33,3,'2026-04-07 00:00:00',
'SALIDA',13,'Venta comercial #58');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (29,33,9,88,
'2026-04-07 00:00:00',13,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (4,20,3,'2026-03-08 00:00:00',
'SALIDA',29,'Venta comercial #59');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (50,20,12,89,
'2026-03-08 00:00:00',29,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (8,18,3,'2026-01-10 00:00:00',
'SALIDA',19,'Venta comercial #60');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (18,18,24,90,
'2026-01-10 00:00:00',19,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (12,18,2,'2026-02-10 00:00:00',
'SALIDA',15,'Venta comercial #61');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (18,18,35,91,
'2026-02-10 00:00:00',15,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (9,11,1,'2026-02-19 00:00:00',
'SALIDA',12,'Venta comercial #62');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (10,11,25,92,
'2026-02-19 00:00:00',12,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (12,48,1,'2026-02-23 00:00:00',
'SALIDA',7,'Venta comercial #63');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (14,48,34,93,
'2026-02-23 00:00:00',7,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (7,37,2,'2026-01-08 00:00:00',
'SALIDA',18,'Venta comercial #64');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (30,37,20,94,
'2026-01-08 00:00:00',18,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (4,27,2,'2026-03-31 00:00:00',
'SALIDA',23,'Venta comercial #65');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (50,27,11,95,
'2026-03-31 00:00:00',23,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (1,27,3,'2026-05-01 00:00:00',
'SALIDA',5,'Venta comercial #66');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (31,27,3,96,
'2026-05-01 00:00:00',5,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (6,51,2,'2026-03-10 00:00:00',
'SALIDA',18,'Venta comercial #67');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (25,51,17,97,
'2026-03-10 00:00:00',18,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (12,37,3,'2026-03-04 00:00:00',
'SALIDA',12,'Venta comercial #68');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (39,37,36,98,
'2026-03-04 00:00:00',12,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (4,30,2,'2026-02-19 00:00:00',
'SALIDA',5,'Venta comercial #69');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (32,30,11,99,
'2026-02-19 00:00:00',5,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (6,46,3,'2026-01-22 00:00:00',
'SALIDA',28,'Venta comercial #70');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (26,46,18,100,
'2026-01-22 00:00:00',28,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (8,42,1,'2026-04-27 00:00:00',
'SALIDA',5,'Venta comercial #71');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (35,42,22,101,
'2026-04-27 00:00:00',5,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (7,39,3,'2026-01-11 00:00:00',
'SALIDA',5,'Venta comercial #72');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (43,39,21,102,
'2026-01-11 00:00:00',5,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (11,11,2,'2026-01-07 00:00:00',
'SALIDA',10,'Venta comercial #73');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (30,11,32,103,
'2026-01-07 00:00:00',10,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (5,23,2,'2026-02-11 00:00:00',
'SALIDA',19,'Venta comercial #74');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (14,23,14,104,
'2026-02-11 00:00:00',19,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (6,20,2,'2026-02-02 00:00:00',
'SALIDA',18,'Venta comercial #75');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (49,20,17,105,
'2026-02-02 00:00:00',18,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (2,4,2,'2026-01-07 00:00:00',
'SALIDA',22,'Venta comercial #76');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (48,4,5,106,
'2026-01-07 00:00:00',22,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (6,44,1,'2026-03-25 00:00:00',
'SALIDA',29,'Venta comercial #77');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (5,44,16,107,
'2026-03-25 00:00:00',29,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (1,18,1,'2026-03-21 00:00:00',
'SALIDA',5,'Venta comercial #78');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (13,18,1,108,
'2026-03-21 00:00:00',5,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (3,11,1,'2026-01-15 00:00:00',
'SALIDA',26,'Venta comercial #79');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (31,11,7,109,
'2026-01-15 00:00:00',26,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (10,32,1,'2026-04-09 00:00:00',
'SALIDA',13,'Venta comercial #80');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (45,32,28,110,
'2026-04-09 00:00:00',13,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (6,41,1,'2026-04-02 00:00:00',
'SALIDA',28,'Venta comercial #81');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (39,41,16,111,
'2026-04-02 00:00:00',28,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (2,22,1,'2026-01-04 00:00:00',
'SALIDA',23,'Venta comercial #82');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (7,22,4,112,
'2026-01-04 00:00:00',23,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (5,46,3,'2026-05-01 00:00:00',
'SALIDA',17,'Venta comercial #83');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (25,46,15,113,
'2026-05-01 00:00:00',17,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (12,7,1,'2026-04-17 00:00:00',
'SALIDA',27,'Venta comercial #84');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (38,7,34,114,
'2026-04-17 00:00:00',27,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (11,9,1,'2026-02-08 00:00:00',
'SALIDA',29,'Venta comercial #85');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (45,9,31,115,
'2026-02-08 00:00:00',29,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (11,10,3,'2026-01-06 00:00:00',
'SALIDA',30,'Venta comercial #86');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (37,10,33,116,
'2026-01-06 00:00:00',30,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (6,30,3,'2026-01-09 00:00:00',
'SALIDA',16,'Venta comercial #87');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (43,30,18,117,
'2026-01-09 00:00:00',16,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (9,24,3,'2026-04-16 00:00:00',
'SALIDA',18,'Venta comercial #88');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (1,24,27,118,
'2026-04-16 00:00:00',18,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (8,30,1,'2026-04-25 00:00:00',
'SALIDA',25,'Venta comercial #89');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (24,30,22,119,
'2026-04-25 00:00:00',25,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (8,12,3,'2026-04-04 00:00:00',
'SALIDA',10,'Venta comercial #90');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (28,12,24,120,
'2026-04-04 00:00:00',10,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (9,20,3,'2026-04-28 00:00:00',
'SALIDA',30,'Venta comercial #91');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (40,20,27,121,
'2026-04-28 00:00:00',30,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (9,32,2,'2026-03-17 00:00:00',
'SALIDA',28,'Venta comercial #92');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (28,32,26,122,
'2026-03-17 00:00:00',28,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (5,18,2,'2026-04-23 00:00:00',
'SALIDA',13,'Venta comercial #93');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (6,18,14,123,
'2026-04-23 00:00:00',13,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (8,51,1,'2026-03-20 00:00:00',
'SALIDA',23,'Venta comercial #94');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (30,51,22,124,
'2026-03-20 00:00:00',23,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (11,24,2,'2026-04-19 00:00:00',
'SALIDA',20,'Venta comercial #95');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (2,24,32,125,
'2026-04-19 00:00:00',20,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (6,34,1,'2026-04-13 00:00:00',
'SALIDA',16,'Venta comercial #96');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (14,34,16,126,
'2026-04-13 00:00:00',16,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (5,20,2,'2026-04-23 00:00:00',
'SALIDA',27,'Venta comercial #97');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (39,20,14,127,
'2026-04-23 00:00:00',27,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (5,3,3,'2026-01-11 00:00:00',
'SALIDA',11,'Venta comercial #98');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (34,3,15,128,
'2026-01-11 00:00:00',11,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (4,29,3,'2026-04-08 00:00:00',
'SALIDA',22,'Venta comercial #99');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (32,29,12,129,
'2026-04-08 00:00:00',22,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (4,33,3,'2026-03-04 00:00:00',
'SALIDA',27,'Venta comercial #100');


INSERT INTO salida
(id_cliente,id_usuario,id_stock,id_movimiento,fecha_salida,cantidad_salida,destino_bodega,tipo_mov_salida,motivo_salida,observaciones)
VALUES (42,33,12,130,
'2026-03-04 00:00:00',27,
'Sede cliente','VENTA','Venta regular','Despacho exitoso');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (8,1,1,'2026-01-29 00:00:00',
'AJUSTE',5,'Ajuste por auditoria');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (7,1,3,'2026-03-26 00:00:00',
'AJUSTE',5,'Ajuste por auditoria');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (10,2,2,'2026-03-09 00:00:00',
'AJUSTE',9,'Ajuste por auditoria');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (6,2,2,'2026-03-31 00:00:00',
'AJUSTE',6,'Ajuste por auditoria');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (8,2,2,'2026-01-30 00:00:00',
'AJUSTE',5,'Ajuste por auditoria');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (2,1,3,'2026-01-16 00:00:00',
'AJUSTE',6,'Ajuste por auditoria');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (12,1,3,'2026-01-28 00:00:00',
'AJUSTE',4,'Ajuste por auditoria');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (12,2,2,'2026-04-08 00:00:00',
'AJUSTE',10,'Ajuste por auditoria');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (9,2,3,'2026-04-17 00:00:00',
'AJUSTE',2,'Ajuste por auditoria');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (4,1,2,'2026-01-23 00:00:00',
'AJUSTE',6,'Ajuste por auditoria');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (5,1,1,'2026-01-06 00:00:00',
'AJUSTE',5,'Ajuste por auditoria');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (1,2,3,'2026-03-23 00:00:00',
'AJUSTE',3,'Ajuste por auditoria');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (8,1,1,'2026-02-06 00:00:00',
'AJUSTE',10,'Ajuste por auditoria');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (8,2,2,'2026-01-24 00:00:00',
'AJUSTE',6,'Ajuste por auditoria');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (1,2,2,'2026-04-16 00:00:00',
'AJUSTE',2,'Ajuste por auditoria');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (2,2,2,'2026-03-15 00:00:00',
'AJUSTE',2,'Ajuste por auditoria');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (11,1,3,'2026-01-20 00:00:00',
'AJUSTE',3,'Ajuste por auditoria');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (10,1,2,'2026-01-16 00:00:00',
'AJUSTE',4,'Ajuste por auditoria');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (9,1,2,'2026-02-18 00:00:00',
'AJUSTE',9,'Ajuste por auditoria');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (8,2,2,'2026-02-24 00:00:00',
'AJUSTE',10,'Ajuste por auditoria');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (5,6,3,'2026-02-13 00:00:00',
'DEVOLUCION',5,'Devolucion cliente');


INSERT INTO devolucion
(id_stock,id_movimiento_relacionado,id_bodega,id_cliente,id_usuario,fecha_devolucion,
cantidad_devuelta,motivo_devolucion,estado_producto,genera_entrada,observaciones)
VALUES (15,128,3,40,6,
'2026-02-13 00:00:00',5,
'Empaque defectuoso','PARCIAL',1,'Reingreso parcial');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (4,19,3,'2026-02-21 00:00:00',
'DEVOLUCION',1,'Devolucion cliente');


INSERT INTO devolucion
(id_stock,id_movimiento_relacionado,id_bodega,id_cliente,id_usuario,fecha_devolucion,
cantidad_devuelta,motivo_devolucion,estado_producto,genera_entrada,observaciones)
VALUES (12,61,3,14,19,
'2026-02-21 00:00:00',1,
'Empaque defectuoso','PARCIAL',1,'Reingreso parcial');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (3,13,3,'2026-03-25 00:00:00',
'DEVOLUCION',1,'Devolucion cliente');


INSERT INTO devolucion
(id_stock,id_movimiento_relacionado,id_bodega,id_cliente,id_usuario,fecha_devolucion,
cantidad_devuelta,motivo_devolucion,estado_producto,genera_entrada,observaciones)
VALUES (9,88,3,5,13,
'2026-03-25 00:00:00',1,
'Empaque defectuoso','PARCIAL',1,'Reingreso parcial');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (12,21,3,'2026-03-02 00:00:00',
'DEVOLUCION',1,'Devolucion cliente');


INSERT INTO devolucion
(id_stock,id_movimiento_relacionado,id_bodega,id_cliente,id_usuario,fecha_devolucion,
cantidad_devuelta,motivo_devolucion,estado_producto,genera_entrada,observaciones)
VALUES (36,67,3,31,21,
'2026-03-02 00:00:00',1,
'Empaque defectuoso','PARCIAL',1,'Reingreso parcial');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (12,32,2,'2026-04-29 00:00:00',
'DEVOLUCION',1,'Devolucion cliente');


INSERT INTO devolucion
(id_stock,id_movimiento_relacionado,id_bodega,id_cliente,id_usuario,fecha_devolucion,
cantidad_devuelta,motivo_devolucion,estado_producto,genera_entrada,observaciones)
VALUES (35,60,2,45,32,
'2026-04-29 00:00:00',1,
'Empaque defectuoso','PARCIAL',1,'Reingreso parcial');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (5,45,3,'2026-03-27 00:00:00',
'DEVOLUCION',2,'Devolucion cliente');


INSERT INTO devolucion
(id_stock,id_movimiento_relacionado,id_bodega,id_cliente,id_usuario,fecha_devolucion,
cantidad_devuelta,motivo_devolucion,estado_producto,genera_entrada,observaciones)
VALUES (15,45,3,38,45,
'2026-03-27 00:00:00',2,
'Empaque defectuoso','PARCIAL',1,'Reingreso parcial');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (9,12,1,'2026-02-19 00:00:00',
'DEVOLUCION',3,'Devolucion cliente');


INSERT INTO devolucion
(id_stock,id_movimiento_relacionado,id_bodega,id_cliente,id_usuario,fecha_devolucion,
cantidad_devuelta,motivo_devolucion,estado_producto,genera_entrada,observaciones)
VALUES (25,40,1,42,12,
'2026-02-19 00:00:00',3,
'Empaque defectuoso','PARCIAL',1,'Reingreso parcial');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (1,41,1,'2026-03-09 00:00:00',
'DEVOLUCION',5,'Devolucion cliente');


INSERT INTO devolucion
(id_stock,id_movimiento_relacionado,id_bodega,id_cliente,id_usuario,fecha_devolucion,
cantidad_devuelta,motivo_devolucion,estado_producto,genera_entrada,observaciones)
VALUES (1,87,1,20,41,
'2026-03-09 00:00:00',5,
'Empaque defectuoso','PARCIAL',1,'Reingreso parcial');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (2,22,2,'2026-03-07 00:00:00',
'DEVOLUCION',4,'Devolucion cliente');


INSERT INTO devolucion
(id_stock,id_movimiento_relacionado,id_bodega,id_cliente,id_usuario,fecha_devolucion,
cantidad_devuelta,motivo_devolucion,estado_producto,genera_entrada,observaciones)
VALUES (5,95,2,45,22,
'2026-03-07 00:00:00',4,
'Empaque defectuoso','PARCIAL',1,'Reingreso parcial');


INSERT INTO movimiento_inventario
(id_producto,id_usuario,id_bodega,fecha_movimiento,tipo_movimiento,cantidad_bultos,observaciones)
VALUES (9,8,2,'2026-02-06 00:00:00',
'DEVOLUCION',5,'Devolucion cliente');


INSERT INTO devolucion
(id_stock,id_movimiento_relacionado,id_bodega,id_cliente,id_usuario,fecha_devolucion,
cantidad_devuelta,motivo_devolucion,estado_producto,genera_entrada,observaciones)
VALUES (26,86,2,29,8,
'2026-02-06 00:00:00',5,
'Empaque defectuoso','PARCIAL',1,'Reingreso parcial');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-01 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 1');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-05-01 00:00:00',
'2026-01-01 / 2026-04-30',
'STOCK',
'Reporte asociado al movimiento 2');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-25 00:00:00',
'2026-01-01 / 2026-04-30',
'PERDIDAS',
'Reporte asociado al movimiento 3');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-25 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 4');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-17 00:00:00',
'2026-01-01 / 2026-04-30',
'SALIDAS',
'Reporte asociado al movimiento 5');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-06 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 6');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-21 00:00:00',
'2026-01-01 / 2026-04-30',
'PERDIDAS',
'Reporte asociado al movimiento 7');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-16 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 8');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-11 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 9');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-28 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 10');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-14 00:00:00',
'2026-01-01 / 2026-04-30',
'SALIDAS',
'Reporte asociado al movimiento 11');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-22 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 12');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-15 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 13');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-09 00:00:00',
'2026-01-01 / 2026-04-30',
'STOCK',
'Reporte asociado al movimiento 14');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-25 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 15');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-22 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 16');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-14 00:00:00',
'2026-01-01 / 2026-04-30',
'PERDIDAS',
'Reporte asociado al movimiento 17');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-17 00:00:00',
'2026-01-01 / 2026-04-30',
'STOCK',
'Reporte asociado al movimiento 18');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-21 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 19');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-07 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 20');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-30 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 21');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-29 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 22');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-01 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 23');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-23 00:00:00',
'2026-01-01 / 2026-04-30',
'PERDIDAS',
'Reporte asociado al movimiento 24');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-18 00:00:00',
'2026-01-01 / 2026-04-30',
'SALIDAS',
'Reporte asociado al movimiento 25');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-03 00:00:00',
'2026-01-01 / 2026-04-30',
'STOCK',
'Reporte asociado al movimiento 26');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-15 00:00:00',
'2026-01-01 / 2026-04-30',
'SALIDAS',
'Reporte asociado al movimiento 27');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-16 00:00:00',
'2026-01-01 / 2026-04-30',
'STOCK',
'Reporte asociado al movimiento 28');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-14 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 29');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-08 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 30');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-13 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 31');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-28 00:00:00',
'2026-01-01 / 2026-04-30',
'SALIDAS',
'Reporte asociado al movimiento 32');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-25 00:00:00',
'2026-01-01 / 2026-04-30',
'STOCK',
'Reporte asociado al movimiento 33');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-30 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 34');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-27 00:00:00',
'2026-01-01 / 2026-04-30',
'PERDIDAS',
'Reporte asociado al movimiento 35');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-24 00:00:00',
'2026-01-01 / 2026-04-30',
'STOCK',
'Reporte asociado al movimiento 36');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-28 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 37');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-18 00:00:00',
'2026-01-01 / 2026-04-30',
'SALIDAS',
'Reporte asociado al movimiento 38');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-11 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 39');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-15 00:00:00',
'2026-01-01 / 2026-04-30',
'PERDIDAS',
'Reporte asociado al movimiento 40');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-23 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 41');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-08 00:00:00',
'2026-01-01 / 2026-04-30',
'SALIDAS',
'Reporte asociado al movimiento 42');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-11 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 43');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-13 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 44');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-05-01 00:00:00',
'2026-01-01 / 2026-04-30',
'SALIDAS',
'Reporte asociado al movimiento 45');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-17 00:00:00',
'2026-01-01 / 2026-04-30',
'STOCK',
'Reporte asociado al movimiento 46');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-28 00:00:00',
'2026-01-01 / 2026-04-30',
'PERDIDAS',
'Reporte asociado al movimiento 47');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-04 00:00:00',
'2026-01-01 / 2026-04-30',
'STOCK',
'Reporte asociado al movimiento 48');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-01 00:00:00',
'2026-01-01 / 2026-04-30',
'PERDIDAS',
'Reporte asociado al movimiento 49');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-28 00:00:00',
'2026-01-01 / 2026-04-30',
'SALIDAS',
'Reporte asociado al movimiento 50');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-16 00:00:00',
'2026-01-01 / 2026-04-30',
'SALIDAS',
'Reporte asociado al movimiento 51');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-20 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 52');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-28 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 53');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-05-01 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 54');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-28 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 55');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-20 00:00:00',
'2026-01-01 / 2026-04-30',
'PERDIDAS',
'Reporte asociado al movimiento 56');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-21 00:00:00',
'2026-01-01 / 2026-04-30',
'STOCK',
'Reporte asociado al movimiento 57');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-24 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 58');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-04 00:00:00',
'2026-01-01 / 2026-04-30',
'STOCK',
'Reporte asociado al movimiento 59');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-06 00:00:00',
'2026-01-01 / 2026-04-30',
'STOCK',
'Reporte asociado al movimiento 60');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-02 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 61');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-10 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 62');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-14 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 63');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-17 00:00:00',
'2026-01-01 / 2026-04-30',
'SALIDAS',
'Reporte asociado al movimiento 64');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-06 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 65');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-20 00:00:00',
'2026-01-01 / 2026-04-30',
'SALIDAS',
'Reporte asociado al movimiento 66');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-16 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 67');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-08 00:00:00',
'2026-01-01 / 2026-04-30',
'PERDIDAS',
'Reporte asociado al movimiento 68');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-15 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 69');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-29 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 70');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-22 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 71');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-03 00:00:00',
'2026-01-01 / 2026-04-30',
'PERDIDAS',
'Reporte asociado al movimiento 72');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-19 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 73');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-23 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 74');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-28 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 75');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-13 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 76');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-08 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 77');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-19 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 78');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-01 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 79');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-01 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 80');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-30 00:00:00',
'2026-01-01 / 2026-04-30',
'PERDIDAS',
'Reporte asociado al movimiento 81');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-27 00:00:00',
'2026-01-01 / 2026-04-30',
'PERDIDAS',
'Reporte asociado al movimiento 82');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-20 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 83');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-21 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 84');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-22 00:00:00',
'2026-01-01 / 2026-04-30',
'SALIDAS',
'Reporte asociado al movimiento 85');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-29 00:00:00',
'2026-01-01 / 2026-04-30',
'SALIDAS',
'Reporte asociado al movimiento 86');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-26 00:00:00',
'2026-01-01 / 2026-04-30',
'STOCK',
'Reporte asociado al movimiento 87');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-19 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 88');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-03 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 89');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-24 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 90');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-07 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 91');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-17 00:00:00',
'2026-01-01 / 2026-04-30',
'SALIDAS',
'Reporte asociado al movimiento 92');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-27 00:00:00',
'2026-01-01 / 2026-04-30',
'PERDIDAS',
'Reporte asociado al movimiento 93');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-30 00:00:00',
'2026-01-01 / 2026-04-30',
'SALIDAS',
'Reporte asociado al movimiento 94');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-24 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 95');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-15 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 96');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-25 00:00:00',
'2026-01-01 / 2026-04-30',
'STOCK',
'Reporte asociado al movimiento 97');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-05-01 00:00:00',
'2026-01-01 / 2026-04-30',
'SALIDAS',
'Reporte asociado al movimiento 98');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-03 00:00:00',
'2026-01-01 / 2026-04-30',
'PERDIDAS',
'Reporte asociado al movimiento 99');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-09 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 100');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-15 00:00:00',
'2026-01-01 / 2026-04-30',
'PERDIDAS',
'Reporte asociado al movimiento 101');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-19 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 102');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-04 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 103');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-01 00:00:00',
'2026-01-01 / 2026-04-30',
'SALIDAS',
'Reporte asociado al movimiento 104');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-30 00:00:00',
'2026-01-01 / 2026-04-30',
'PERDIDAS',
'Reporte asociado al movimiento 105');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-21 00:00:00',
'2026-01-01 / 2026-04-30',
'PERDIDAS',
'Reporte asociado al movimiento 106');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-30 00:00:00',
'2026-01-01 / 2026-04-30',
'STOCK',
'Reporte asociado al movimiento 107');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-04 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 108');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-05-01 00:00:00',
'2026-01-01 / 2026-04-30',
'SALIDAS',
'Reporte asociado al movimiento 109');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-16 00:00:00',
'2026-01-01 / 2026-04-30',
'STOCK',
'Reporte asociado al movimiento 110');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-08 00:00:00',
'2026-01-01 / 2026-04-30',
'STOCK',
'Reporte asociado al movimiento 111');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-13 00:00:00',
'2026-01-01 / 2026-04-30',
'PERDIDAS',
'Reporte asociado al movimiento 112');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-22 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 113');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-19 00:00:00',
'2026-01-01 / 2026-04-30',
'PERDIDAS',
'Reporte asociado al movimiento 114');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-21 00:00:00',
'2026-01-01 / 2026-04-30',
'SALIDAS',
'Reporte asociado al movimiento 115');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-20 00:00:00',
'2026-01-01 / 2026-04-30',
'STOCK',
'Reporte asociado al movimiento 116');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-02 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 117');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-15 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 118');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-28 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 119');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-22 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 120');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-02 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 121');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-07 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 122');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-03 00:00:00',
'2026-01-01 / 2026-04-30',
'STOCK',
'Reporte asociado al movimiento 123');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-02 00:00:00',
'2026-01-01 / 2026-04-30',
'SALIDAS',
'Reporte asociado al movimiento 124');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-05 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 125');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-03 00:00:00',
'2026-01-01 / 2026-04-30',
'PERDIDAS',
'Reporte asociado al movimiento 126');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-19 00:00:00',
'2026-01-01 / 2026-04-30',
'PERDIDAS',
'Reporte asociado al movimiento 127');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-11 00:00:00',
'2026-01-01 / 2026-04-30',
'SALIDAS',
'Reporte asociado al movimiento 128');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-09 00:00:00',
'2026-01-01 / 2026-04-30',
'SALIDAS',
'Reporte asociado al movimiento 129');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-18 00:00:00',
'2026-01-01 / 2026-04-30',
'SALIDAS',
'Reporte asociado al movimiento 130');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-04 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 131');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-01 00:00:00',
'2026-01-01 / 2026-04-30',
'STOCK',
'Reporte asociado al movimiento 132');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-19 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 133');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-06 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 134');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-05 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 135');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-24 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 136');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-15 00:00:00',
'2026-01-01 / 2026-04-30',
'STOCK',
'Reporte asociado al movimiento 137');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-15 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 138');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-05-01 00:00:00',
'2026-01-01 / 2026-04-30',
'PERDIDAS',
'Reporte asociado al movimiento 139');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-24 00:00:00',
'2026-01-01 / 2026-04-30',
'PERDIDAS',
'Reporte asociado al movimiento 140');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-15 00:00:00',
'2026-01-01 / 2026-04-30',
'PERDIDAS',
'Reporte asociado al movimiento 141');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-16 00:00:00',
'2026-01-01 / 2026-04-30',
'STOCK',
'Reporte asociado al movimiento 142');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-22 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 143');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-23 00:00:00',
'2026-01-01 / 2026-04-30',
'STOCK',
'Reporte asociado al movimiento 144');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-29 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 145');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-20 00:00:00',
'2026-01-01 / 2026-04-30',
'STOCK',
'Reporte asociado al movimiento 146');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-05 00:00:00',
'2026-01-01 / 2026-04-30',
'SALIDAS',
'Reporte asociado al movimiento 147');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-13 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 148');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-15 00:00:00',
'2026-01-01 / 2026-04-30',
'PERDIDAS',
'Reporte asociado al movimiento 149');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-04 00:00:00',
'2026-01-01 / 2026-04-30',
'PERDIDAS',
'Reporte asociado al movimiento 150');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-14 00:00:00',
'2026-01-01 / 2026-04-30',
'STOCK',
'Reporte asociado al movimiento 151');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-14 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 152');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-13 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 153');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-11 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 154');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-22 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 155');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-05-01 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 156');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (2,
'2026-04-03 00:00:00',
'2026-01-01 / 2026-04-30',
'SALIDAS',
'Reporte asociado al movimiento 157');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-03 00:00:00',
'2026-01-01 / 2026-04-30',
'STOCK',
'Reporte asociado al movimiento 158');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-24 00:00:00',
'2026-01-01 / 2026-04-30',
'HISTORIAL',
'Reporte asociado al movimiento 159');


INSERT INTO reporte
(id_usuario,fecha_emision,rango_fechas,tipo_reporte,resumen)
VALUES (1,
'2026-04-18 00:00:00',
'2026-01-01 / 2026-04-30',
'ENTRADAS',
'Reporte asociado al movimiento 160');



-- ============================================================
-- MÓDULO 1: USUARIOS DEL SISTEMA
-- Implementa RQF001 - RQF009
-- Base: salinas_del_cravo_v2
--
-- IMPORTANTE:
-- Este bloque reemplaza las tablas antiguas:
-- usuario, administrador y vendedor.
--
-- Debe ir ANTES de cualquier tabla que tenga FK hacia usuario.
-- ============================================================

-- ============================================================
-- LIMPIEZA DEL MÓDULO 1
-- ============================================================

DROP PROCEDURE IF EXISTS sp_crear_usuario;
DROP PROCEDURE IF EXISTS sp_listar_usuarios;
DROP PROCEDURE IF EXISTS sp_actualizar_usuario;
DROP PROCEDURE IF EXISTS sp_desactivar_usuario;
DROP PROCEDURE IF EXISTS sp_iniciar_sesion;
DROP PROCEDURE IF EXISTS sp_cerrar_sesion;
DROP PROCEDURE IF EXISTS sp_asignar_rol;

DROP VIEW IF EXISTS vw_usuarios_sistema;

DROP TRIGGER IF EXISTS trg_usuario_no_delete;

-- ============================================================
-- LIMPIEZA SEGURA DEL MÓDULO 1 EN DESARROLLO
-- ============================================================

SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS sesion_usuario;
DROP TABLE IF EXISTS administrador;
DROP TABLE IF EXISTS vendedor;
DROP TABLE IF EXISTS usuario;

SET FOREIGN_KEY_CHECKS = 1;

-- ============================================================
-- TABLA PRINCIPAL: USUARIO
-- RQF001, RQF002, RQF003, RQF004, RQF005, RQF008, RQF009
-- ============================================================

CREATE TABLE usuario (
    id_usuario              INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    nombre_completo         VARCHAR(150) NOT NULL,
    numero_documento        VARCHAR(25) NOT NULL,
    password_hash           CHAR(64) NOT NULL,
    password_salt           CHAR(32) NOT NULL,
    rol                     ENUM(
                                'ADMINISTRADOR',
                                'JEFE_PRODUCCION',
                                'ENCARGADO_BODEGA',
                                'AUDITOR'
                            ) NOT NULL,
    estado_activo           TINYINT(1) NOT NULL DEFAULT 1,
    fecha_creacion          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                            ON UPDATE CURRENT_TIMESTAMP,
    fecha_desactivacion     DATETIME NULL,
    ultimo_acceso           DATETIME NULL,

    CONSTRAINT uq_usuario_documento UNIQUE (numero_documento),
    CONSTRAINT ck_usuario_estado CHECK (estado_activo IN (0, 1))
);

CREATE INDEX idx_usuario_rol ON usuario (rol);
CREATE INDEX idx_usuario_estado ON usuario (estado_activo);
CREATE INDEX idx_usuario_documento_estado ON usuario (numero_documento, estado_activo);

-- ============================================================
-- TABLA DE SESIONES
-- RQF006, RQF007, RQF009
-- ============================================================

CREATE TABLE sesion_usuario (
    id_sesion           BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    id_usuario          INT NOT NULL,
    token_sesion        CHAR(64) NOT NULL,
    fecha_inicio        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_cierre        DATETIME NULL,
    estado_sesion       ENUM('ABIERTA', 'CERRADA') NOT NULL DEFAULT 'ABIERTA',

    CONSTRAINT uq_sesion_token UNIQUE (token_sesion),

    CONSTRAINT fk_sesion_usuario
        FOREIGN KEY (id_usuario) REFERENCES usuario (id_usuario)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    CONSTRAINT ck_sesion_fechas
        CHECK (fecha_cierre IS NULL OR fecha_cierre >= fecha_inicio)
);

CREATE INDEX idx_sesion_usuario_estado ON sesion_usuario (id_usuario, estado_sesion);

-- ============================================================
-- VISTA PARA LISTAR USUARIOS
-- RQF002
-- ============================================================

CREATE VIEW vw_usuarios_sistema AS
SELECT
    u.id_usuario,
    u.nombre_completo,
    u.numero_documento,
    u.rol,
    CASE
        WHEN u.estado_activo = 1 THEN 'ACTIVO'
        ELSE 'INACTIVO'
    END AS estado_usuario,
    u.fecha_creacion,
    u.fecha_actualizacion,
    u.fecha_desactivacion,
    u.ultimo_acceso
FROM usuario u;

-- ============================================================
-- BLOQUEAR ELIMINACIÓN FÍSICA DE USUARIOS
-- RQF004
-- ============================================================

DELIMITER $$

CREATE TRIGGER trg_usuario_no_delete
BEFORE DELETE ON usuario
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'RQF004: no se permite borrar usuarios. Use sp_desactivar_usuario para conservar el historial.';
END$$

-- ============================================================
-- RQF001, RQF005, RQF008
-- CREAR USUARIO
-- ============================================================

CREATE PROCEDURE sp_crear_usuario (
    IN p_nombre_completo VARCHAR(150),
    IN p_numero_documento VARCHAR(25),
    IN p_contrasena VARCHAR(255),
    IN p_rol VARCHAR(40)
)
BEGIN
    DECLARE v_documento VARCHAR(25);
    DECLARE v_rol VARCHAR(40);
    DECLARE v_salt CHAR(32);
    DECLARE v_existe INT DEFAULT 0;

    SET v_documento = TRIM(p_numero_documento);
    SET v_rol = UPPER(TRIM(p_rol));
    SET v_salt = REPLACE(UUID(), '-', '');

    IF p_nombre_completo IS NULL OR CHAR_LENGTH(TRIM(p_nombre_completo)) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF001: el nombre del usuario es obligatorio.';
    END IF;

    IF v_documento IS NULL OR CHAR_LENGTH(v_documento) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF001: el número de documento es obligatorio.';
    END IF;

    IF p_contrasena IS NULL OR CHAR_LENGTH(TRIM(p_contrasena)) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF001: la contraseña es obligatoria.';
    END IF;

    IF v_rol NOT IN (
        'ADMINISTRADOR',
        'JEFE_PRODUCCION',
        'ENCARGADO_BODEGA',
        'AUDITOR'
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF008: rol inválido. Use ADMINISTRADOR, JEFE_PRODUCCION, ENCARGADO_BODEGA o AUDITOR.';
    END IF;

    SELECT COUNT(*)
    INTO v_existe
    FROM usuario
    WHERE numero_documento = v_documento;

    IF v_existe > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF005: ya existe un usuario con ese número de documento.';
    END IF;

    INSERT INTO usuario (
        nombre_completo,
        numero_documento,
        password_hash,
        password_salt,
        rol,
        estado_activo
    )
    VALUES (
        TRIM(p_nombre_completo),
        v_documento,
        SHA2(CONCAT(p_contrasena, v_salt), 256),
        v_salt,
        v_rol,
        1
    );

    SELECT
        id_usuario,
        nombre_completo,
        numero_documento,
        rol,
        'ACTIVO' AS estado_usuario
    FROM usuario
    WHERE id_usuario = LAST_INSERT_ID();
END$$

-- ============================================================
-- RQF002
-- VER LISTA DE USUARIOS
-- ============================================================

CREATE PROCEDURE sp_listar_usuarios ()
BEGIN
    SELECT
        id_usuario,
        nombre_completo,
        numero_documento,
        rol,
        estado_usuario,
        fecha_creacion,
        ultimo_acceso
    FROM vw_usuarios_sistema
    ORDER BY nombre_completo ASC;
END$$

-- ============================================================
-- RQF003, RQF008
-- CAMBIAR DATOS DE USUARIO
-- Permite cambiar nombre, contraseña o rol.
-- Si un parámetro llega NULL, conserva el valor actual.
-- ============================================================

CREATE PROCEDURE sp_actualizar_usuario (
    IN p_id_usuario INT,
    IN p_nombre_completo VARCHAR(150),
    IN p_nueva_contrasena VARCHAR(255),
    IN p_rol VARCHAR(40)
)
BEGIN
    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_rol VARCHAR(40) DEFAULT NULL;
    DECLARE v_salt CHAR(32) DEFAULT NULL;

    SELECT COUNT(*)
    INTO v_existe
    FROM usuario
    WHERE id_usuario = p_id_usuario;

    IF v_existe = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF003: el usuario indicado no existe.';
    END IF;

    IF p_nombre_completo IS NOT NULL
       AND CHAR_LENGTH(TRIM(p_nombre_completo)) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF003: el nombre no puede quedar vacío.';
    END IF;

    IF p_nueva_contrasena IS NOT NULL
       AND CHAR_LENGTH(TRIM(p_nueva_contrasena)) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF003: la contraseña no puede quedar vacía.';
    END IF;

    IF p_rol IS NOT NULL THEN
        SET v_rol = UPPER(TRIM(p_rol));

        IF v_rol NOT IN (
            'ADMINISTRADOR',
            'JEFE_PRODUCCION',
            'ENCARGADO_BODEGA',
            'AUDITOR'
        ) THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'RQF008: rol inválido. Use ADMINISTRADOR, JEFE_PRODUCCION, ENCARGADO_BODEGA o AUDITOR.';
        END IF;
    END IF;

    IF p_nueva_contrasena IS NOT NULL THEN
        SET v_salt = REPLACE(UUID(), '-', '');
    END IF;

    UPDATE usuario
    SET
        nombre_completo = CASE
            WHEN p_nombre_completo IS NOT NULL THEN TRIM(p_nombre_completo)
            ELSE nombre_completo
        END,

        password_salt = CASE
            WHEN p_nueva_contrasena IS NOT NULL THEN v_salt
            ELSE password_salt
        END,

        password_hash = CASE
            WHEN p_nueva_contrasena IS NOT NULL THEN SHA2(CONCAT(p_nueva_contrasena, v_salt), 256)
            ELSE password_hash
        END,

        rol = CASE
            WHEN v_rol IS NOT NULL THEN v_rol
            ELSE rol
        END
    WHERE id_usuario = p_id_usuario;

    SELECT
        id_usuario,
        nombre_completo,
        numero_documento,
        rol,
        CASE
            WHEN estado_activo = 1 THEN 'ACTIVO'
            ELSE 'INACTIVO'
        END AS estado_usuario
    FROM usuario
    WHERE id_usuario = p_id_usuario;
END$$

-- ============================================================
-- RQF004, RQF009
-- DESACTIVAR USUARIO
-- No borra el usuario.
-- También cierra sus sesiones abiertas.
-- ============================================================

CREATE PROCEDURE sp_desactivar_usuario (
    IN p_id_usuario INT
)
BEGIN
    DECLARE v_existe INT DEFAULT 0;

    SELECT COUNT(*)
    INTO v_existe
    FROM usuario
    WHERE id_usuario = p_id_usuario;

    IF v_existe = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF004: el usuario indicado no existe.';
    END IF;

    UPDATE usuario
    SET
        estado_activo = 0,
        fecha_desactivacion = CURRENT_TIMESTAMP
    WHERE id_usuario = p_id_usuario;

    UPDATE sesion_usuario
    SET
        estado_sesion = 'CERRADA',
        fecha_cierre = CURRENT_TIMESTAMP
    WHERE id_usuario = p_id_usuario
      AND estado_sesion = 'ABIERTA';

    SELECT
        id_usuario,
        nombre_completo,
        numero_documento,
        rol,
        'INACTIVO' AS estado_usuario,
        fecha_desactivacion
    FROM usuario
    WHERE id_usuario = p_id_usuario;
END$$

-- ============================================================
-- RQF006, RQF009
-- INICIAR SESIÓN
-- Solo permite entrar a usuarios activos.
-- ============================================================

CREATE PROCEDURE sp_iniciar_sesion (
    IN p_numero_documento VARCHAR(25),
    IN p_contrasena VARCHAR(255)
)
BEGIN
    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_id_usuario INT;
    DECLARE v_nombre VARCHAR(150);
    DECLARE v_rol VARCHAR(40);
    DECLARE v_estado TINYINT(1);
    DECLARE v_hash CHAR(64);
    DECLARE v_salt CHAR(32);
    DECLARE v_token CHAR(64);

    IF p_numero_documento IS NULL OR CHAR_LENGTH(TRIM(p_numero_documento)) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF006: debe ingresar el número de documento.';
    END IF;

    IF p_contrasena IS NULL OR CHAR_LENGTH(TRIM(p_contrasena)) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF006: debe ingresar la contraseña.';
    END IF;

    SELECT COUNT(*)
    INTO v_existe
    FROM usuario
    WHERE numero_documento = TRIM(p_numero_documento);

    IF v_existe = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF006: documento o contraseña incorrectos.';
    END IF;

    SELECT
        id_usuario,
        nombre_completo,
        rol,
        estado_activo,
        password_hash,
        password_salt
    INTO
        v_id_usuario,
        v_nombre,
        v_rol,
        v_estado,
        v_hash,
        v_salt
    FROM usuario
    WHERE numero_documento = TRIM(p_numero_documento)
    LIMIT 1;

    IF v_estado = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF009: usuario desactivado. No puede iniciar sesión.';
    END IF;

    IF SHA2(CONCAT(p_contrasena, v_salt), 256) <> v_hash THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF006: documento o contraseña incorrectos.';
    END IF;

    SET v_token = SHA2(CONCAT(UUID(), RAND(), NOW(6), v_id_usuario), 256);

    INSERT INTO sesion_usuario (
        id_usuario,
        token_sesion,
        estado_sesion
    )
    VALUES (
        v_id_usuario,
        v_token,
        'ABIERTA'
    );

    UPDATE usuario
    SET ultimo_acceso = CURRENT_TIMESTAMP
    WHERE id_usuario = v_id_usuario;

    SELECT
        'LOGIN_OK' AS resultado,
        v_token AS token_sesion,
        v_id_usuario AS id_usuario,
        v_nombre AS nombre_completo,
        v_rol AS rol;
END$$

-- ============================================================
-- RQF007
-- CERRAR SESIÓN
-- Cierra una sesión abierta y evita reutilizar el token.
-- ============================================================

CREATE PROCEDURE sp_cerrar_sesion (
    IN p_token_sesion CHAR(64)
)
BEGIN
    DECLARE v_existe INT DEFAULT 0;

    IF p_token_sesion IS NULL OR CHAR_LENGTH(TRIM(p_token_sesion)) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF007: debe enviar un token de sesión válido.';
    END IF;

    SELECT COUNT(*)
    INTO v_existe
    FROM sesion_usuario
    WHERE token_sesion = TRIM(p_token_sesion)
      AND estado_sesion = 'ABIERTA';

    IF v_existe = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF007: la sesión no existe o ya fue cerrada.';
    END IF;

    UPDATE sesion_usuario
    SET
        estado_sesion = 'CERRADA',
        fecha_cierre = CURRENT_TIMESTAMP
    WHERE token_sesion = TRIM(p_token_sesion)
      AND estado_sesion = 'ABIERTA';

    SELECT
        'LOGOUT_OK' AS resultado,
        'Sesión cerrada correctamente.' AS mensaje;
END$$

-- ============================================================
-- RQF008
-- ASIGNAR ROL
-- ============================================================

CREATE PROCEDURE sp_asignar_rol (
    IN p_id_usuario INT,
    IN p_rol VARCHAR(40)
)
BEGIN
    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_rol VARCHAR(40);

    SET v_rol = UPPER(TRIM(p_rol));

    SELECT COUNT(*)
    INTO v_existe
    FROM usuario
    WHERE id_usuario = p_id_usuario;

    IF v_existe = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF008: el usuario indicado no existe.';
    END IF;

    IF v_rol NOT IN (
        'ADMINISTRADOR',
        'JEFE_PRODUCCION',
        'ENCARGADO_BODEGA',
        'AUDITOR'
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF008: rol inválido. Use ADMINISTRADOR, JEFE_PRODUCCION, ENCARGADO_BODEGA o AUDITOR.';
    END IF;

    UPDATE usuario
    SET rol = v_rol
    WHERE id_usuario = p_id_usuario;

    SELECT
        id_usuario,
        nombre_completo,
        numero_documento,
        rol,
        CASE
            WHEN estado_activo = 1 THEN 'ACTIVO'
            ELSE 'INACTIVO'
        END AS estado_usuario
    FROM usuario
    WHERE id_usuario = p_id_usuario;
END$$

DELIMITER ;

-- ============================================================
-- DATOS INICIALES DEL MÓDULO 1
-- Usuarios base para probar cada rol del sistema.
-- ============================================================

CALL sp_crear_usuario(
    'Administrador Principal',
    '1000000001',
    'Admin2026!',
    'ADMINISTRADOR'
);

CALL sp_crear_usuario(
    'Jefe de Producción Principal',
    '1000000002',
    'Jefe2026!',
    'JEFE_PRODUCCION'
);

CALL sp_crear_usuario(
    'Encargado de Bodega Principal',
    '1000000003',
    'Bodega2026!',
    'ENCARGADO_BODEGA'
);

CALL sp_crear_usuario(
    'Auditor de Inventario Principal',
    '1000000004',
    'Auditor2026!',
    'AUDITOR'
);

-- ============================================================
-- CONSULTA FINAL DE VALIDACIÓN
-- ============================================================

CALL sp_listar_usuarios();

-- ============================================================
-- MÓDULO 2: TIPOS DE SAL
-- Implementa RQF010 - RQF017
-- Base: salinas_del_cravo_v2
--
-- Este módulo reemplaza y mejora:
-- categoria
-- producto
-- ============================================================

-- ============================================================
-- LIMPIEZA DEL MÓDULO 2
-- ============================================================

DROP TRIGGER IF EXISTS trg_categoria_no_delete;
DROP TRIGGER IF EXISTS trg_categoria_bu_validar_desactivacion;
DROP TRIGGER IF EXISTS trg_producto_no_delete;
DROP TRIGGER IF EXISTS trg_producto_bi_validar_categoria;
DROP TRIGGER IF EXISTS trg_producto_bu_validar_categoria;
DROP TRIGGER IF EXISTS trg_movimiento_bi_bloquear_tipo_inactivo;
DROP TRIGGER IF EXISTS trg_movimiento_bu_bloquear_tipo_inactivo;

DROP PROCEDURE IF EXISTS sp_crear_categoria;
DROP PROCEDURE IF EXISTS sp_listar_categorias;
DROP PROCEDURE IF EXISTS sp_actualizar_categoria;
DROP PROCEDURE IF EXISTS sp_desactivar_categoria;

DROP PROCEDURE IF EXISTS sp_crear_tipo_sal;
DROP PROCEDURE IF EXISTS sp_listar_tipos_sal;
DROP PROCEDURE IF EXISTS sp_actualizar_tipo_sal;
DROP PROCEDURE IF EXISTS sp_desactivar_tipo_sal;
DROP PROCEDURE IF EXISTS sp_validar_tipo_sal_activo;

DROP FUNCTION IF EXISTS fn_tipo_sal_activo;

DROP VIEW IF EXISTS vw_tipos_sal;
DROP VIEW IF EXISTS vw_categorias;

-- ============================================================
-- LIMPIEZA SEGURA EN DESARROLLO
-- producto es tabla padre de stock, movimiento_inventario, etc.
-- Por eso se desactivan temporalmente las FK.
-- ============================================================

SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS producto;
DROP TABLE IF EXISTS categoria;

SET FOREIGN_KEY_CHECKS = 1;

-- ============================================================
-- TABLA: CATEGORIA
-- RQF015
-- ============================================================

CREATE TABLE categoria (
    id_categoria            INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    codigo_categoria        VARCHAR(30) NOT NULL,
    nombre_categoria        VARCHAR(100) NOT NULL,
    descripcion_uso         VARCHAR(255) NULL,
    porcentaje_fosforo      DECIMAL(5,2) NULL,
    estado_activo           TINYINT(1) NOT NULL DEFAULT 1,
    fecha_creacion          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                            ON UPDATE CURRENT_TIMESTAMP,
    fecha_desactivacion     DATETIME NULL,

    CONSTRAINT uq_categoria_codigo UNIQUE (codigo_categoria),
    CONSTRAINT uq_categoria_nombre UNIQUE (nombre_categoria),

    CONSTRAINT ck_categoria_estado
        CHECK (estado_activo IN (0, 1)),

    CONSTRAINT ck_categoria_fosforo
        CHECK (porcentaje_fosforo IS NULL OR porcentaje_fosforo BETWEEN 0 AND 100)
);

CREATE INDEX idx_categoria_estado ON categoria (estado_activo);

-- ============================================================
-- TABLA: PRODUCTO
-- En este sistema representa el "tipo de sal"
-- RQF010, RQF011, RQF012, RQF013, RQF014, RQF016, RQF017
-- ============================================================

CREATE TABLE producto (
    id_producto                 INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    codigo_tipo_sal             VARCHAR(30) NOT NULL,
    id_categoria                INT NOT NULL,
    nombre_sal_mineralizada     VARCHAR(150) NOT NULL,
    presentacion                VARCHAR(80) NOT NULL,
    peso_bulto_kg               DECIMAL(7,2) NOT NULL,
    porcentaje_fosforo          DECIMAL(5,2) NOT NULL,
    unidad_medida               VARCHAR(50) NOT NULL,
    estado_activo               TINYINT(1) NOT NULL DEFAULT 1,
    descontinuado               TINYINT(1) NOT NULL DEFAULT 0,
    fecha_creacion              DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                                ON UPDATE CURRENT_TIMESTAMP,
    fecha_desactivacion         DATETIME NULL,

    CONSTRAINT uq_producto_codigo UNIQUE (codigo_tipo_sal),

    CONSTRAINT ck_producto_peso
        CHECK (peso_bulto_kg > 0),

    CONSTRAINT ck_producto_fosforo
        CHECK (porcentaje_fosforo BETWEEN 0 AND 100),

    CONSTRAINT ck_producto_estado
        CHECK (estado_activo IN (0, 1)),

    CONSTRAINT ck_producto_descontinuado
        CHECK (descontinuado IN (0, 1)),

    CONSTRAINT fk_producto_categoria
        FOREIGN KEY (id_categoria) REFERENCES categoria (id_categoria)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
);

CREATE INDEX idx_producto_categoria ON producto (id_categoria);
CREATE INDEX idx_producto_estado ON producto (estado_activo);
CREATE INDEX idx_producto_codigo_estado ON producto (codigo_tipo_sal, estado_activo);

-- ============================================================
-- VISTAS DEL MÓDULO 2
-- RQF011, RQF015
-- ============================================================

CREATE VIEW vw_categorias AS
SELECT
    c.id_categoria,
    c.codigo_categoria,
    c.nombre_categoria,
    c.descripcion_uso,
    c.porcentaje_fosforo,
    CASE
        WHEN c.estado_activo = 1 THEN 'ACTIVA'
        ELSE 'INACTIVA'
    END AS estado_categoria,
    c.fecha_creacion,
    c.fecha_actualizacion,
    c.fecha_desactivacion
FROM categoria c;

CREATE VIEW vw_tipos_sal AS
SELECT
    p.id_producto,
    p.codigo_tipo_sal,
    p.nombre_sal_mineralizada,
    p.presentacion,
    p.peso_bulto_kg,
    p.porcentaje_fosforo,
    p.unidad_medida,
    p.id_categoria,
    c.codigo_categoria,
    c.nombre_categoria,
    CASE
        WHEN p.estado_activo = 1 THEN 'ACTIVO'
        ELSE 'INACTIVO'
    END AS estado_tipo_sal,
    CASE
        WHEN c.estado_activo = 1 THEN 'ACTIVA'
        ELSE 'INACTIVA'
    END AS estado_categoria,
    p.fecha_creacion,
    p.fecha_actualizacion,
    p.fecha_desactivacion
FROM producto p
INNER JOIN categoria c
    ON c.id_categoria = p.id_categoria;

-- ============================================================
-- FUNCIONES, TRIGGERS Y PROCEDIMIENTOS
-- ============================================================

DELIMITER $$

-- ============================================================
-- FUNCIÓN AUXILIAR
-- RQF017
-- Devuelve 1 si el tipo de sal existe y está activo.
-- Devuelve 0 si no existe o está inactivo.
-- ============================================================

CREATE FUNCTION fn_tipo_sal_activo (
    p_id_producto INT
)
RETURNS TINYINT
READS SQL DATA
BEGIN
    DECLARE v_resultado TINYINT DEFAULT 0;

    SELECT
        CASE
            WHEN COUNT(*) > 0 THEN 1
            ELSE 0
        END
    INTO v_resultado
    FROM producto p
    INNER JOIN categoria c
        ON c.id_categoria = p.id_categoria
    WHERE p.id_producto = p_id_producto
      AND p.estado_activo = 1
      AND p.descontinuado = 0
      AND c.estado_activo = 1;

    RETURN v_resultado;
END$$

-- ============================================================
-- TRIGGER: NO BORRAR CATEGORÍAS
-- RQF015
-- ============================================================

CREATE TRIGGER trg_categoria_no_delete
BEFORE DELETE ON categoria
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'RQF015: no se permite borrar categorías. Use sp_desactivar_categoria para conservar el historial.';
END$$

-- ============================================================
-- TRIGGER: VALIDAR DESACTIVACIÓN DE CATEGORÍA
-- RQF015, RQF016
-- No deja desactivar una categoría si todavía tiene tipos activos.
-- ============================================================

CREATE TRIGGER trg_categoria_bu_validar_desactivacion
BEFORE UPDATE ON categoria
FOR EACH ROW
BEGIN
    DECLARE v_tipos_activos INT DEFAULT 0;

    IF OLD.estado_activo = 1 AND NEW.estado_activo = 0 THEN
        SELECT COUNT(*)
        INTO v_tipos_activos
        FROM producto
        WHERE id_categoria = OLD.id_categoria
          AND estado_activo = 1;

        IF v_tipos_activos > 0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'RQF015/RQF016: no se puede desactivar una categoría con tipos de sal activos. Desactive primero los tipos asociados.';
        END IF;
    END IF;
END$$

-- ============================================================
-- TRIGGER: NO BORRAR TIPOS DE SAL
-- RQF013
-- ============================================================

CREATE TRIGGER trg_producto_no_delete
BEFORE DELETE ON producto
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'RQF013: no se permite borrar tipos de sal. Use sp_desactivar_tipo_sal para conservar el historial.';
END$$

-- ============================================================
-- TRIGGER: VALIDAR CATEGORÍA ACTIVA AL CREAR TIPO
-- RQF010, RQF014, RQF016
-- ============================================================

CREATE TRIGGER trg_producto_bi_validar_categoria
BEFORE INSERT ON producto
FOR EACH ROW
BEGIN
    DECLARE v_categoria_activa INT DEFAULT 0;

    IF NEW.codigo_tipo_sal IS NULL OR CHAR_LENGTH(TRIM(NEW.codigo_tipo_sal)) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF010: el código del tipo de sal es obligatorio.';
    END IF;

    IF NEW.nombre_sal_mineralizada IS NULL OR CHAR_LENGTH(TRIM(NEW.nombre_sal_mineralizada)) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF010: el nombre del tipo de sal es obligatorio.';
    END IF;

    IF NEW.presentacion IS NULL OR CHAR_LENGTH(TRIM(NEW.presentacion)) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF010: la presentación del tipo de sal es obligatoria.';
    END IF;

    IF NEW.peso_bulto_kg IS NULL OR NEW.peso_bulto_kg <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF010: el peso del bulto debe ser mayor a cero.';
    END IF;

    IF NEW.porcentaje_fosforo IS NULL
       OR NEW.porcentaje_fosforo < 0
       OR NEW.porcentaje_fosforo > 100 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF010: el porcentaje de fósforo debe estar entre 0 y 100.';
    END IF;

    SELECT COUNT(*)
    INTO v_categoria_activa
    FROM categoria
    WHERE id_categoria = NEW.id_categoria
      AND estado_activo = 1;

    IF v_categoria_activa = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF016: no se puede crear un tipo de sal sin una categoría activa.';
    END IF;

    SET NEW.codigo_tipo_sal = UPPER(TRIM(NEW.codigo_tipo_sal));
    SET NEW.nombre_sal_mineralizada = TRIM(NEW.nombre_sal_mineralizada);
    SET NEW.presentacion = TRIM(NEW.presentacion);
    SET NEW.unidad_medida = TRIM(NEW.presentacion);

    IF NEW.estado_activo = 1 THEN
        SET NEW.descontinuado = 0;
    ELSE
        SET NEW.descontinuado = 1;
        SET NEW.fecha_desactivacion = CURRENT_TIMESTAMP;
    END IF;
END$$

-- ============================================================
-- TRIGGER: VALIDAR CATEGORÍA ACTIVA AL ACTUALIZAR TIPO
-- RQF012, RQF016
-- ============================================================

CREATE TRIGGER trg_producto_bu_validar_categoria
BEFORE UPDATE ON producto
FOR EACH ROW
BEGIN
    DECLARE v_categoria_activa INT DEFAULT 0;

    IF NEW.codigo_tipo_sal IS NULL OR CHAR_LENGTH(TRIM(NEW.codigo_tipo_sal)) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF012: el código del tipo de sal no puede quedar vacío.';
    END IF;

    IF NEW.nombre_sal_mineralizada IS NULL OR CHAR_LENGTH(TRIM(NEW.nombre_sal_mineralizada)) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF012: el nombre del tipo de sal no puede quedar vacío.';
    END IF;

    IF NEW.presentacion IS NULL OR CHAR_LENGTH(TRIM(NEW.presentacion)) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF012: la presentación no puede quedar vacía.';
    END IF;

    IF NEW.peso_bulto_kg IS NULL OR NEW.peso_bulto_kg <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF012: el peso del bulto debe ser mayor a cero.';
    END IF;

    IF NEW.porcentaje_fosforo IS NULL
       OR NEW.porcentaje_fosforo < 0
       OR NEW.porcentaje_fosforo > 100 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF012: el porcentaje de fósforo debe estar entre 0 y 100.';
    END IF;

    IF NEW.estado_activo = 1 THEN
        SELECT COUNT(*)
        INTO v_categoria_activa
        FROM categoria
        WHERE id_categoria = NEW.id_categoria
          AND estado_activo = 1;

        IF v_categoria_activa = 0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'RQF016: un tipo de sal activo debe tener una categoría activa.';
        END IF;

        SET NEW.descontinuado = 0;
        SET NEW.fecha_desactivacion = NULL;
    ELSE
        SET NEW.descontinuado = 1;

        IF NEW.fecha_desactivacion IS NULL THEN
            SET NEW.fecha_desactivacion = CURRENT_TIMESTAMP;
        END IF;
    END IF;

    SET NEW.codigo_tipo_sal = UPPER(TRIM(NEW.codigo_tipo_sal));
    SET NEW.nombre_sal_mineralizada = TRIM(NEW.nombre_sal_mineralizada);
    SET NEW.presentacion = TRIM(NEW.presentacion);
    SET NEW.unidad_medida = TRIM(NEW.presentacion);
END$$

-- ============================================================
-- TRIGGER: BLOQUEAR MOVIMIENTOS CON TIPOS INACTIVOS
-- RQF017
-- Esta tabla ya existe en el script base.
-- Para lotes se hará el mismo bloqueo cuando implementemos Módulo 3.
-- ============================================================

CREATE TRIGGER trg_movimiento_bi_bloquear_tipo_inactivo
BEFORE INSERT ON movimiento_inventario
FOR EACH ROW
BEGIN
    IF fn_tipo_sal_activo(NEW.id_producto) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF017: no se puede registrar un movimiento con un tipo de sal desactivado o con categoría inactiva.';
    END IF;
END$$

CREATE TRIGGER trg_movimiento_bu_bloquear_tipo_inactivo
BEFORE UPDATE ON movimiento_inventario
FOR EACH ROW
BEGIN
    IF fn_tipo_sal_activo(NEW.id_producto) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF017: no se puede actualizar un movimiento usando un tipo de sal desactivado o con categoría inactiva.';
    END IF;
END$$

-- ============================================================
-- RQF015
-- CREAR CATEGORÍA
-- ============================================================

CREATE PROCEDURE sp_crear_categoria (
    IN p_codigo_categoria VARCHAR(30),
    IN p_nombre_categoria VARCHAR(100),
    IN p_descripcion_uso VARCHAR(255),
    IN p_porcentaje_fosforo DECIMAL(5,2)
)
BEGIN
    DECLARE v_codigo VARCHAR(30);
    DECLARE v_existe INT DEFAULT 0;

    SET v_codigo = UPPER(TRIM(p_codigo_categoria));

    IF v_codigo IS NULL OR CHAR_LENGTH(v_codigo) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF015: el código de la categoría es obligatorio.';
    END IF;

    IF p_nombre_categoria IS NULL OR CHAR_LENGTH(TRIM(p_nombre_categoria)) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF015: el nombre de la categoría es obligatorio.';
    END IF;

    IF p_porcentaje_fosforo IS NOT NULL
       AND (p_porcentaje_fosforo < 0 OR p_porcentaje_fosforo > 100) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF015: el porcentaje de fósforo de la categoría debe estar entre 0 y 100.';
    END IF;

    SELECT COUNT(*)
    INTO v_existe
    FROM categoria
    WHERE codigo_categoria = v_codigo;

    IF v_existe > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF015: ya existe una categoría con ese código.';
    END IF;

    SELECT COUNT(*)
    INTO v_existe
    FROM categoria
    WHERE nombre_categoria = TRIM(p_nombre_categoria);

    IF v_existe > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF015: ya existe una categoría con ese nombre.';
    END IF;

    INSERT INTO categoria (
        codigo_categoria,
        nombre_categoria,
        descripcion_uso,
        porcentaje_fosforo,
        estado_activo
    )
    VALUES (
        v_codigo,
        TRIM(p_nombre_categoria),
        TRIM(p_descripcion_uso),
        p_porcentaje_fosforo,
        1
    );

    SELECT *
    FROM vw_categorias
    WHERE id_categoria = LAST_INSERT_ID();
END$$

-- ============================================================
-- RQF015
-- LISTAR CATEGORÍAS
-- ============================================================

CREATE PROCEDURE sp_listar_categorias (
    IN p_incluir_inactivas TINYINT
)
BEGIN
    SELECT
        id_categoria,
        codigo_categoria,
        nombre_categoria,
        descripcion_uso,
        porcentaje_fosforo,
        estado_categoria,
        fecha_creacion,
        fecha_desactivacion
    FROM vw_categorias
    WHERE p_incluir_inactivas = 1
       OR estado_categoria = 'ACTIVA'
    ORDER BY nombre_categoria ASC;
END$$

-- ============================================================
-- RQF015
-- ACTUALIZAR CATEGORÍA
-- Si un parámetro llega NULL, conserva el valor actual.
-- ============================================================

CREATE PROCEDURE sp_actualizar_categoria (
    IN p_id_categoria INT,
    IN p_codigo_categoria VARCHAR(30),
    IN p_nombre_categoria VARCHAR(100),
    IN p_descripcion_uso VARCHAR(255),
    IN p_porcentaje_fosforo DECIMAL(5,2)
)
BEGIN
    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_codigo VARCHAR(30) DEFAULT NULL;

    SELECT COUNT(*)
    INTO v_existe
    FROM categoria
    WHERE id_categoria = p_id_categoria;

    IF v_existe = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF015: la categoría indicada no existe.';
    END IF;

    IF p_codigo_categoria IS NOT NULL THEN
        SET v_codigo = UPPER(TRIM(p_codigo_categoria));

        IF CHAR_LENGTH(v_codigo) = 0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'RQF015: el código de la categoría no puede quedar vacío.';
        END IF;

        SELECT COUNT(*)
        INTO v_existe
        FROM categoria
        WHERE codigo_categoria = v_codigo
          AND id_categoria <> p_id_categoria;

        IF v_existe > 0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'RQF015: ya existe otra categoría con ese código.';
        END IF;
    END IF;

    IF p_nombre_categoria IS NOT NULL THEN
        IF CHAR_LENGTH(TRIM(p_nombre_categoria)) = 0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'RQF015: el nombre de la categoría no puede quedar vacío.';
        END IF;

        SELECT COUNT(*)
        INTO v_existe
        FROM categoria
        WHERE nombre_categoria = TRIM(p_nombre_categoria)
          AND id_categoria <> p_id_categoria;

        IF v_existe > 0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'RQF015: ya existe otra categoría con ese nombre.';
        END IF;
    END IF;

    IF p_porcentaje_fosforo IS NOT NULL
       AND (p_porcentaje_fosforo < 0 OR p_porcentaje_fosforo > 100) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF015: el porcentaje de fósforo debe estar entre 0 y 100.';
    END IF;

    UPDATE categoria
    SET
        codigo_categoria = CASE
            WHEN v_codigo IS NOT NULL THEN v_codigo
            ELSE codigo_categoria
        END,
        nombre_categoria = CASE
            WHEN p_nombre_categoria IS NOT NULL THEN TRIM(p_nombre_categoria)
            ELSE nombre_categoria
        END,
        descripcion_uso = CASE
            WHEN p_descripcion_uso IS NOT NULL THEN TRIM(p_descripcion_uso)
            ELSE descripcion_uso
        END,
        porcentaje_fosforo = CASE
            WHEN p_porcentaje_fosforo IS NOT NULL THEN p_porcentaje_fosforo
            ELSE porcentaje_fosforo
        END
    WHERE id_categoria = p_id_categoria;

    SELECT *
    FROM vw_categorias
    WHERE id_categoria = p_id_categoria;
END$$

-- ============================================================
-- RQF015
-- DESACTIVAR CATEGORÍA
-- No borra la categoría.
-- ============================================================

CREATE PROCEDURE sp_desactivar_categoria (
    IN p_id_categoria INT
)
BEGIN
    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_tipos_activos INT DEFAULT 0;

    SELECT COUNT(*)
    INTO v_existe
    FROM categoria
    WHERE id_categoria = p_id_categoria;

    IF v_existe = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF015: la categoría indicada no existe.';
    END IF;

    SELECT COUNT(*)
    INTO v_tipos_activos
    FROM producto
    WHERE id_categoria = p_id_categoria
      AND estado_activo = 1;

    IF v_tipos_activos > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF015/RQF016: no se puede desactivar una categoría con tipos de sal activos. Desactive primero los tipos asociados.';
    END IF;

    UPDATE categoria
    SET
        estado_activo = 0,
        fecha_desactivacion = CURRENT_TIMESTAMP
    WHERE id_categoria = p_id_categoria;

    SELECT *
    FROM vw_categorias
    WHERE id_categoria = p_id_categoria;
END$$

-- ============================================================
-- RQF010, RQF014, RQF016
-- CREAR TIPO DE SAL
-- ============================================================

CREATE PROCEDURE sp_crear_tipo_sal (
    IN p_codigo_tipo_sal VARCHAR(30),
    IN p_nombre_sal_mineralizada VARCHAR(150),
    IN p_id_categoria INT,
    IN p_presentacion VARCHAR(80),
    IN p_peso_bulto_kg DECIMAL(7,2),
    IN p_porcentaje_fosforo DECIMAL(5,2)
)
BEGIN
    DECLARE v_codigo VARCHAR(30);
    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_categoria_activa INT DEFAULT 0;

    SET v_codigo = UPPER(TRIM(p_codigo_tipo_sal));

    IF v_codigo IS NULL OR CHAR_LENGTH(v_codigo) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF010: el código del tipo de sal es obligatorio.';
    END IF;

    IF p_nombre_sal_mineralizada IS NULL
       OR CHAR_LENGTH(TRIM(p_nombre_sal_mineralizada)) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF010: el nombre del tipo de sal es obligatorio.';
    END IF;

    IF p_id_categoria IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF016: debe asignar una categoría activa al tipo de sal.';
    END IF;

    IF p_presentacion IS NULL OR CHAR_LENGTH(TRIM(p_presentacion)) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF010: la presentación es obligatoria.';
    END IF;

    IF p_peso_bulto_kg IS NULL OR p_peso_bulto_kg <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF010: el peso del bulto debe ser mayor a cero.';
    END IF;

    IF p_porcentaje_fosforo IS NULL
       OR p_porcentaje_fosforo < 0
       OR p_porcentaje_fosforo > 100 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF010: el porcentaje de fósforo debe estar entre 0 y 100.';
    END IF;

    SELECT COUNT(*)
    INTO v_existe
    FROM producto
    WHERE codigo_tipo_sal = v_codigo;

    IF v_existe > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF014: ya existe un tipo de sal con ese código.';
    END IF;

    SELECT COUNT(*)
    INTO v_categoria_activa
    FROM categoria
    WHERE id_categoria = p_id_categoria
      AND estado_activo = 1;

    IF v_categoria_activa = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF016: la categoría no existe o está inactiva.';
    END IF;

    INSERT INTO producto (
        codigo_tipo_sal,
        id_categoria,
        nombre_sal_mineralizada,
        presentacion,
        peso_bulto_kg,
        porcentaje_fosforo,
        unidad_medida,
        estado_activo,
        descontinuado
    )
    VALUES (
        v_codigo,
        p_id_categoria,
        TRIM(p_nombre_sal_mineralizada),
        TRIM(p_presentacion),
        p_peso_bulto_kg,
        p_porcentaje_fosforo,
        TRIM(p_presentacion),
        1,
        0
    );

    SELECT *
    FROM vw_tipos_sal
    WHERE id_producto = LAST_INSERT_ID();
END$$

-- ============================================================
-- RQF011
-- VER LISTA DE TIPOS DE SAL
-- Permite filtrar por nombre, código o categoría.
-- ============================================================

CREATE PROCEDURE sp_listar_tipos_sal (
    IN p_nombre VARCHAR(150),
    IN p_codigo VARCHAR(30),
    IN p_id_categoria INT,
    IN p_incluir_inactivos TINYINT
)
BEGIN
    SELECT
        id_producto,
        codigo_tipo_sal,
        nombre_sal_mineralizada,
        nombre_categoria,
        presentacion,
        peso_bulto_kg,
        porcentaje_fosforo,
        estado_tipo_sal,
        estado_categoria
    FROM vw_tipos_sal
    WHERE
        (
            p_nombre IS NULL
            OR CHAR_LENGTH(TRIM(p_nombre)) = 0
            OR nombre_sal_mineralizada LIKE CONCAT('%', TRIM(p_nombre), '%')
        )
        AND
        (
            p_codigo IS NULL
            OR CHAR_LENGTH(TRIM(p_codigo)) = 0
            OR codigo_tipo_sal LIKE CONCAT('%', UPPER(TRIM(p_codigo)), '%')
        )
        AND
        (
            p_id_categoria IS NULL
            OR id_categoria = p_id_categoria
        )
        AND
        (
            p_incluir_inactivos = 1
            OR estado_tipo_sal = 'ACTIVO'
        )
    ORDER BY nombre_categoria ASC, nombre_sal_mineralizada ASC;
END$$

-- ============================================================
-- RQF012, RQF014, RQF016
-- ACTUALIZAR TIPO DE SAL
-- Si un parámetro llega NULL, conserva el valor actual.
-- ============================================================

CREATE PROCEDURE sp_actualizar_tipo_sal (
    IN p_id_producto INT,
    IN p_codigo_tipo_sal VARCHAR(30),
    IN p_nombre_sal_mineralizada VARCHAR(150),
    IN p_id_categoria INT,
    IN p_presentacion VARCHAR(80),
    IN p_peso_bulto_kg DECIMAL(7,2),
    IN p_porcentaje_fosforo DECIMAL(5,2)
)
BEGIN
    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_codigo VARCHAR(30) DEFAULT NULL;
    DECLARE v_categoria_activa INT DEFAULT 0;

    SELECT COUNT(*)
    INTO v_existe
    FROM producto
    WHERE id_producto = p_id_producto;

    IF v_existe = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF012: el tipo de sal indicado no existe.';
    END IF;

    IF p_codigo_tipo_sal IS NOT NULL THEN
        SET v_codigo = UPPER(TRIM(p_codigo_tipo_sal));

        IF CHAR_LENGTH(v_codigo) = 0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'RQF012: el código del tipo de sal no puede quedar vacío.';
        END IF;

        SELECT COUNT(*)
        INTO v_existe
        FROM producto
        WHERE codigo_tipo_sal = v_codigo
          AND id_producto <> p_id_producto;

        IF v_existe > 0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'RQF014: ya existe otro tipo de sal con ese código.';
        END IF;
    END IF;

    IF p_nombre_sal_mineralizada IS NOT NULL
       AND CHAR_LENGTH(TRIM(p_nombre_sal_mineralizada)) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF012: el nombre del tipo de sal no puede quedar vacío.';
    END IF;

    IF p_presentacion IS NOT NULL
       AND CHAR_LENGTH(TRIM(p_presentacion)) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF012: la presentación no puede quedar vacía.';
    END IF;

    IF p_peso_bulto_kg IS NOT NULL AND p_peso_bulto_kg <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF012: el peso del bulto debe ser mayor a cero.';
    END IF;

    IF p_porcentaje_fosforo IS NOT NULL
       AND (p_porcentaje_fosforo < 0 OR p_porcentaje_fosforo > 100) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF012: el porcentaje de fósforo debe estar entre 0 y 100.';
    END IF;

    IF p_id_categoria IS NOT NULL THEN
        SELECT COUNT(*)
        INTO v_categoria_activa
        FROM categoria
        WHERE id_categoria = p_id_categoria
          AND estado_activo = 1;

        IF v_categoria_activa = 0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'RQF016: la categoría no existe o está inactiva.';
        END IF;
    END IF;

    UPDATE producto
    SET
        codigo_tipo_sal = CASE
            WHEN v_codigo IS NOT NULL THEN v_codigo
            ELSE codigo_tipo_sal
        END,
        nombre_sal_mineralizada = CASE
            WHEN p_nombre_sal_mineralizada IS NOT NULL THEN TRIM(p_nombre_sal_mineralizada)
            ELSE nombre_sal_mineralizada
        END,
        id_categoria = CASE
            WHEN p_id_categoria IS NOT NULL THEN p_id_categoria
            ELSE id_categoria
        END,
        presentacion = CASE
            WHEN p_presentacion IS NOT NULL THEN TRIM(p_presentacion)
            ELSE presentacion
        END,
        unidad_medida = CASE
            WHEN p_presentacion IS NOT NULL THEN TRIM(p_presentacion)
            ELSE unidad_medida
        END,
        peso_bulto_kg = CASE
            WHEN p_peso_bulto_kg IS NOT NULL THEN p_peso_bulto_kg
            ELSE peso_bulto_kg
        END,
        porcentaje_fosforo = CASE
            WHEN p_porcentaje_fosforo IS NOT NULL THEN p_porcentaje_fosforo
            ELSE porcentaje_fosforo
        END
    WHERE id_producto = p_id_producto;

    SELECT *
    FROM vw_tipos_sal
    WHERE id_producto = p_id_producto;
END$$

-- ============================================================
-- RQF013, RQF017
-- DESACTIVAR TIPO DE SAL
-- No borra el tipo, solo lo marca como inactivo.
-- ============================================================

CREATE PROCEDURE sp_desactivar_tipo_sal (
    IN p_id_producto INT
)
BEGIN
    DECLARE v_existe INT DEFAULT 0;

    SELECT COUNT(*)
    INTO v_existe
    FROM producto
    WHERE id_producto = p_id_producto;

    IF v_existe = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF013: el tipo de sal indicado no existe.';
    END IF;

    UPDATE producto
    SET
        estado_activo = 0,
        descontinuado = 1,
        fecha_desactivacion = CURRENT_TIMESTAMP
    WHERE id_producto = p_id_producto;

    SELECT *
    FROM vw_tipos_sal
    WHERE id_producto = p_id_producto;
END$$

-- ============================================================
-- RQF017
-- VALIDAR TIPO DE SAL ACTIVO
-- Útil para futuros módulos como lotes y movimientos.
-- ============================================================

CREATE PROCEDURE sp_validar_tipo_sal_activo (
    IN p_id_producto INT
)
BEGIN
    IF fn_tipo_sal_activo(p_id_producto) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF017: el tipo de sal no existe, está desactivado o pertenece a una categoría inactiva.';
    END IF;

    SELECT
        'TIPO_SAL_ACTIVO' AS resultado,
        p.id_producto,
        p.codigo_tipo_sal,
        p.nombre_sal_mineralizada
    FROM producto p
    WHERE p.id_producto = p_id_producto;
END$$

DELIMITER ;

-- ============================================================
-- DATOS INICIALES DEL MÓDULO 2
-- Mantienen 3 categorías y 12 tipos de sal como en el script base.
-- ============================================================

CALL sp_crear_categoria(
    'CAT-12',
    'Sal Mineralizada 12%',
    'Especial para ganado de leche',
    12.00
);

CALL sp_crear_categoria(
    'CAT-08',
    'Sal Mineralizada 8%',
    'Ganado doble propósito',
    8.00
);

CALL sp_crear_categoria(
    'CAT-04',
    'Sal Mineralizada 4%',
    'Ganado de ceba',
    4.00
);

-- Tipos de sal 12%

CALL sp_crear_tipo_sal(
    'SAL12-B50-1KG',
    'Sal Mineralizada 12% - Bulto 50kg 1kg',
    1,
    '1kg',
    50.00,
    12.00
);

CALL sp_crear_tipo_sal(
    'SAL12-B50-5KG',
    'Sal Mineralizada 12% - Bulto 50kg 5kg',
    1,
    '5kg',
    50.00,
    12.00
);

CALL sp_crear_tipo_sal(
    'SAL12-B40-GRANEL',
    'Sal Mineralizada 12% - Bulto 40kg Granel',
    1,
    'granel',
    40.00,
    12.00
);

CALL sp_crear_tipo_sal(
    'SAL12-M10',
    'Sal Mineralizada 12% - Mochila 10kg',
    1,
    'mochila',
    10.00,
    12.00
);

-- Tipos de sal 8%

CALL sp_crear_tipo_sal(
    'SAL08-B50-1KG',
    'Sal Mineralizada 8% - Bulto 50kg 1kg',
    2,
    '1kg',
    50.00,
    8.00
);

CALL sp_crear_tipo_sal(
    'SAL08-B50-5KG',
    'Sal Mineralizada 8% - Bulto 50kg 5kg',
    2,
    '5kg',
    50.00,
    8.00
);

CALL sp_crear_tipo_sal(
    'SAL08-B40-GRANEL',
    'Sal Mineralizada 8% - Bulto 40kg Granel',
    2,
    'granel',
    40.00,
    8.00
);

CALL sp_crear_tipo_sal(
    'SAL08-M10',
    'Sal Mineralizada 8% - Mochila 10kg',
    2,
    'mochila',
    10.00,
    8.00
);

-- Tipos de sal 4%

CALL sp_crear_tipo_sal(
    'SAL04-B50-1KG',
    'Sal Mineralizada 4% - Bulto 50kg 1kg',
    3,
    '1kg',
    50.00,
    4.00
);

CALL sp_crear_tipo_sal(
    'SAL04-B50-5KG',
    'Sal Mineralizada 4% - Bulto 50kg 5kg',
    3,
    '5kg',
    50.00,
    4.00
);

CALL sp_crear_tipo_sal(
    'SAL04-B40-GRANEL',
    'Sal Mineralizada 4% - Bulto 40kg Granel',
    3,
    'granel',
    40.00,
    4.00
);

CALL sp_crear_tipo_sal(
    'SAL04-M10',
    'Sal Mineralizada 4% - Mochila 10kg',
    3,
    'mochila',
    10.00,
    4.00
);

-- ============================================================
-- CONSULTAS FINALES DE VALIDACIÓN
-- ============================================================

CALL sp_listar_categorias(1);

CALL sp_listar_tipos_sal(NULL, NULL, NULL, 1);

-- ============================================================
-- MÓDULO 3: LOTES DE PRODUCCIÓN
-- Implementa RQF018 - RQF026
-- Base: salinas_del_cravo_v2
--
-- Depende de:
-- usuario
-- producto
-- bodega
-- stock
-- movimiento_inventario
-- entrada
-- ============================================================
-- ============================================================
-- LIMPIEZA DEL MÓDULO 3
-- ============================================================

DROP TRIGGER IF EXISTS trg_lote_no_delete;
DROP TRIGGER IF EXISTS trg_lote_bi_validaciones;
DROP TRIGGER IF EXISTS trg_lote_bu_validaciones;
DROP TRIGGER IF EXISTS trg_lote_movimiento_bi_validar_lote;

DROP PROCEDURE IF EXISTS sp_registrar_lote;
DROP PROCEDURE IF EXISTS sp_listar_lotes;
DROP PROCEDURE IF EXISTS sp_actualizar_lote;
DROP PROCEDURE IF EXISTS sp_desactivar_lote;
DROP PROCEDURE IF EXISTS sp_validar_lote_activo;

DROP FUNCTION IF EXISTS fn_lote_activo;

DROP VIEW IF EXISTS vw_lotes_produccion;

SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS lote_movimiento;
DROP TABLE IF EXISTS lote_produccion;

SET FOREIGN_KEY_CHECKS = 1;

-- ============================================================
-- TABLA: LOTE_PRODUCCION
-- RQF018, RQF020, RQF021, RQF022, RQF023, RQF024, RQF026
-- ============================================================

CREATE TABLE lote_produccion (
    id_lote                    INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    id_producto                INT NOT NULL,
    numero_lote                VARCHAR(50) NOT NULL,
    fecha_produccion           DATE NOT NULL,
    fecha_vencimiento          DATE NOT NULL,
    cantidad_bultos_inicial    INT NOT NULL,
    cantidad_bultos_actual     INT NOT NULL,
    id_bodega                  INT NOT NULL,
    id_usuario_productor       INT NOT NULL,
    estado_activo              TINYINT(1) NOT NULL DEFAULT 1,
    observaciones              TEXT NULL,
    fecha_registro             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                               ON UPDATE CURRENT_TIMESTAMP,
    fecha_desactivacion        DATETIME NULL,

    CONSTRAINT uq_lote_producto_numero
        UNIQUE (id_producto, numero_lote),

    CONSTRAINT ck_lote_cantidad_inicial
        CHECK (cantidad_bultos_inicial > 0),

    CONSTRAINT ck_lote_cantidad_actual
        CHECK (cantidad_bultos_actual >= 0),

    CONSTRAINT ck_lote_fechas
        CHECK (fecha_vencimiento > fecha_produccion),

    CONSTRAINT ck_lote_estado
        CHECK (estado_activo IN (0, 1)),

    CONSTRAINT fk_lote_producto
        FOREIGN KEY (id_producto) REFERENCES producto (id_producto)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    CONSTRAINT fk_lote_bodega
        FOREIGN KEY (id_bodega) REFERENCES bodega (id_bodega)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    CONSTRAINT fk_lote_usuario_productor
        FOREIGN KEY (id_usuario_productor) REFERENCES usuario (id_usuario)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
);

CREATE INDEX idx_lote_producto ON lote_produccion (id_producto);
CREATE INDEX idx_lote_bodega ON lote_produccion (id_bodega);
CREATE INDEX idx_lote_productor ON lote_produccion (id_usuario_productor);
CREATE INDEX idx_lote_estado ON lote_produccion (estado_activo);
CREATE INDEX idx_lote_vencimiento ON lote_produccion (fecha_vencimiento);

-- ============================================================
-- TABLA PUENTE: LOTE_MOVIMIENTO
-- Relaciona cada lote con su movimiento automático de entrada.
-- RQF025
-- ============================================================

CREATE TABLE lote_movimiento (
    id_lote_movimiento     INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    id_lote                INT NOT NULL,
    id_movimiento          INT NOT NULL,
    cantidad_bultos        INT NOT NULL,
    tipo_relacion          ENUM('ENTRADA_PRODUCCION') NOT NULL DEFAULT 'ENTRADA_PRODUCCION',
    fecha_relacion         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_lote_movimiento
        UNIQUE (id_lote, id_movimiento),

    CONSTRAINT ck_lote_movimiento_cantidad
        CHECK (cantidad_bultos > 0),

    CONSTRAINT fk_lote_movimiento_lote
        FOREIGN KEY (id_lote) REFERENCES lote_produccion (id_lote)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    CONSTRAINT fk_lote_movimiento_movimiento
        FOREIGN KEY (id_movimiento) REFERENCES movimiento_inventario (id_movimiento)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
);

CREATE INDEX idx_lote_movimiento_lote ON lote_movimiento (id_lote);
CREATE INDEX idx_lote_movimiento_movimiento ON lote_movimiento (id_movimiento);

-- ============================================================
-- VISTA: LOTES DE PRODUCCIÓN
-- RQF019
-- ============================================================

CREATE VIEW vw_lotes_produccion AS
SELECT
    l.id_lote,
    l.id_producto,
    p.codigo_tipo_sal,
    p.nombre_sal_mineralizada,
    l.numero_lote,
    l.fecha_produccion,
    l.fecha_vencimiento,
    l.cantidad_bultos_inicial,
    l.cantidad_bultos_actual,
    l.id_bodega,
    b.nombre_bodega,
    l.id_usuario_productor,
    u.nombre_completo AS producido_por,

    CASE
        WHEN l.estado_activo = 0 THEN 'INACTIVO'
        ELSE 'ACTIVO'
    END AS estado_lote,

    CASE
        WHEN l.estado_activo = 0 THEN 'NO_DISPONIBLE'
        WHEN l.fecha_vencimiento < CURDATE() THEN 'VENCIDO'
        WHEN l.fecha_vencimiento BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 30 DAY) THEN 'PROXIMO_A_VENCER'
        ELSE 'VIGENTE'
    END AS estado_vencimiento,

    l.observaciones,
    l.fecha_registro,
    l.fecha_actualizacion,
    l.fecha_desactivacion
FROM lote_produccion l
INNER JOIN producto p
    ON p.id_producto = l.id_producto
INNER JOIN bodega b
    ON b.id_bodega = l.id_bodega
INNER JOIN usuario u
    ON u.id_usuario = l.id_usuario_productor;

-- ============================================================
-- FUNCIONES, TRIGGERS Y PROCEDIMIENTOS
-- ============================================================

DELIMITER $$

-- ============================================================
-- FUNCIÓN AUXILIAR
-- RQF021
-- ============================================================

CREATE FUNCTION fn_lote_activo (
    p_id_lote INT
)
RETURNS TINYINT
READS SQL DATA
BEGIN
    DECLARE v_resultado TINYINT DEFAULT 0;

    SELECT
        CASE
            WHEN COUNT(*) > 0 THEN 1
            ELSE 0
        END
    INTO v_resultado
    FROM lote_produccion
    WHERE id_lote = p_id_lote
      AND estado_activo = 1;

    RETURN v_resultado;
END$$

-- ============================================================
-- TRIGGER: NO BORRAR LOTES
-- RQF021
-- ============================================================

CREATE TRIGGER trg_lote_no_delete
BEFORE DELETE ON lote_produccion
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'RQF021: no se permite borrar lotes. Use sp_desactivar_lote para conservar el historial.';
END$$

-- ============================================================
-- TRIGGER: VALIDACIONES AL CREAR LOTE
-- RQF018, RQF022, RQF023, RQF024
-- ============================================================

CREATE TRIGGER trg_lote_bi_validaciones
BEFORE INSERT ON lote_produccion
FOR EACH ROW
BEGIN
    IF NEW.numero_lote IS NULL OR CHAR_LENGTH(TRIM(NEW.numero_lote)) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF018: el número de lote es obligatorio.';
    END IF;

    IF NEW.fecha_produccion IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF018: la fecha de producción es obligatoria.';
    END IF;

    IF NEW.fecha_vencimiento IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF018: la fecha de vencimiento es obligatoria.';
    END IF;

    IF NEW.fecha_vencimiento <= NEW.fecha_produccion THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF023: la fecha de vencimiento debe ser mayor a la fecha de producción.';
    END IF;

    IF NEW.cantidad_bultos_inicial IS NULL OR NEW.cantidad_bultos_inicial <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF024: la cantidad de bultos debe ser mayor a cero.';
    END IF;

    IF NEW.cantidad_bultos_actual IS NULL OR NEW.cantidad_bultos_actual < 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF024: la cantidad actual no puede ser negativa.';
    END IF;

    SET NEW.numero_lote = UPPER(TRIM(NEW.numero_lote));
END$$

-- ============================================================
-- TRIGGER: VALIDACIONES AL ACTUALIZAR LOTE
-- RQF020, RQF022, RQF023, RQF024
--
-- No permite tocar:
-- cantidad inicial
-- fecha de producción
-- fecha de vencimiento
-- ============================================================

CREATE TRIGGER trg_lote_bu_validaciones
BEFORE UPDATE ON lote_produccion
FOR EACH ROW
BEGIN
    IF NEW.fecha_produccion <> OLD.fecha_produccion THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF020: no se permite cambiar la fecha de producción del lote.';
    END IF;

    IF NEW.fecha_vencimiento <> OLD.fecha_vencimiento THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF020: no se permite cambiar la fecha de vencimiento del lote.';
    END IF;

    IF NEW.cantidad_bultos_inicial <> OLD.cantidad_bultos_inicial THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF020: no se permite cambiar la cantidad inicial del lote.';
    END IF;

    IF NEW.numero_lote IS NULL OR CHAR_LENGTH(TRIM(NEW.numero_lote)) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF020: el número de lote no puede quedar vacío.';
    END IF;

    IF NEW.cantidad_bultos_actual < 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF024: la cantidad actual del lote no puede ser negativa.';
    END IF;

    SET NEW.numero_lote = UPPER(TRIM(NEW.numero_lote));
END$$

-- ============================================================
-- TRIGGER: VALIDAR LOTE ACTIVO EN RELACIÓN CON MOVIMIENTOS
-- RQF021
-- ============================================================

CREATE TRIGGER trg_lote_movimiento_bi_validar_lote
BEFORE INSERT ON lote_movimiento
FOR EACH ROW
BEGIN
    IF fn_lote_activo(NEW.id_lote) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF021: no se puede asociar un movimiento a un lote inactivo.';
    END IF;
END$$

-- ============================================================
-- RQF018, RQF022, RQF023, RQF024, RQF025, RQF026
-- REGISTRAR LOTE
--
-- Hace todo en una transacción:
-- 1. Valida producto activo
-- 2. Valida bodega activa
-- 3. Valida usuario jefe de producción activo
-- 4. Crea el lote
-- 5. Crea o actualiza el stock
-- 6. Registra movimiento automático de ENTRADA
-- 7. Registra detalle en entrada
-- 8. Relaciona lote con movimiento
-- ============================================================

CREATE PROCEDURE sp_registrar_lote (
    IN p_id_producto INT,
    IN p_numero_lote VARCHAR(50),
    IN p_fecha_produccion DATE,
    IN p_fecha_vencimiento DATE,
    IN p_cantidad_bultos INT,
    IN p_id_bodega INT,
    IN p_id_usuario_productor INT,
    IN p_observaciones TEXT
)
BEGIN
    DECLARE v_producto_valido INT DEFAULT 0;
    DECLARE v_bodega_valida INT DEFAULT 0;
    DECLARE v_usuario_valido INT DEFAULT 0;
    DECLARE v_lote_repetido INT DEFAULT 0;
    DECLARE v_id_lote INT;
    DECLARE v_id_stock INT;
    DECLARE v_id_movimiento INT;
    DECLARE v_numero_lote VARCHAR(50);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SET v_numero_lote = UPPER(TRIM(p_numero_lote));

    IF v_numero_lote IS NULL OR CHAR_LENGTH(v_numero_lote) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF018: el número de lote es obligatorio.';
    END IF;

    IF p_fecha_produccion IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF018: la fecha de producción es obligatoria.';
    END IF;

    IF p_fecha_vencimiento IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF018: la fecha de vencimiento es obligatoria.';
    END IF;

    IF p_fecha_vencimiento <= p_fecha_produccion THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF023: la fecha de vencimiento debe ser mayor a la fecha de producción.';
    END IF;

    IF p_cantidad_bultos IS NULL OR p_cantidad_bultos <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF024: la cantidad de bultos debe ser mayor a cero.';
    END IF;

    SELECT COUNT(*)
    INTO v_producto_valido
    FROM producto p
    INNER JOIN categoria c
        ON c.id_categoria = p.id_categoria
    WHERE p.id_producto = p_id_producto
      AND p.estado_activo = 1
      AND p.descontinuado = 0
      AND c.estado_activo = 1;

    IF v_producto_valido = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF018: el tipo de sal no existe, está desactivado o pertenece a una categoría inactiva.';
    END IF;

    SELECT COUNT(*)
    INTO v_bodega_valida
    FROM bodega
    WHERE id_bodega = p_id_bodega
      AND estado_activo = 1;

    IF v_bodega_valida = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF018: la bodega no existe o está inactiva.';
    END IF;

    SELECT COUNT(*)
    INTO v_usuario_valido
    FROM usuario
    WHERE id_usuario = p_id_usuario_productor
      AND estado_activo = 1
      AND rol = 'JEFE_PRODUCCION';

    IF v_usuario_valido = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF026: el lote debe ser registrado por un jefe de producción activo.';
    END IF;

    SELECT COUNT(*)
    INTO v_lote_repetido
    FROM lote_produccion
    WHERE id_producto = p_id_producto
      AND numero_lote = v_numero_lote;

    IF v_lote_repetido > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF022: ya existe un lote con ese número para este tipo de sal.';
    END IF;

    START TRANSACTION;

    INSERT INTO lote_produccion (
        id_producto,
        numero_lote,
        fecha_produccion,
        fecha_vencimiento,
        cantidad_bultos_inicial,
        cantidad_bultos_actual,
        id_bodega,
        id_usuario_productor,
        estado_activo,
        observaciones
    )
    VALUES (
        p_id_producto,
        v_numero_lote,
        p_fecha_produccion,
        p_fecha_vencimiento,
        p_cantidad_bultos,
        p_cantidad_bultos,
        p_id_bodega,
        p_id_usuario_productor,
        1,
        p_observaciones
    );

    SET v_id_lote = LAST_INSERT_ID();

    INSERT INTO stock (
        id_producto,
        id_bodega,
        cantidad_actual,
        stock_minimo_seguridad,
        fecha_ultima_auditoria
    )
    VALUES (
        p_id_producto,
        p_id_bodega,
        p_cantidad_bultos,
        0,
        CURRENT_TIMESTAMP
    )
    ON DUPLICATE KEY UPDATE
        cantidad_actual = cantidad_actual + p_cantidad_bultos,
        fecha_ultima_auditoria = CURRENT_TIMESTAMP;

    SELECT id_stock
    INTO v_id_stock
    FROM stock
    WHERE id_producto = p_id_producto
      AND id_bodega = p_id_bodega
    LIMIT 1;

    INSERT INTO movimiento_inventario (
        id_producto,
        id_usuario,
        id_bodega,
        id_reporte,
        fecha_movimiento,
        tipo_movimiento,
        cantidad_bultos,
        observaciones
    )
    VALUES (
        p_id_producto,
        p_id_usuario_productor,
        p_id_bodega,
        NULL,
        CURRENT_TIMESTAMP,
        'ENTRADA',
        p_cantidad_bultos,
        CONCAT('Entrada automática por registro del lote ', v_numero_lote)
    );

    SET v_id_movimiento = LAST_INSERT_ID();

    INSERT INTO entrada (
        id_stock,
        id_usuario,
        id_bodega,
        id_movimiento,
        id_proveedor,
        fecha_entrada,
        cantidad_ingresada,
        tipo_ingreso,
        numero_lote,
        observaciones
    )
    VALUES (
        v_id_stock,
        p_id_usuario_productor,
        p_id_bodega,
        v_id_movimiento,
        NULL,
        CURRENT_TIMESTAMP,
        p_cantidad_bultos,
        'PRODUCCION',
        v_numero_lote,
        CONCAT('Entrada automática generada desde el lote ', v_numero_lote)
    );

    INSERT INTO lote_movimiento (
        id_lote,
        id_movimiento,
        cantidad_bultos,
        tipo_relacion
    )
    VALUES (
        v_id_lote,
        v_id_movimiento,
        p_cantidad_bultos,
        'ENTRADA_PRODUCCION'
    );

    COMMIT;

    SELECT *
    FROM vw_lotes_produccion
    WHERE id_lote = v_id_lote;
END$$

-- ============================================================
-- RQF019
-- VER LISTA DE LOTES
--
-- Permite buscar por:
-- tipo de sal
-- usuario productor
-- estado
-- próximos a vencer
-- ============================================================

CREATE PROCEDURE sp_listar_lotes (
    IN p_id_producto INT,
    IN p_id_usuario_productor INT,
    IN p_estado VARCHAR(30),
    IN p_solo_proximos_vencer TINYINT,
    IN p_dias_alerta INT
)
BEGIN
    DECLARE v_dias_alerta INT DEFAULT 30;
    DECLARE v_estado VARCHAR(30);

    SET v_dias_alerta = IFNULL(p_dias_alerta, 30);
    SET v_estado = UPPER(TRIM(p_estado));

    SELECT
        id_lote,
        codigo_tipo_sal,
        nombre_sal_mineralizada,
        numero_lote,
        fecha_produccion,
        fecha_vencimiento,
        cantidad_bultos_inicial,
        cantidad_bultos_actual,
        nombre_bodega,
        producido_por,
        estado_lote,
        estado_vencimiento,
        observaciones
    FROM vw_lotes_produccion
    WHERE
        (
            p_id_producto IS NULL
            OR id_producto = p_id_producto
        )
        AND
        (
            p_id_usuario_productor IS NULL
            OR id_usuario_productor = p_id_usuario_productor
        )
        AND
        (
            p_estado IS NULL
            OR CHAR_LENGTH(TRIM(p_estado)) = 0
            OR estado_lote = v_estado
            OR estado_vencimiento = v_estado
        )
        AND
        (
            p_solo_proximos_vencer IS NULL
            OR p_solo_proximos_vencer = 0
            OR (
                estado_lote = 'ACTIVO'
                AND fecha_vencimiento BETWEEN CURDATE()
                AND DATE_ADD(CURDATE(), INTERVAL v_dias_alerta DAY)
            )
        )
    ORDER BY fecha_vencimiento ASC, numero_lote ASC;
END$$

-- ============================================================
-- RQF020, RQF022
-- ACTUALIZAR LOTE
--
-- Permite cambiar:
-- número de lote
-- bodega
-- observaciones
--
-- No permite cambiar:
-- cantidad
-- fecha de producción
-- fecha de vencimiento
-- ============================================================

CREATE PROCEDURE sp_actualizar_lote (
    IN p_id_lote INT,
    IN p_numero_lote VARCHAR(50),
    IN p_id_bodega INT,
    IN p_observaciones TEXT
)
BEGIN
    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_bodega_valida INT DEFAULT 0;
    DECLARE v_lote_repetido INT DEFAULT 0;

    DECLARE v_id_producto INT;
    DECLARE v_id_bodega_actual INT;
    DECLARE v_id_bodega_nueva INT;
    DECLARE v_id_stock_actual INT;
    DECLARE v_id_stock_nuevo INT;
    DECLARE v_id_movimiento INT;
    DECLARE v_cantidad INT;
    DECLARE v_numero_lote_actual VARCHAR(50);
    DECLARE v_numero_lote_nuevo VARCHAR(50);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SELECT COUNT(*)
    INTO v_existe
    FROM lote_produccion
    WHERE id_lote = p_id_lote;

    IF v_existe = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF020: el lote indicado no existe.';
    END IF;

    SELECT
        id_producto,
        id_bodega,
        cantidad_bultos_inicial,
        numero_lote
    INTO
        v_id_producto,
        v_id_bodega_actual,
        v_cantidad,
        v_numero_lote_actual
    FROM lote_produccion
    WHERE id_lote = p_id_lote;

    SET v_id_bodega_nueva = IFNULL(p_id_bodega, v_id_bodega_actual);

    IF p_numero_lote IS NULL THEN
        SET v_numero_lote_nuevo = v_numero_lote_actual;
    ELSE
        SET v_numero_lote_nuevo = UPPER(TRIM(p_numero_lote));
    END IF;

    IF v_numero_lote_nuevo IS NULL OR CHAR_LENGTH(v_numero_lote_nuevo) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF020: el número de lote no puede quedar vacío.';
    END IF;

    SELECT COUNT(*)
    INTO v_lote_repetido
    FROM lote_produccion
    WHERE id_producto = v_id_producto
      AND numero_lote = v_numero_lote_nuevo
      AND id_lote <> p_id_lote;

    IF v_lote_repetido > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF022: ya existe otro lote con ese número para este tipo de sal.';
    END IF;

    SELECT COUNT(*)
    INTO v_bodega_valida
    FROM bodega
    WHERE id_bodega = v_id_bodega_nueva
      AND estado_activo = 1;

    IF v_bodega_valida = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF020: la bodega no existe o está inactiva.';
    END IF;

    START TRANSACTION;

    IF v_id_bodega_nueva <> v_id_bodega_actual THEN

        SELECT id_stock
        INTO v_id_stock_actual
        FROM stock
        WHERE id_producto = v_id_producto
          AND id_bodega = v_id_bodega_actual
        LIMIT 1;

        IF v_id_stock_actual IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'RQF020: no existe stock actual asociado al lote.';
        END IF;

        UPDATE stock
        SET
            cantidad_actual = cantidad_actual - v_cantidad,
            fecha_ultima_auditoria = CURRENT_TIMESTAMP
        WHERE id_stock = v_id_stock_actual
          AND cantidad_actual >= v_cantidad;

        IF ROW_COUNT() = 0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'RQF020: no hay stock suficiente para mover el lote a otra bodega.';
        END IF;

        INSERT INTO stock (
            id_producto,
            id_bodega,
            cantidad_actual,
            stock_minimo_seguridad,
            fecha_ultima_auditoria
        )
        VALUES (
            v_id_producto,
            v_id_bodega_nueva,
            v_cantidad,
            0,
            CURRENT_TIMESTAMP
        )
        ON DUPLICATE KEY UPDATE
            cantidad_actual = cantidad_actual + v_cantidad,
            fecha_ultima_auditoria = CURRENT_TIMESTAMP;

        SELECT id_stock
        INTO v_id_stock_nuevo
        FROM stock
        WHERE id_producto = v_id_producto
          AND id_bodega = v_id_bodega_nueva
        LIMIT 1;

        SELECT lm.id_movimiento
        INTO v_id_movimiento
        FROM lote_movimiento lm
        WHERE lm.id_lote = p_id_lote
          AND lm.tipo_relacion = 'ENTRADA_PRODUCCION'
        LIMIT 1;

        UPDATE movimiento_inventario
        SET
            id_bodega = v_id_bodega_nueva,
            observaciones = CONCAT('Entrada automática por registro del lote ', v_numero_lote_nuevo)
        WHERE id_movimiento = v_id_movimiento;

        UPDATE entrada
        SET
            id_stock = v_id_stock_nuevo,
            id_bodega = v_id_bodega_nueva,
            numero_lote = v_numero_lote_nuevo,
            observaciones = CONCAT('Entrada automática generada desde el lote ', v_numero_lote_nuevo)
        WHERE id_movimiento = v_id_movimiento;
    ELSE
        SELECT lm.id_movimiento
        INTO v_id_movimiento
        FROM lote_movimiento lm
        WHERE lm.id_lote = p_id_lote
          AND lm.tipo_relacion = 'ENTRADA_PRODUCCION'
        LIMIT 1;

        UPDATE movimiento_inventario
        SET observaciones = CONCAT('Entrada automática por registro del lote ', v_numero_lote_nuevo)
        WHERE id_movimiento = v_id_movimiento;

        UPDATE entrada
        SET
            numero_lote = v_numero_lote_nuevo,
            observaciones = CONCAT('Entrada automática generada desde el lote ', v_numero_lote_nuevo)
        WHERE id_movimiento = v_id_movimiento;
    END IF;

    UPDATE lote_produccion
    SET
        numero_lote = v_numero_lote_nuevo,
        id_bodega = v_id_bodega_nueva,
        observaciones = CASE
            WHEN p_observaciones IS NOT NULL THEN p_observaciones
            ELSE observaciones
        END
    WHERE id_lote = p_id_lote;

    COMMIT;

    SELECT *
    FROM vw_lotes_produccion
    WHERE id_lote = p_id_lote;
END$$

-- ============================================================
-- RQF021
-- DESACTIVAR LOTE
-- No borra el lote.
-- Solo lo marca como no disponible.
-- ============================================================

CREATE PROCEDURE sp_desactivar_lote (
    IN p_id_lote INT,
    IN p_id_usuario_admin INT
)
BEGIN
    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_admin_valido INT DEFAULT 0;

    SELECT COUNT(*)
    INTO v_existe
    FROM lote_produccion
    WHERE id_lote = p_id_lote;

    IF v_existe = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF021: el lote indicado no existe.';
    END IF;

    SELECT COUNT(*)
    INTO v_admin_valido
    FROM usuario
    WHERE id_usuario = p_id_usuario_admin
      AND estado_activo = 1
      AND rol = 'ADMINISTRADOR';

    IF v_admin_valido = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF021: solo un administrador activo puede desactivar lotes.';
    END IF;

    UPDATE lote_produccion
    SET
        estado_activo = 0,
        fecha_desactivacion = CURRENT_TIMESTAMP
    WHERE id_lote = p_id_lote;

    SELECT *
    FROM vw_lotes_produccion
    WHERE id_lote = p_id_lote;
END$$

-- ============================================================
-- RQF021
-- VALIDAR LOTE ACTIVO
-- Útil para módulos posteriores.
-- ============================================================

CREATE PROCEDURE sp_validar_lote_activo (
    IN p_id_lote INT
)
BEGIN
    IF fn_lote_activo(p_id_lote) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF021: el lote no existe o está inactivo.';
    END IF;

    SELECT
        'LOTE_ACTIVO' AS resultado,
        id_lote,
        numero_lote,
        id_producto,
        id_bodega,
        cantidad_bultos_actual
    FROM lote_produccion
    WHERE id_lote = p_id_lote;
END$$

DELIMITER ;

-- ============================================================
-- CONSULTAS DE VALIDACIÓN DEL MÓDULO 3
-- No insertan datos automáticamente para no alterar el stock.
-- ============================================================

CALL sp_listar_lotes(NULL, NULL, NULL, 0, 30);
