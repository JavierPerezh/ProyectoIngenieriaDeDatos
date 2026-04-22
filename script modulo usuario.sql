USE salinas_del_cravo;

-- ============================================================
-- CONSULTAS
-- ============================================================

-- ------------------------------------------------------------
-- CONSULTA BÁSICA [RQF002]
-- Listar todos los usuarios registrados en el sistema
-- ------------------------------------------------------------
SELECT
    id_usuario,
    nombre_completo,
    username,
    rol,
    estado_activo
FROM usuario
ORDER BY rol, nombre_completo;


-- ------------------------------------------------------------
-- CONSULTA 1 [RQF002]
-- Buscar un usuario específico por su username
-- ------------------------------------------------------------
SELECT
    id_usuario,
    nombre_completo,
    username,
    rol,
    estado_activo
FROM usuario
WHERE username = 'afmorales';


-- ------------------------------------------------------------
-- CONSULTA 2 [RQF007]
-- Listar únicamente los administradores activos del sistema
-- ------------------------------------------------------------
SELECT
    u.id_usuario,
    u.nombre_completo,
    u.username,
    a.ultimo_acceso_admin
FROM usuario u
INNER JOIN administrador a ON u.id_usuario = a.id_usuario
WHERE u.estado_activo = 1
ORDER BY u.nombre_completo;


-- ------------------------------------------------------------
-- CONSULTA 3 [RQF007]
-- Listar únicamente los vendedores activos con su terminal
-- ------------------------------------------------------------
SELECT
    u.id_usuario,
    u.nombre_completo,
    u.username,
    v.codigo_terminal,
    v.ventas_mes_actual
FROM usuario u
INNER JOIN vendedor v ON u.id_usuario = v.id_usuario
WHERE u.estado_activo = 1
ORDER BY v.ventas_mes_actual DESC;


-- ------------------------------------------------------------
-- CONSULTA 4 [RQF004]
-- Listar usuarios inactivos (acceso deshabilitado)
-- Evidencia que el historial se conserva (RQF004: sin borrar)
-- ------------------------------------------------------------
SELECT
    id_usuario,
    nombre_completo,
    username,
    rol
FROM usuario
WHERE estado_activo = 0
ORDER BY nombre_completo;


-- ------------------------------------------------------------
-- CONSULTA 5 [RQF005]
-- Autenticación: validar credenciales de ingreso
-- Retorna datos del usuario si username + password coinciden
-- ------------------------------------------------------------
SELECT
    id_usuario,
    nombre_completo,
    rol,
    estado_activo
FROM usuario
WHERE username = 'afmorales'
  AND password_hash = SHA2('Vend2026#', 256)
  AND estado_activo = 1;


-- ------------------------------------------------------------
-- CONSULTA 6 [RQF007]
-- Resumen de usuarios agrupados por rol
-- Muestra cuántos activos e inactivos hay por cada rol
-- ------------------------------------------------------------
SELECT
    rol,
    SUM(CASE WHEN estado_activo = 1 THEN 1 ELSE 0 END) AS activos,
    SUM(CASE WHEN estado_activo = 0 THEN 1 ELSE 0 END) AS inactivos,
    COUNT(*) AS total FROM usuario GROUP BY rol ORDER BY rol;
    
-- ------------------------------------------------------------
-- CONSULTA 7 — SUBCONSULTA [RQF002 + RQF007]
-- Usuarios que NUNCA han registrado un movimiento de inventario
-- Útil para auditoría y control de acceso real al sistema
-- ------------------------------------------------------------
SELECT
    u.id_usuario,
    u.nombre_completo,
    u.username,
    u.rol
FROM usuario u
WHERE u.id_usuario NOT IN (
    SELECT DISTINCT id_usuario
    FROM movimiento_inventario
)
ORDER BY u.rol, u.nombre_completo;


-- ============================================================
-- BLOQUE 2 — MODIFICACIONES  (5 UPDATE + 1 DELETE)
-- ============================================================

-- ------------------------------------------------------------
-- MODIFICACIÓN 1 [RQF003]
-- Actualizar el nombre completo de un usuario
-- ------------------------------------------------------------
SET SQL_SAFE_UPDATES = 0;

UPDATE usuario
SET nombre_completo = 'Andrés Felipe Morales Cruz Actualizado'
WHERE username = 'afmorales';

SET SQL_SAFE_UPDATES = 1;


-- ------------------------------------------------------------
-- MODIFICACIÓN 2 [RQF003]
-- Actualizar el código de terminal de un vendedor
-- ------------------------------------------------------------
SET SQL_SAFE_UPDATES = 0;

UPDATE vendedor
SET codigo_terminal = 'TRM-001-B'
WHERE codigo_terminal = 'TRM-001';

SET SQL_SAFE_UPDATES = 1;

-- ------------------------------------------------------------
-- MODIFICACIÓN 3 [RQF004]
-- Inactivar un usuario: deshabilita acceso SIN eliminar historial
-- ------------------------------------------------------------
SET SQL_SAFE_UPDATES = 0;

UPDATE usuario
SET estado_activo = 0
WHERE username = 'afmorales';

SET SQL_SAFE_UPDATES = 1;


-- ------------------------------------------------------------
-- MODIFICACIÓN 4 [RQF004]
-- Reactivar un usuario previamente inactivado
-- ------------------------------------------------------------
SET SQL_SAFE_UPDATES = 0;

UPDATE usuario
SET estado_activo = 1
WHERE username = 'afmorales';

SET SQL_SAFE_UPDATES = 1;


-- ------------------------------------------------------------
-- MODIFICACIÓN 5 [RQF003]
-- Resetear el contador de ventas del mes a un vendedor
-- ------------------------------------------------------------
SET SQL_SAFE_UPDATES = 0;

UPDATE vendedor
SET ventas_mes_actual = 0
WHERE codigo_terminal = 'TRM-001-B';

SET SQL_SAFE_UPDATES = 1;


-- ------------------------------------------------------------
-- ELIMINACIÓN 1 [RQF001]
-- Eliminar un usuario que fue registrado por error
-- NOTA: solo es posible si el usuario NO tiene movimientos
-- asociados en movimiento_inventario.
-- Para usuarios con historial se usa INACTIVAR (RQF004).
-- ------------------------------------------------------------
DELETE FROM usuario
WHERE username = 'usuario_prueba_borrar'
  AND id_usuario NOT IN (
      SELECT DISTINCT id_usuario FROM movimiento_inventario
  );
  
-- ============================================================
-- BLOQUE 3 — VISTAS
-- ============================================================
-- ------------------------------------------------------------
-- VISTA 1 [RQF002 + RQF007]
-- Vista general de usuarios con su rol detallado
-- Muestra todos los usuarios y a qué especialización pertenecen
-- ------------------------------------------------------------
DROP VIEW IF EXISTS vista_usuarios_sistema;

CREATE VIEW vista_usuarios_sistema AS
SELECT
    u.id_usuario,
    u.nombre_completo,
    u.username,
    u.rol,
    u.estado_activo,
    CASE u.rol
        WHEN 'ADMIN' THEN a.ultimo_acceso_admin
        ELSE NULL
    END AS ultimo_acceso_admin,
    CASE u.rol
        WHEN 'VENDEDOR' THEN v.codigo_terminal
        ELSE NULL
    END AS codigo_terminal,
    CASE u.rol
        WHEN 'VENDEDOR' THEN v.ventas_mes_actual
        ELSE NULL
    END AS ventas_mes_actual
FROM usuario u
LEFT JOIN administrador a ON u.id_usuario = a.id_usuario
LEFT JOIN vendedor       v ON u.id_usuario = v.id_usuario;

-- Consultar la vista:
SELECT * FROM vista_usuarios_sistema ORDER BY rol, nombre_completo;

-- ------------------------------------------------------------
-- VISTA 2 [RQF005 + RQF007]
-- Vista de acceso activo
-- Esta vista es la que consulta el sistema en el proceso de login
-- ------------------------------------------------------------
DROP VIEW IF EXISTS vista_usuarios_activos;

CREATE VIEW vista_usuarios_activos AS
SELECT
    id_usuario,
    nombre_completo,
    username,
    password_hash,
    rol
FROM usuario
WHERE estado_activo = 1;

-- Consultar la vista:
SELECT id_usuario, nombre_completo, username, rol
FROM vista_usuarios_activos
ORDER BY rol, nombre_completo;


-- ============================================================
-- BLOQUE 4 — PROCEDIMIENTOS ALMACENADOS
-- ============================================================

-- ------------------------------------------------------------
-- PROCEDIMIENTO 1 [RQF001]
-- Registrar un nuevo usuario en el sistema
-- Inserta en usuario y en su tabla de especialización (ADMIN o VENDEDOR)
-- ------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_registrar_usuario;

DELIMITER $$
CREATE PROCEDURE sp_registrar_usuario(
    IN  p_nombre_completo   VARCHAR(150),
    IN  p_username VARCHAR(60),
    IN  p_password VARCHAR(255),
    IN  p_rol ENUM('ADMIN','VENDEDOR'),
    IN  p_codigo_terminal VARCHAR(20),  
    OUT p_id_nuevo INT,
    OUT p_mensaje VARCHAR(255)
)
BEGIN
    DECLARE v_existe INT DEFAULT 0;

    -- Verificar que el username no esté ya registrado
    SELECT COUNT(*) INTO v_existe
    FROM usuario
    WHERE username = p_username;

    IF v_existe > 0 THEN
        SET p_id_nuevo = NULL;
        SET p_mensaje  = CONCAT('ERROR: El username "', p_username, '" ya existe en el sistema.');
    ELSE
        -- Insertar en tabla base usuario
        INSERT INTO usuario (nombre_completo, username, password_hash, estado_activo, rol)
        VALUES (p_nombre_completo, p_username, SHA2(p_password, 256), 1, p_rol);

        SET p_id_nuevo = LAST_INSERT_ID();

        -- Insertar en tabla de especialización según rol
        IF p_rol = 'ADMIN' THEN
            INSERT INTO administrador (id_usuario, ultimo_acceso_admin)
            VALUES (p_id_nuevo, NULL);
        ELSE
            INSERT INTO vendedor (id_usuario, codigo_terminal, ventas_mes_actual)
            VALUES (p_id_nuevo, p_codigo_terminal, 0);
        END IF;

        SET p_mensaje = CONCAT('OK: Usuario "', p_username, '" registrado con ID ', p_id_nuevo, '.');
    END IF;
END$$
DELIMITER ;

-- Llamado de prueba:
CALL sp_registrar_usuario(
    'Prueba Registro Usuario', 'prueba_usr', 'Clave2026!',
    'VENDEDOR', 'TRM-099',
    @nuevo_id, @msg
);
SELECT @nuevo_id AS id_generado, @msg AS resultado;


-- ------------------------------------------------------------
-- PROCEDIMIENTO 2 [RQF005]
-- Autenticar usuario: valida credenciales y registra último acceso
-- Retorna los datos del usuario si el login es exitoso
-- ------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_autenticar_usuario;

DELIMITER $$
CREATE PROCEDURE sp_autenticar_usuario(
    IN  p_username  VARCHAR(60),
    IN  p_password  VARCHAR(255),
    OUT p_resultado VARCHAR(50)
)
BEGIN
    DECLARE v_id INT DEFAULT NULL;
    DECLARE v_activo TINYINT DEFAULT 0;
    DECLARE v_rol VARCHAR(20);

    SELECT id_usuario, estado_activo, rol
    INTO v_id, v_activo, v_rol
    FROM  usuario
    WHERE username = p_username
      AND password_hash = SHA2(p_password, 256)
    LIMIT 1;

    IF v_id IS NULL THEN
        SET p_resultado = 'CREDENCIALES_INVALIDAS';
    ELSEIF v_activo = 0 THEN
        SET p_resultado = 'USUARIO_INACTIVO';
    ELSE
        -- Registrar último acceso si es administrador
        IF v_rol = 'ADMIN' THEN
            UPDATE administrador
            SET ultimo_acceso_admin = NOW()
            WHERE id_usuario = v_id;
        END IF;

        SET p_resultado = CONCAT('LOGIN_OK|', v_id, '|', v_rol);

        -- Retornar datos del usuario autenticado
        SELECT id_usuario, nombre_completo, rol
        FROM   usuario
        WHERE  id_usuario = v_id;
    END IF;
END$$
DELIMITER ;

-- Llamado de prueba — credenciales correctas:
CALL sp_autenticar_usuario('afmorales', 'Vend2026#', @res);
SELECT @res AS resultado_login;

-- Llamado de prueba — credenciales incorrectas:
CALL sp_autenticar_usuario('afmorales', 'ClaveErronea', @res);
SELECT @res AS resultado_login;


-- ============================================================
-- BLOQUE 5 — TRIGGERS
-- ============================================================

-- ------------------------------------------------------------
-- TRIGGER 1 [RQF004]
-- Antes de ELIMINAR un usuario, verificar que no tenga
-- movimientos de inventario asociados.
-- Si los tiene, lanza un error y cancela la eliminación.
-- Esto protege la trazabilidad del sistema.
-- ------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_before_delete_usuario;

DELIMITER $$
CREATE TRIGGER trg_before_delete_usuario
BEFORE DELETE ON usuario
FOR EACH ROW
BEGIN
    DECLARE v_mov INT DEFAULT 0;

    SELECT COUNT(*) INTO v_mov
    FROM movimiento_inventario
    WHERE id_usuario = OLD.id_usuario;

    IF v_mov > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'No se puede eliminar el usuario: tiene movimientos de inventario registrados. Use INACTIVAR (RQF004).';
    END IF;
END$$
DELIMITER ;

-- Prueba del trigger — debe lanzar error:

-- ------------------------------------------------------------
-- TRIGGER 2 [RQF001]
-- Después de insertar un nuevo usuario, registrar automáticamente
-- en su tabla de especialización si no se hizo manualmente.
-- Aplica solo si el rol es ADMIN y no existe aún en administrador.
-- ------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_after_insert_usuario_admin;

DELIMITER $$
CREATE TRIGGER trg_after_insert_usuario_admin
AFTER INSERT ON usuario
FOR EACH ROW
BEGIN
    DECLARE v_existe INT DEFAULT 0;

    IF NEW.rol = 'ADMIN' THEN
        SELECT COUNT(*) INTO v_existe
        FROM administrador
        WHERE id_usuario = NEW.id_usuario;

        IF v_existe = 0 THEN
            INSERT INTO administrador (id_usuario, ultimo_acceso_admin)
            VALUES (NEW.id_usuario, NULL);
        END IF;
    END IF;
END$$
DELIMITER ;

-- Prueba del trigger — insertar admin y verificar que se crea en administrador:
INSERT INTO usuario (nombre_completo, username, password_hash, estado_activo, rol)
VALUES ('Admin Trigger Test', 'admin_trigger_test', SHA2('Test2026!', 256), 1, 'ADMIN');

SELECT u.id_usuario, u.username, u.rol, a.ultimo_acceso_admin
FROM usuario u
INNER JOIN administrador a ON u.id_usuario = a.id_usuario
WHERE u.username = 'admin_trigger_test';


-- ============================================================
-- BLOQUE 6 — CONSULTAS MULTITABLA
-- ============================================================

-- ------------------------------------------------------------
-- MULTITABLA 1 [RQF002 + RQF007]
-- Cruce usuario + especialización: lista completa de todos
-- los usuarios con los datos de su rol correspondiente
-- ------------------------------------------------------------
SELECT
    u.id_usuario,
    u.nombre_completo,
    u.username,
    u.rol,
    u.estado_activo,
    COALESCE(v.codigo_terminal, 'N/A') AS terminal,
    COALESCE(v.ventas_mes_actual, 0)     AS ventas_mes,
    COALESCE(a.ultimo_acceso_admin, 'Sin acceso aún') AS ultimo_acceso
FROM usuario u
LEFT JOIN vendedor v ON u.id_usuario = v.id_usuario
LEFT JOIN administrador a ON u.id_usuario = a.id_usuario
ORDER BY u.rol, u.estado_activo DESC, u.nombre_completo;


-- ------------------------------------------------------------
-- MULTITABLA 2 [RQF002 + RQF007]
-- Vendedores con al menos un movimiento de inventario registrado
-- Cruza usuario + vendedor + movimiento_inventario
-- ------------------------------------------------------------
SELECT
    u.id_usuario,
    u.nombre_completo,
    v.codigo_terminal,
    COUNT(m.id_movimiento) AS total_movimientos,
    MAX(m.timestamp_mov) AS ultimo_movimiento
FROM usuario u
INNER JOIN vendedor v ON u.id_usuario = v.id_usuario
INNER JOIN movimiento_inventario m ON u.id_usuario = m.id_usuario
GROUP BY u.id_usuario, u.nombre_completo, v.codigo_terminal
ORDER BY total_movimientos DESC;
