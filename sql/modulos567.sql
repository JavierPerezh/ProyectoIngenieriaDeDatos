USE salinas_del_cravo;

DELIMITER $$

-- TRIGGERS DE STOCK (sin cambios)
CREATE TRIGGER trg_movimiento_stock_bodega AFTER INSERT ON movimiento_inventario
FOR EACH ROW
BEGIN
    IF NEW.tipo_movimiento = 'ENTRADA' THEN
        INSERT INTO stock_bodega (id_bodega, id_producto, id_lote, cantidad_actual)
        VALUES (NEW.id_bodega, NEW.id_producto, NEW.id_lote, NEW.cantidad)
        ON DUPLICATE KEY UPDATE cantidad_actual = cantidad_actual + NEW.cantidad;
    ELSEIF NEW.tipo_movimiento = 'SALIDA' THEN
        UPDATE stock_bodega SET cantidad_actual = cantidad_actual - NEW.cantidad
        WHERE id_bodega = NEW.id_bodega AND id_producto = NEW.id_producto AND id_lote = NEW.id_lote;
    END IF;
END$$

CREATE TRIGGER trg_movimiento_stock_tienda AFTER INSERT ON movimiento_inventario
FOR EACH ROW
BEGIN
    IF NEW.tipo_movimiento = 'ABASTECIMIENTO' THEN
        INSERT INTO stock_tienda (id_tienda, id_producto, id_lote, cantidad_actual)
        VALUES (NEW.id_tienda, NEW.id_producto, NEW.id_lote, NEW.cantidad)
        ON DUPLICATE KEY UPDATE cantidad_actual = cantidad_actual + NEW.cantidad;
    ELSEIF NEW.tipo_movimiento = 'VENTA' THEN
        UPDATE stock_tienda SET cantidad_actual = cantidad_actual - NEW.cantidad
        WHERE id_tienda = NEW.id_tienda AND id_producto = NEW.id_producto AND id_lote = NEW.id_lote;
    ELSEIF NEW.tipo_movimiento = 'DEVOLUCION' THEN
        UPDATE stock_tienda SET cantidad_actual = cantidad_actual + NEW.cantidad
        WHERE id_tienda = NEW.id_tienda AND id_producto = NEW.id_producto AND id_lote = NEW.id_lote;
    END IF;
END$$

-- MÓDULO 5: CONSULTAS DE STOCK (sin cambios)
CREATE PROCEDURE sp_ver_stock(IN p_id_producto INT)
BEGIN
    SELECT 'BODEGA' origen, b.nombre_bodega ubicacion, sb.cantidad_actual
    FROM stock_bodega sb JOIN bodega b ON b.id_bodega = sb.id_bodega
    WHERE sb.id_producto = p_id_producto
    UNION ALL
    SELECT 'TIENDA', t.nombre_tienda, st.cantidad_actual
    FROM stock_tienda st JOIN tienda t ON t.id_tienda = st.id_tienda
    WHERE st.id_producto = p_id_producto;
END$$

-- MÓDULO 6: MOVIMIENTOS

-- Entrada manual
CREATE PROCEDURE sp_entrada_manual(IN p_id_producto INT, IN p_id_lote INT,
    IN p_id_bodega INT, IN p_cantidad INT, IN p_id_usuario INT,
    IN p_tipo ENUM('PRODUCCION','TRANSFERENCIA','AJUSTE_EXTRA'))
BEGIN
    INSERT INTO movimiento_inventario (id_producto, id_lote, id_usuario, tipo_movimiento, cantidad, id_bodega)
    VALUES (p_id_producto, p_id_lote, p_id_usuario, 'ENTRADA', p_cantidad, p_id_bodega);
    INSERT INTO entrada (id_movimiento, tipo_ingreso) VALUES (LAST_INSERT_ID(), p_tipo);
END$$

-- Salida manual (con validación de stock)
CREATE PROCEDURE sp_salida_manual(IN p_id_producto INT, IN p_id_lote INT,
    IN p_id_bodega INT, IN p_cantidad INT, IN p_id_usuario INT,
    IN p_tipo ENUM('TRANSFERENCIA','FALTANTE','PERDIDA','DAÑO'))
BEGIN
    DECLARE v_stock_actual INT;
    SELECT cantidad_actual INTO v_stock_actual
    FROM stock_bodega
    WHERE id_bodega = p_id_bodega AND id_producto = p_id_producto AND id_lote = p_id_lote;

    IF v_stock_actual IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No existe stock en esta bodega para el producto/lote';
    END IF;
    IF v_stock_actual < p_cantidad THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Stock insuficiente para realizar la salida';
    END IF;

    INSERT INTO movimiento_inventario (id_producto, id_lote, id_usuario, tipo_movimiento, cantidad, id_bodega)
    VALUES (p_id_producto, p_id_lote, p_id_usuario, 'SALIDA', p_cantidad, p_id_bodega);
    INSERT INTO salida (id_movimiento, tipo_salida) VALUES (LAST_INSERT_ID(), p_tipo);
END$$

-- Transferencia entre bodegas
CREATE PROCEDURE sp_transferir_entre_bodegas(IN p_id_producto INT, IN p_id_lote INT,
    IN p_origen INT, IN p_destino INT, IN p_cantidad INT, IN p_id_usuario INT)
BEGIN
    IF p_origen = p_destino THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Mismo origen y destino';
    END IF;
    START TRANSACTION;
        CALL sp_salida_manual(p_id_producto, p_id_lote, p_origen, p_cantidad, p_id_usuario, 'TRANSFERENCIA');
        CALL sp_entrada_manual(p_id_producto, p_id_lote, p_destino, p_cantidad, p_id_usuario, 'TRANSFERENCIA');
    COMMIT;
END$$

-- Abastecer tienda (bodega a tienda)
CREATE PROCEDURE sp_abastecer_tienda(IN p_id_producto INT, IN p_id_lote INT,
    IN p_id_bodega INT, IN p_id_tienda INT, IN p_cantidad INT, IN p_id_usuario INT)
BEGIN
    START TRANSACTION;
        CALL sp_salida_manual(p_id_producto, p_id_lote, p_id_bodega, p_cantidad, p_id_usuario, 'TRANSFERENCIA');
        INSERT INTO movimiento_inventario (id_producto, id_lote, id_usuario, tipo_movimiento, cantidad, id_tienda)
        VALUES (p_id_producto, p_id_lote, p_id_usuario, 'ABASTECIMIENTO', p_cantidad, p_id_tienda);
    COMMIT;
END$$

-- MÓDULO 7: VENTAS

-- Registrar venta (versión corregida que evita el error de CONCAT)
CREATE PROCEDURE sp_registrar_venta(
    IN p_id_cliente INT, IN p_id_tienda INT,
    IN p_id_usuario INT, IN p_items JSON
)
BEGIN
    DECLARE v_id_venta INT;
    DECLARE v_idx INT DEFAULT 0;
    DECLARE v_len INT DEFAULT JSON_LENGTH(p_items);
    DECLARE v_item JSON;
    DECLARE v_id_producto INT;
    DECLARE v_id_lote INT;
    DECLARE v_cantidad INT;
    DECLARE v_stock_actual INT;
    DECLARE v_msg VARCHAR(255);

    START TRANSACTION;
    -- Validar stock para todos los ítems
    WHILE v_idx < v_len DO
        SET v_item = JSON_EXTRACT(p_items, CONCAT('$[', v_idx, ']'));
        SET v_id_producto = JSON_UNQUOTE(JSON_EXTRACT(v_item, '$.id_producto'));
        SET v_id_lote = JSON_UNQUOTE(JSON_EXTRACT(v_item, '$.id_lote'));
        SET v_cantidad = JSON_UNQUOTE(JSON_EXTRACT(v_item, '$.cantidad'));

        SELECT cantidad_actual INTO v_stock_actual
        FROM stock_tienda
        WHERE id_tienda = p_id_tienda AND id_producto = v_id_producto AND id_lote = v_id_lote;

        IF v_stock_actual IS NULL OR v_stock_actual < v_cantidad THEN
            SET v_msg = CONCAT('Stock insuficiente en tienda para producto ', v_id_producto, ' lote ', v_id_lote);
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
        END IF;
        SET v_idx = v_idx + 1;
    END WHILE;

    -- Insertar venta
    INSERT INTO venta (id_cliente, id_usuario, id_tienda) VALUES (p_id_cliente, p_id_usuario, p_id_tienda);
    SET v_id_venta = LAST_INSERT_ID();

    -- Insertar detalles y movimientos de venta
    SET v_idx = 0;
    WHILE v_idx < v_len DO
        SET v_item = JSON_EXTRACT(p_items, CONCAT('$[', v_idx, ']'));
        INSERT INTO movimiento_inventario (id_producto, id_lote, id_usuario, tipo_movimiento, cantidad, id_tienda)
        VALUES (JSON_UNQUOTE(JSON_EXTRACT(v_item, '$.id_producto')),
                JSON_UNQUOTE(JSON_EXTRACT(v_item, '$.id_lote')),
                p_id_usuario, 'VENTA',
                JSON_UNQUOTE(JSON_EXTRACT(v_item, '$.cantidad')),
                p_id_tienda);
        INSERT INTO venta_detalle (id_venta, id_producto, id_lote, cantidad, id_movimiento)
        VALUES (v_id_venta,
                JSON_UNQUOTE(JSON_EXTRACT(v_item, '$.id_producto')),
                JSON_UNQUOTE(JSON_EXTRACT(v_item, '$.id_lote')),
                JSON_UNQUOTE(JSON_EXTRACT(v_item, '$.cantidad')),
                LAST_INSERT_ID());
        SET v_idx = v_idx + 1;
    END WHILE;
    COMMIT;
    SELECT v_id_venta id_venta;
END$$

-- Anular venta (ya corregida, se deja igual)
CREATE PROCEDURE sp_anular_venta(
    IN p_id_venta INT, IN p_id_usuario INT, IN p_motivo VARCHAR(255)
)
BEGIN
    DECLARE v_id_mov INT;
    DECLARE v_producto INT;
    DECLARE v_lote INT;
    DECLARE v_cantidad INT;
    DECLARE v_tienda INT;
    DECLARE done INT DEFAULT FALSE;
    DECLARE cur CURSOR FOR
        SELECT vd.id_producto, vd.id_lote, vd.cantidad, mi.id_tienda
        FROM venta_detalle vd
        JOIN movimiento_inventario mi ON mi.id_movimiento = vd.id_movimiento
        WHERE vd.id_venta = p_id_venta;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    START TRANSACTION;
        UPDATE venta SET estado = 'ANULADA' WHERE id_venta = p_id_venta AND estado = 'ACTIVA';
        OPEN cur;
        read_loop: LOOP
            FETCH cur INTO v_producto, v_lote, v_cantidad, v_tienda;
            IF done THEN LEAVE read_loop; END IF;

            INSERT INTO movimiento_inventario (id_producto, id_lote, id_usuario, tipo_movimiento, cantidad, id_tienda, observaciones)
            VALUES (v_producto, v_lote, p_id_usuario, 'DEVOLUCION', v_cantidad, v_tienda,
                    CONCAT('Anulación venta ', p_id_venta, ': ', p_motivo));
            SET v_id_mov = LAST_INSERT_ID();
            INSERT INTO devolucion_detalle (id_producto, id_lote, cantidad_devuelta, id_movimiento)
            VALUES (v_producto, v_lote, v_cantidad, v_id_mov);
        END LOOP;
        CLOSE cur;
    COMMIT;
END$$

DELIMITER ;
