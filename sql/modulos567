-- ============================================================
-- BASE DE DATOS: salinas_del_cravo_v2
-- ============================================================
DROP DATABASE IF EXISTS salinas_del_cravo_v2;
CREATE DATABASE salinas_del_cravo_v2
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE salinas_del_cravo_v2;

-- ------------------------------------------------------------
-- Tabla CLIENTE
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
-- Tabla USUARIO
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
-- Tabla CATEGORIA
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
-- Tabla PRODUCTO
-- ------------------------------------------------------------
CREATE TABLE producto (
    id_producto             INT             NOT NULL AUTO_INCREMENT PRIMARY KEY,
    id_categoria            INT             NOT NULL,
    nombre_sal_mineralizada VARCHAR(150)    NOT NULL,
    peso_bulto_kg           DECIMAL(7,2)    NOT NULL,
    unidad_medida           VARCHAR(50)     NOT NULL,
    descontinuado           TINYINT(1)      NOT NULL DEFAULT 0,
    CONSTRAINT ck_peso_positivo
        CHECK (peso_bulto_kg > 0),
    CONSTRAINT fk_producto_categoria
        FOREIGN KEY (id_categoria) REFERENCES categoria (id_categoria)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

-- ------------------------------------------------------------
-- Tabla BODEGA
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
-- Tabla STOCK (inventario por producto y bodega, única fuente de existencias)
-- ------------------------------------------------------------
CREATE TABLE stock (
    id_stock                INT             NOT NULL AUTO_INCREMENT PRIMARY KEY,
    id_producto             INT             NOT NULL,
    id_bodega               INT             NOT NULL,
    cantidad_actual         INT             NOT NULL DEFAULT 0,
    stock_minimo_seguridad  INT             NOT NULL DEFAULT 0,
    fecha_ultima_auditoria  DATETIME        NOT NULL,
    CONSTRAINT uq_stock_prod_bod    UNIQUE (id_producto, id_bodega),
    CONSTRAINT ck_stock_cant_no_neg CHECK (cantidad_actual >= 0),
    CONSTRAINT ck_stock_min_no_neg  CHECK (stock_minimo_seguridad >= 0),
    CONSTRAINT fk_stock_producto
        FOREIGN KEY (id_producto) REFERENCES producto (id_producto)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_stock_bodega
        FOREIGN KEY (id_bodega) REFERENCES bodega (id_bodega)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

-- ------------------------------------------------------------
-- Tabla REPORTE
-- ------------------------------------------------------------
CREATE TABLE reporte (
    id_reporte          INT             NOT NULL AUTO_INCREMENT PRIMARY KEY,
    id_usuario          INT             NOT NULL,
    fecha_emision       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    rango_fechas        VARCHAR(100)        NULL,
    tipo_reporte        ENUM('STOCK','SALIDAS','ENTRADAS','HISTORIAL','PERDIDAS','VENTAS') NOT NULL,
    resumen             TEXT                NULL,
    CONSTRAINT fk_reporte_usuario
        FOREIGN KEY (id_usuario) REFERENCES usuario (id_usuario)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

-- ------------------------------------------------------------
-- Tabla MOVIMIENTO_INVENTARIO (registro maestro de toda transacción)
-- ------------------------------------------------------------
CREATE TABLE movimiento_inventario (
    id_movimiento       INT             NOT NULL AUTO_INCREMENT PRIMARY KEY,
    id_producto         INT             NOT NULL,
    id_usuario          INT             NOT NULL,
    id_bodega           INT             NOT NULL,
    id_reporte          INT                 NULL,
    fecha_movimiento    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    tipo_movimiento     ENUM('ENTRADA','SALIDA','AJUSTE','DEVOLUCION','PERDIDA','DAÑO','TRASLADO','VENTA') NOT NULL,
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
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_mov_reporte
        FOREIGN KEY (id_reporte) REFERENCES reporte (id_reporte)
        ON UPDATE CASCADE ON DELETE SET NULL
);

-- ------------------------------------------------------------
-- Tabla ENTRADA (detalle de ingreso a bodega)
-- ------------------------------------------------------------
CREATE TABLE entrada (
    id_entrada          INT             NOT NULL AUTO_INCREMENT PRIMARY KEY,
    id_stock            INT             NOT NULL,
    id_usuario          INT             NOT NULL,
    id_bodega           INT             NOT NULL,
    id_movimiento       INT             NOT NULL,
    id_proveedor        INT                 NULL,
    fecha_entrada       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    cantidad_ingresada  INT             NOT NULL,
    tipo_ingreso        VARCHAR(80)     NOT NULL,
    numero_lote         VARCHAR(50)         NULL,
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
-- Tabla SALIDA (detalle de egreso que no es venta: traslados, ajustes, etc.)
-- ------------------------------------------------------------
CREATE TABLE salida (
    id_salida           INT             NOT NULL AUTO_INCREMENT PRIMARY KEY,
    id_usuario          INT             NOT NULL,
    id_stock            INT             NOT NULL,
    id_movimiento       INT             NOT NULL,
    fecha_salida        DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    cantidad_salida     INT             NOT NULL,
    tipo_mov_salida     VARCHAR(80)         NULL,
    observaciones       TEXT                NULL,
    CONSTRAINT ck_salida_cantidad
        CHECK (cantidad_salida > 0),
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
-- Tabla VENTA (cabecera de venta a cliente, conectada a una salida)
-- ------------------------------------------------------------
CREATE TABLE venta (
    id_venta            INT             NOT NULL AUTO_INCREMENT PRIMARY KEY,
    id_cliente          INT             NOT NULL,
    id_usuario          INT             NOT NULL,
    id_salida           INT             NOT NULL,
    fecha_venta         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    observaciones       TEXT                NULL,
    CONSTRAINT fk_venta_cliente
        FOREIGN KEY (id_cliente) REFERENCES cliente (id_cliente)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_venta_usuario
        FOREIGN KEY (id_usuario) REFERENCES usuario (id_usuario)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_venta_salida
        FOREIGN KEY (id_salida) REFERENCES salida (id_salida)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

-- ------------------------------------------------------------
-- Tabla DEVOLUCION
-- ------------------------------------------------------------
CREATE TABLE devolucion (
    id_devolucion               INT             NOT NULL AUTO_INCREMENT PRIMARY KEY,
    id_stock                    INT             NOT NULL,
    id_movimiento_relacionado   INT             NOT NULL,
    id_bodega                   INT             NOT NULL,
    id_cliente                  INT             NOT NULL,
    id_usuario                  INT             NOT NULL,
    fecha_devolucion            DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    cantidad_devuelta           INT             NOT NULL,
    motivo_devolucion           VARCHAR(255)        NULL,
    estado_producto             ENUM('BUENO','DAÑADO','PARCIAL') NOT NULL DEFAULT 'BUENO',
    genera_entrada              TINYINT(1)      NOT NULL DEFAULT 0,
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
-- AJUSTES DE ESQUEMA (si aún no se han ejecutado)
-- ============================================================
ALTER TABLE salida
    ADD COLUMN IF NOT EXISTS lote VARCHAR(50) NULL AFTER tipo_mov_salida;

ALTER TABLE venta
    ADD COLUMN IF NOT EXISTS estado ENUM('ACTIVA','ANULADA') NOT NULL DEFAULT 'ACTIVA' AFTER observaciones;

-- ============================================================
-- TRIGGER: IMPEDIR MODIFICACIÓN DIRECTA DEL STOCK (RQF038)
-- ============================================================
DELIMITER //
CREATE OR REPLACE TRIGGER trg_stock_prevent_direct_update
BEFORE UPDATE ON stock
FOR EACH ROW
BEGIN
    IF @allow_stock_update IS NULL OR @allow_stock_update = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RQF038: No se permite modificar el stock directamente. Use un movimiento de inventario.';
    END IF;
END;
//
DELIMITER ;

-- ============================================================
-- TRIGGER: ACTUALIZAR STOCK AUTOMÁTICAMENTE (RQF033)
-- ============================================================
DELIMITER //
CREATE OR REPLACE TRIGGER trg_movimiento_inventario_after_insert
AFTER INSERT ON movimiento_inventario
FOR EACH ROW
BEGIN
    DECLARE v_signo INT DEFAULT 0;
    DECLARE v_id_stock INT;

    -- Determinar si el movimiento suma o resta al stock
    IF NEW.tipo_movimiento IN ('ENTRADA','DEVOLUCION') THEN
        SET v_signo = 1;
    ELSEIF NEW.tipo_movimiento IN ('SALIDA','AJUSTE','PERDIDA','DAÑO','VENTA') THEN
        SET v_signo = -1;
    ELSE
        -- TRASLADO se maneja manualmente (no se actualiza aquí)
        SET v_signo = 0;
    END IF;

    IF v_signo <> 0 THEN
        -- Obtener el id_stock correspondiente
        SELECT id_stock INTO v_id_stock
          FROM stock
         WHERE id_producto = NEW.id_producto
           AND id_bodega   = NEW.id_bodega
         LIMIT 1;

        IF v_id_stock IS NOT NULL THEN
            SET @allow_stock_update = 1;
            UPDATE stock
               SET cantidad_actual = cantidad_actual + (NEW.cantidad_bultos * v_signo),
                   fecha_ultima_auditoria = NOW()
             WHERE id_stock = v_id_stock;
            SET @allow_stock_update = 0;
        END IF;
    END IF;
END;
//
DELIMITER ;

-- ============================================================
-- PROCEDIMIENTOS PARA EL MÓDULO 6 – MOVIMIENTOS
-- ============================================================

-- RQF039: Registrar entrada
DELIMITER //
CREATE OR REPLACE PROCEDURE registrar_entrada(
    IN p_id_producto  INT,
    IN p_id_bodega    INT,
    IN p_cantidad     INT,
    IN p_id_usuario   INT,
    IN p_tipo_ingreso VARCHAR(80),
    IN p_numero_lote  VARCHAR(50),
    IN p_id_proveedor INT,
    IN p_observaciones TEXT
)
BEGIN
    DECLARE v_id_stock INT;
    DECLARE v_id_movimiento INT;

    IF p_cantidad <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RQF050: La cantidad debe ser mayor a cero.';
    END IF;

    START TRANSACTION;

    -- Obtener o crear el registro de stock
    SELECT id_stock INTO v_id_stock
      FROM stock
     WHERE id_producto = p_id_producto
       AND id_bodega   = p_id_bodega;

    IF v_id_stock IS NULL THEN
        INSERT INTO stock (id_producto, id_bodega, cantidad_actual, stock_minimo_seguridad, fecha_ultima_auditoria)
        VALUES (p_id_producto, p_id_bodega, 0, 0, NOW());
        SET v_id_stock = LAST_INSERT_ID();
    END IF;

    -- Insertar movimiento maestro
    INSERT INTO movimiento_inventario (id_producto, id_usuario, id_bodega, fecha_movimiento, tipo_movimiento, cantidad_bultos, observaciones)
    VALUES (p_id_producto, p_id_usuario, p_id_bodega, NOW(), 'ENTRADA', p_cantidad, p_observaciones);
    SET v_id_movimiento = LAST_INSERT_ID();

    -- Insertar entrada
    INSERT INTO entrada (id_stock, id_usuario, id_bodega, id_movimiento, id_proveedor, fecha_entrada, cantidad_ingresada, tipo_ingreso, numero_lote, observaciones)
    VALUES (v_id_stock, p_id_usuario, p_id_bodega, v_id_movimiento, p_id_proveedor, NOW(), p_cantidad, p_tipo_ingreso, p_numero_lote, p_observaciones);

    COMMIT;
    SELECT v_id_stock AS id_stock, v_id_movimiento AS id_movimiento;
END;
//
DELIMITER ;

-- RQF041: Registrar bultos extra (ajuste positivo)
DELIMITER //
CREATE OR REPLACE PROCEDURE registrar_ajuste_extra(
    IN p_id_producto  INT,
    IN p_id_bodega    INT,
    IN p_cantidad     INT,
    IN p_id_usuario   INT,
    IN p_observaciones TEXT
)
BEGIN
    CALL registrar_entrada(p_id_producto, p_id_bodega, p_cantidad, p_id_usuario, 'AJUSTE_EXTRA', NULL, NULL, p_observaciones);
END;
//
DELIMITER ;

-- RQF042: Registrar bultos faltantes (ajuste negativo)
DELIMITER //
CREATE OR REPLACE PROCEDURE registrar_ajuste_faltante(
    IN p_id_producto  INT,
    IN p_id_bodega    INT,
    IN p_cantidad     INT,
    IN p_id_usuario   INT,
    IN p_observaciones TEXT
)
BEGIN
    DECLARE v_id_stock INT;
    DECLARE v_id_movimiento INT;

    IF p_cantidad <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RQF050: Cantidad mayor a cero.';
    END IF;

    START TRANSACTION;

    SELECT id_stock INTO v_id_stock
      FROM stock
     WHERE id_producto = p_id_producto
       AND id_bodega   = p_id_bodega;

    IF v_id_stock IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No existe stock para ese producto en la bodega.';
    END IF;

    IF (SELECT cantidad_actual FROM stock WHERE id_stock = v_id_stock) < p_cantidad THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RQF046: Stock insuficiente para este ajuste.';
    END IF;

    INSERT INTO movimiento_inventario (id_producto, id_usuario, id_bodega, fecha_movimiento, tipo_movimiento, cantidad_bultos, observaciones)
    VALUES (p_id_producto, p_id_usuario, p_id_bodega, NOW(), 'AJUSTE', p_cantidad, p_observaciones);
    SET v_id_movimiento = LAST_INSERT_ID();

    INSERT INTO salida (id_usuario, id_stock, id_movimiento, fecha_salida, cantidad_salida, tipo_mov_salida, lote, observaciones)
    VALUES (p_id_usuario, v_id_stock, v_id_movimiento, NOW(), p_cantidad, 'AJUSTE_FALTANTE', NULL, p_observaciones);

    COMMIT;
END;
//
DELIMITER ;

-- RQF043: Registrar pérdida
DELIMITER //
CREATE OR REPLACE PROCEDURE registrar_perdida(
    IN p_id_producto  INT,
    IN p_id_bodega    INT,
    IN p_cantidad     INT,
    IN p_id_usuario   INT,
    IN p_observaciones TEXT
)
BEGIN
    DECLARE v_id_stock INT;
    DECLARE v_id_movimiento INT;

    IF p_cantidad <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RQF050: Cantidad mayor a cero.';
    END IF;

    START TRANSACTION;

    SELECT id_stock INTO v_id_stock
      FROM stock
     WHERE id_producto = p_id_producto
       AND id_bodega   = p_id_bodega;

    IF v_id_stock IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No existe stock para ese producto en la bodega.';
    END IF;

    IF (SELECT cantidad_actual FROM stock WHERE id_stock = v_id_stock) < p_cantidad THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RQF046: Stock insuficiente para registrar la pérdida.';
    END IF;

    INSERT INTO movimiento_inventario (id_producto, id_usuario, id_bodega, fecha_movimiento, tipo_movimiento, cantidad_bultos, observaciones)
    VALUES (p_id_producto, p_id_usuario, p_id_bodega, NOW(), 'PERDIDA', p_cantidad, p_observaciones);
    SET v_id_movimiento = LAST_INSERT_ID();

    INSERT INTO salida (id_usuario, id_stock, id_movimiento, fecha_salida, cantidad_salida, tipo_mov_salida, lote, observaciones)
    VALUES (p_id_usuario, v_id_stock, v_id_movimiento, NOW(), p_cantidad, 'PERDIDA', NULL, p_observaciones);

    COMMIT;
END;
//
DELIMITER ;

-- RQF044: Registrar daño
DELIMITER //
CREATE OR REPLACE PROCEDURE registrar_dano(
    IN p_id_producto  INT,
    IN p_id_bodega    INT,
    IN p_cantidad     INT,
    IN p_id_usuario   INT,
    IN p_observaciones TEXT
)
BEGIN
    DECLARE v_id_stock INT;
    DECLARE v_id_movimiento INT;

    IF p_cantidad <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RQF050: Cantidad mayor a cero.';
    END IF;

    START TRANSACTION;

    SELECT id_stock INTO v_id_stock
      FROM stock
     WHERE id_producto = p_id_producto
       AND id_bodega   = p_id_bodega;

    IF v_id_stock IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No existe stock para ese producto en la bodega.';
    END IF;

    IF (SELECT cantidad_actual FROM stock WHERE id_stock = v_id_stock) < p_cantidad THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RQF046: Stock insuficiente para registrar el daño.';
    END IF;

    INSERT INTO movimiento_inventario (id_producto, id_usuario, id_bodega, fecha_movimiento, tipo_movimiento, cantidad_bultos, observaciones)
    VALUES (p_id_producto, p_id_usuario, p_id_bodega, NOW(), 'DAÑO', p_cantidad, p_observaciones);
    SET v_id_movimiento = LAST_INSERT_ID();

    INSERT INTO salida (id_usuario, id_stock, id_movimiento, fecha_salida, cantidad_salida, tipo_mov_salida, lote, observaciones)
    VALUES (p_id_usuario, v_id_stock, v_id_movimiento, NOW(), p_cantidad, 'DAÑO', NULL, p_observaciones);

    COMMIT;
END;
//
DELIMITER ;

-- RQF045: Registrar traslado
DELIMITER //
CREATE OR REPLACE PROCEDURE registrar_traslado(
    IN p_id_producto      INT,
    IN p_id_bodega_origen  INT,
    IN p_id_bodega_destino INT,
    IN p_cantidad         INT,
    IN p_id_usuario       INT,
    IN p_observaciones    TEXT
)
BEGIN
    DECLARE v_id_stock_origen INT;
    DECLARE v_id_stock_destino INT;

    IF p_cantidad <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RQF050: Cantidad mayor a cero.';
    END IF;

    IF p_id_bodega_origen = p_id_bodega_destino THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RQF051: No se puede trasladar a la misma bodega.';
    END IF;

    START TRANSACTION;

    SELECT id_stock INTO v_id_stock_origen
      FROM stock
     WHERE id_producto = p_id_producto
       AND id_bodega   = p_id_bodega_origen;

    IF v_id_stock_origen IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No existe stock en la bodega de origen.';
    END IF;

    IF (SELECT cantidad_actual FROM stock WHERE id_stock = v_id_stock_origen) < p_cantidad THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RQF046: Stock insuficiente en la bodega de origen.';
    END IF;

    -- Destino: crear si no existe
    SELECT id_stock INTO v_id_stock_destino
      FROM stock
     WHERE id_producto = p_id_producto
       AND id_bodega   = p_id_bodega_destino;

    IF v_id_stock_destino IS NULL THEN
        INSERT INTO stock (id_producto, id_bodega, cantidad_actual, stock_minimo_seguridad, fecha_ultima_auditoria)
        VALUES (p_id_producto, p_id_bodega_destino, 0, 0, NOW());
        SET v_id_stock_destino = LAST_INSERT_ID();
    END IF;

    -- Ajuste manual de stock (no usamos el trigger porque involucra dos bodegas)
    SET @allow_stock_update = 1;

    -- Salida de origen
    UPDATE stock
       SET cantidad_actual = cantidad_actual - p_cantidad,
           fecha_ultima_auditoria = NOW()
     WHERE id_stock = v_id_stock_origen;

    -- Entrada en destino
    UPDATE stock
       SET cantidad_actual = cantidad_actual + p_cantidad,
           fecha_ultima_auditoria = NOW()
     WHERE id_stock = v_id_stock_destino;

    SET @allow_stock_update = 0;

    -- Registrar movimientos (no disparan actualización de stock porque el trigger los ignora con TRASLADO)
    INSERT INTO movimiento_inventario (id_producto, id_usuario, id_bodega, fecha_movimiento, tipo_movimiento, cantidad_bultos, observaciones)
    VALUES (p_id_producto, p_id_usuario, p_id_bodega_origen, NOW(), 'TRASLADO', p_cantidad, p_observaciones);

    INSERT INTO salida (id_usuario, id_stock, id_movimiento, fecha_salida, cantidad_salida, tipo_mov_salida, lote, observaciones)
    VALUES (p_id_usuario, v_id_stock_origen, LAST_INSERT_ID(), NOW(), p_cantidad, 'TRASLADO_SALIDA', NULL, p_observaciones);

    INSERT INTO movimiento_inventario (id_producto, id_usuario, id_bodega, fecha_movimiento, tipo_movimiento, cantidad_bultos, observaciones)
    VALUES (p_id_producto, p_id_usuario, p_id_bodega_destino, NOW(), 'TRASLADO', p_cantidad, p_observaciones);

    INSERT INTO entrada (id_stock, id_usuario, id_bodega, id_movimiento, id_proveedor, fecha_entrada, cantidad_ingresada, tipo_ingreso, numero_lote, observaciones)
    VALUES (v_id_stock_destino, p_id_usuario, p_id_bodega_destino, LAST_INSERT_ID(), NULL, NOW(), p_cantidad, 'TRASLADO_ENTRADA', NULL, p_observaciones);

    COMMIT;
END;
//
DELIMITER ;

-- ============================================================
-- PROCEDIMIENTOS PARA EL MÓDULO 7 – VENTAS
-- ============================================================

-- RQF052-056: Registrar venta
DELIMITER //
CREATE OR REPLACE PROCEDURE registrar_venta(
    IN p_id_cliente   INT,
    IN p_id_producto  INT,
    IN p_id_bodega    INT,
    IN p_lote         VARCHAR(50),
    IN p_cantidad     INT,
    IN p_id_usuario   INT,
    IN p_observaciones TEXT
)
BEGIN
    DECLARE v_id_stock INT;
    DECLARE v_id_movimiento INT;
    DECLARE v_id_salida INT;

    IF p_cantidad <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RQF050: Cantidad mayor a cero.';
    END IF;

    START TRANSACTION;

    SELECT id_stock INTO v_id_stock
      FROM stock
     WHERE id_producto = p_id_producto
       AND id_bodega   = p_id_bodega;

    IF v_id_stock IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No hay stock del producto en la bodega indicada.';
    END IF;

    IF (SELECT cantidad_actual FROM stock WHERE id_stock = v_id_stock) < p_cantidad THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RQF046/RQF055: Stock insuficiente para la venta.';
    END IF;

    -- Movimiento tipo VENTA (el trigger descuenta el stock)
    INSERT INTO movimiento_inventario (id_producto, id_usuario, id_bodega, fecha_movimiento, tipo_movimiento, cantidad_bultos, observaciones)
    VALUES (p_id_producto, p_id_usuario, p_id_bodega, NOW(), 'VENTA', p_cantidad, p_observaciones);
    SET v_id_movimiento = LAST_INSERT_ID();

    -- Salida asociada
    INSERT INTO salida (id_usuario, id_stock, id_movimiento, fecha_salida, cantidad_salida, tipo_mov_salida, lote, observaciones)
    VALUES (p_id_usuario, v_id_stock, v_id_movimiento, NOW(), p_cantidad, 'VENTA', p_lote, p_observaciones);
    SET v_id_salida = LAST_INSERT_ID();

    -- Venta cabecera
    INSERT INTO venta (id_cliente, id_usuario, id_salida, fecha_venta, observaciones, estado)
    VALUES (p_id_cliente, p_id_usuario, v_id_salida, NOW(), p_observaciones, 'ACTIVA');

    COMMIT;
    SELECT LAST_INSERT_ID() AS id_venta, v_id_salida AS id_salida, v_id_movimiento AS id_movimiento;
END;
//
DELIMITER ;

-- RQF058: Anular venta
DELIMITER //
CREATE OR REPLACE PROCEDURE anular_venta(
    IN p_id_venta    INT,
    IN p_id_usuario  INT,
    IN p_motivo      VARCHAR(255)
)
BEGIN
    DECLARE v_id_salida INT;
    DECLARE v_id_stock INT;
    DECLARE v_id_cliente INT;
    DECLARE v_id_bodega INT;
    DECLARE v_cantidad INT;
    DECLARE v_id_mov_original INT;

    START TRANSACTION;

    SELECT id_salida, id_cliente
      INTO v_id_salida, v_id_cliente
      FROM venta
     WHERE id_venta = p_id_venta
       AND estado = 'ACTIVA';

    IF v_id_salida IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La venta no existe o ya fue anulada.';
    END IF;

    SELECT id_stock, cantidad_salida, id_movimiento
      INTO v_id_stock, v_cantidad, v_id_mov_original
      FROM salida
     WHERE id_salida = v_id_salida;

    SELECT id_bodega INTO v_id_bodega
      FROM stock
     WHERE id_stock = v_id_stock;

    -- Marcar venta como anulada
    UPDATE venta SET estado = 'ANULADA' WHERE id_venta = p_id_venta;

    -- Devolución: reingresa el stock (el trigger suma porque tipo='DEVOLUCION')
    INSERT INTO movimiento_inventario (id_producto, id_usuario, id_bodega, fecha_movimiento, tipo_movimiento, cantidad_bultos, observaciones)
    SELECT id_producto, p_id_usuario, v_id_bodega, NOW(), 'DEVOLUCION', v_cantidad, CONCAT('Anulación venta ', p_id_venta, '. Motivo: ', p_motivo)
      FROM stock WHERE id_stock = v_id_stock;

    SET @id_mov_dev = LAST_INSERT_ID();

    INSERT INTO devolucion (id_stock, id_movimiento_relacionado, id_bodega, id_cliente, id_usuario,
                            fecha_devolucion, cantidad_devuelta, motivo_devolucion, estado_producto, genera_entrada, observaciones)
    VALUES (v_id_stock, v_id_mov_original, v_id_bodega, v_id_cliente, p_id_usuario,
            NOW(), v_cantidad, p_motivo, 'BUENO', 1, CONCAT('Anulación venta ', p_id_venta));

    COMMIT;
END;
//
DELIMITER ;

-- ============================================================
-- MÓDULO 5 – STOCK (mínimos de seguridad)
-- ============================================================

-- RQF034 / RQF035: Actualizar stock mínimo
DELIMITER //
CREATE OR REPLACE PROCEDURE actualizar_stock_minimo(
    IN p_id_producto INT,
    IN p_id_bodega   INT,
    IN p_nuevo_minimo INT
)
BEGIN
    UPDATE stock
       SET stock_minimo_seguridad = p_nuevo_minimo
     WHERE id_producto = p_id_producto
       AND id_bodega   = p_id_bodega;

    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No existe el par producto/bodega.';
    END IF;
END;
//
DELIMITER ;

-- ============================================================
-- VISTAS DE CONSULTA
-- ============================================================
CREATE OR REPLACE VIEW vista_stock_detallado AS
SELECT p.id_producto, p.nombre_sal_mineralizada, b.id_bodega, b.nombre_bodega,
       s.cantidad_actual, s.stock_minimo_seguridad,
       CASE WHEN s.cantidad_actual <= s.stock_minimo_seguridad THEN 'BAJO' ELSE 'OK' END AS alerta
  FROM stock s
  JOIN producto p ON s.id_producto = p.id_producto
  JOIN bodega b  ON s.id_bodega   = b.id_bodega;

CREATE OR REPLACE VIEW vista_total_por_producto AS
SELECT p.id_producto, p.nombre_sal_mineralizada, SUM(s.cantidad_actual) AS total_bultos
  FROM stock s
  JOIN producto p ON s.id_producto = p.id_producto
 GROUP BY p.id_producto, p.nombre_sal_mineralizada;

CREATE OR REPLACE VIEW vista_total_por_bodega AS
SELECT b.id_bodega, b.nombre_bodega, SUM(s.cantidad_actual) AS total_bultos
  FROM stock s
  JOIN bodega b ON s.id_bodega = b.id_bodega
 GROUP BY b.id_bodega, b.nombre_bodega;

CREATE OR REPLACE VIEW vista_ventas AS
SELECT v.id_venta, v.fecha_venta, c.nombre_cliente, p.nombre_sal_mineralizada,
       b.nombre_bodega, sa.lote, sa.cantidad_salida AS cantidad, v.estado,
       u.nombre_completo AS vendedor
  FROM venta v
  JOIN cliente c ON v.id_cliente = c.id_cliente
  JOIN salida sa ON v.id_salida = sa.id_salida
  JOIN stock st ON sa.id_stock = st.id_stock
  JOIN producto p ON st.id_producto = p.id_producto
  JOIN bodega b ON st.id_bodega = b.id_bodega
  JOIN usuario u ON v.id_usuario = u.id_usuario;
