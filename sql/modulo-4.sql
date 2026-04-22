-- ============================================================
-- 1. CREACIÓN DE LA BASE DE DATOS
-- ============================================================
DROP DATABASE IF EXISTS salinas_del_cravo;
CREATE DATABASE salinas_del_cravo
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;
 
USE salinas_del_cravo;
 
 
-- ============================================================
-- 2. DDL — CREACIÓN DE TABLAS
-- ============================================================
 
-- ------------------------------------------------------------
-- 2.1  CATEGORIA
-- Catálogo de líneas de sal mineralizada según % de fósforo.
-- ------------------------------------------------------------
CREATE TABLE categoria (
    id_categoria        INT             NOT NULL AUTO_INCREMENT,
    nombre_categoria    VARCHAR(100)    NOT NULL,
    descripcion_uso     VARCHAR(255)    NOT NULL,
    porcentaje_fosforo  DECIMAL(4,1)    NOT NULL,
    CONSTRAINT pk_categoria PRIMARY KEY (id_categoria),
    CONSTRAINT uq_categoria_nombre UNIQUE (nombre_categoria)
);
 
-- ------------------------------------------------------------
-- 2.2  PRODUCTO
-- Cada combinación concentración × presentación es un producto.
-- ------------------------------------------------------------
CREATE TABLE producto (
    id_producto             INT             NOT NULL AUTO_INCREMENT,
    id_categoria            INT             NOT NULL,
    nombre_sal_mineralizada VARCHAR(150)    NOT NULL,
    peso_bulto_kg           DECIMAL(6,2)    NOT NULL,
    unidad_medida           VARCHAR(50)     NOT NULL   COMMENT 'kg, 5kg, granel, mochila',
    paquetes_por_bulto      INT             NOT NULL   COMMENT 'Unidades empacadas dentro del bulto',
    descontinuado           TINYINT(1)      NOT NULL   DEFAULT 0,
    CONSTRAINT pk_producto  PRIMARY KEY (id_producto),
    CONSTRAINT fk_producto_categoria
        FOREIGN KEY (id_categoria) REFERENCES categoria (id_categoria)
        ON UPDATE CASCADE ON DELETE RESTRICT
);
 
-- ------------------------------------------------------------
-- 2.3  INVENTARIO
-- Representa cada sede / bodega física de la empresa.
-- ------------------------------------------------------------
CREATE TABLE inventario (
    id_inventario           INT             NOT NULL AUTO_INCREMENT,
    nombre_sede             VARCHAR(100)    NOT NULL,
    direccion_fisica        VARCHAR(255)    NOT NULL,
    capacidad_maxima_bultos INT             NOT NULL,
    estado_operativo        TINYINT(1)      NOT NULL DEFAULT 1,
    CONSTRAINT pk_inventario PRIMARY KEY (id_inventario)
);
 
-- ------------------------------------------------------------
-- 2.4  STOCK
-- Nivel actual de existencias de cada producto en cada bodega.
-- ------------------------------------------------------------
CREATE TABLE stock (
    id_stock                INT             NOT NULL AUTO_INCREMENT,
    id_producto             INT             NOT NULL,
    id_inventario           INT             NOT NULL,
    cantidad_actual         INT             NOT NULL DEFAULT 0,
    stock_minimo_seguridad  INT             NOT NULL DEFAULT 10,
    fecha_ultima_auditoria  DATE            NOT NULL,
    CONSTRAINT pk_stock PRIMARY KEY (id_stock),
    CONSTRAINT uq_stock_prod_inv UNIQUE (id_producto, id_inventario),
    CONSTRAINT fk_stock_producto
        FOREIGN KEY (id_producto)  REFERENCES producto   (id_producto)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_stock_inventario
        FOREIGN KEY (id_inventario) REFERENCES inventario (id_inventario)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_stock_cantidad
        CHECK (cantidad_actual >= 0),
    CONSTRAINT ck_stock_minimo
        CHECK (stock_minimo_seguridad >= 0)
);
 
-- ------------------------------------------------------------
-- 2.5  USUARIO
-- Tabla base para la jerarquía Administrador / Vendedor.
-- ------------------------------------------------------------
CREATE TABLE usuario (
    id_usuario      INT             NOT NULL AUTO_INCREMENT,
    nombre_completo VARCHAR(150)    NOT NULL,
    username        VARCHAR(60)     NOT NULL,
    password_hash   VARCHAR(255)    NOT NULL,
    estado_activo   TINYINT(1)      NOT NULL DEFAULT 1,
    rol             ENUM('ADMIN','VENDEDOR') NOT NULL,
    CONSTRAINT pk_usuario  PRIMARY KEY (id_usuario),
    CONSTRAINT uq_username UNIQUE (username)
);
 
-- ------------------------------------------------------------
-- 2.6  ADMINISTRADOR
-- Especialización de usuario con rol ADMIN.
-- ------------------------------------------------------------
CREATE TABLE administrador (
    id_usuario              INT             NOT NULL,
    ultimo_acceso_admin     DATETIME            NULL,
    CONSTRAINT pk_administrador  PRIMARY KEY (id_usuario),
    CONSTRAINT fk_admin_usuario
        FOREIGN KEY (id_usuario) REFERENCES usuario (id_usuario)
        ON UPDATE CASCADE ON DELETE CASCADE
);
 
-- ------------------------------------------------------------
-- 2.7  VENDEDOR
-- Especialización de usuario con rol VENDEDOR.
-- ------------------------------------------------------------
CREATE TABLE vendedor (
    id_usuario          INT             NOT NULL,
    codigo_terminal     VARCHAR(20)     NOT NULL,
    ventas_mes_actual   INT             NOT NULL DEFAULT 0,
    CONSTRAINT pk_vendedor PRIMARY KEY (id_usuario),
    CONSTRAINT uq_vendedor_terminal UNIQUE (codigo_terminal),
    CONSTRAINT fk_vendedor_usuario
        FOREIGN KEY (id_usuario) REFERENCES usuario (id_usuario)
        ON UPDATE CASCADE ON DELETE CASCADE
);
 
-- ------------------------------------------------------------
-- 2.8  CLIENTE
-- Veterinarias que compran sal mineralizada.
-- ------------------------------------------------------------
CREATE TABLE cliente (
    id_cliente          INT             NOT NULL AUTO_INCREMENT,
    nit_cedula          VARCHAR(20)     NOT NULL,
    nombre_cliente      VARCHAR(150)    NOT NULL,
    telefono            VARCHAR(20)         NULL,
    direccion_entrega   VARCHAR(255)        NULL,
    tipo                ENUM('VETERINARIA','GANADERO') NOT NULL DEFAULT 'VETERINARIA',
    estado_activo       TINYINT(1)      NOT NULL DEFAULT 1,
    CONSTRAINT pk_cliente  PRIMARY KEY (id_cliente),
    CONSTRAINT uq_cliente_nit UNIQUE (nit_cedula)
);
 
-- ------------------------------------------------------------
-- 2.9  MOVIMIENTO_INVENTARIO
-- Toda transacción: ENTRADA (compra), SALIDA (venta), AJUSTE.
-- Cuando tipoMov = 'SALIDA', id_cliente e id_usuario son obligatorios
-- para mantener trazabilidad de la venta.
-- ------------------------------------------------------------
CREATE TABLE movimiento_inventario (
    id_movimiento   INT             NOT NULL AUTO_INCREMENT,
    id_stock        INT             NOT NULL,
    id_usuario      INT             NOT NULL  COMMENT 'Quien ejecuta el movimiento',
    id_cliente      INT                 NULL  COMMENT 'Obligatorio en SALIDA',
    timestamp_mov   DATETIME        NOT NULL  DEFAULT CURRENT_TIMESTAMP,
    cantidad_bultos INT             NOT NULL,
    tipo_mov        ENUM('ENTRADA','SALIDA','AJUSTE') NOT NULL,
    motivo          VARCHAR(255)        NULL,
    CONSTRAINT pk_movimiento PRIMARY KEY (id_movimiento),
    CONSTRAINT fk_mov_stock
        FOREIGN KEY (id_stock)    REFERENCES stock   (id_stock)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_mov_usuario
        FOREIGN KEY (id_usuario)  REFERENCES usuario (id_usuario)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_mov_cliente
        FOREIGN KEY (id_cliente)  REFERENCES cliente (id_cliente)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_mov_cantidad
        CHECK (cantidad_bultos > 0),
    CONSTRAINT ck_mov_salida_cliente
        CHECK (
            tipo_mov <> 'SALIDA' OR id_cliente IS NOT NULL
        )
);
 
-- ------------------------------------------------------------
-- 2.10  REPORTE
-- Un reporte se genera automáticamente por cada movimiento.
-- ------------------------------------------------------------
CREATE TABLE reporte (
    id_reporte      INT             NOT NULL AUTO_INCREMENT,
    id_movimiento   INT             NOT NULL,
    fecha_emision   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    rango_fechas    VARCHAR(100)        NULL  COMMENT 'Periodo referencial del reporte',
    tipo_reporte    ENUM('STOCK','SALIDAS','HISTORIAL') NOT NULL,
    resumen         TEXT                NULL  COMMENT 'Descripción automática del movimiento',
    CONSTRAINT pk_reporte PRIMARY KEY (id_reporte),
    CONSTRAINT uq_reporte_movimiento UNIQUE (id_movimiento),
    CONSTRAINT fk_reporte_movimiento
        FOREIGN KEY (id_movimiento) REFERENCES movimiento_inventario (id_movimiento)
        ON UPDATE CASCADE ON DELETE CASCADE
);
 
 
-- ============================================================
-- 3. DML — INSERCIÓN DE DATOS
-- ============================================================
 
-- ------------------------------------------------------------
-- 3.1  CATEGORIA  (3 registros — datos reales del negocio)
-- ------------------------------------------------------------
INSERT INTO categoria (nombre_categoria, descripcion_uso, porcentaje_fosforo) VALUES
('Sal Mineralizada 12%',  'Sal mineralizada especial para ganado de leche, alta concentración de fósforo al 12%',  12.0),
('Sal Mineralizada 8%',   'Sal mineralizada para doble propósito y ganado de cría, concentración de fósforo al 8%',  8.0),
('Sal Mineralizada Ceba 4%', 'Sal mineralizada especializada para ganadería de ceba o engorde, fósforo al 4%',         4.0);
 
-- ------------------------------------------------------------
-- 3.2  PRODUCTO  (12 registros — 3 concentraciones × 4 presentaciones)
-- Presentaciones:
--   P1: bulto 50 kg en unidades de 1 kg  (50 paquetes/bulto)
--   P2: bulto 50 kg en unidades de 5 kg  (10 paquetes/bulto)
--   P3: bulto 40 kg a granel             (1 bulto)
--   P4: mochila 10 kg                    (1 mochila)
-- ------------------------------------------------------------
INSERT INTO producto (id_categoria, nombre_sal_mineralizada, peso_bulto_kg, unidad_medida, paquetes_por_bulto, descontinuado) VALUES
-- Categoría 1 — 12% (leche)
(1, 'Sal Mineralizada 12% — Bulto 50kg (paquetes de 1kg)',  50.00, '1kg',    50, 0),
(1, 'Sal Mineralizada 12% — Bulto 50kg (paquetes de 5kg)',  50.00, '5kg',    10, 0),
(1, 'Sal Mineralizada 12% — Bulto 40kg a Granel',           40.00, 'granel',  1, 0),
(1, 'Sal Mineralizada 12% — Mochila 10kg',                  10.00, 'mochila', 1, 0),
-- Categoría 2 — 8% (doble propósito / cría)
(2, 'Sal Mineralizada 8% — Bulto 50kg (paquetes de 1kg)',   50.00, '1kg',    50, 0),
(2, 'Sal Mineralizada 8% — Bulto 50kg (paquetes de 5kg)',   50.00, '5kg',    10, 0),
(2, 'Sal Mineralizada 8% — Bulto 40kg a Granel',            40.00, 'granel',  1, 0),
(2, 'Sal Mineralizada 8% — Mochila 10kg',                   10.00, 'mochila', 1, 0),
-- Categoría 3 — 4% (ceba / engorde)
(3, 'Sal Mineralizada Ceba 4% — Bulto 50kg (paquetes de 1kg)', 50.00, '1kg',    50, 0),
(3, 'Sal Mineralizada Ceba 4% — Bulto 50kg (paquetes de 5kg)', 50.00, '5kg',    10, 0),
(3, 'Sal Mineralizada Ceba 4% — Bulto 40kg a Granel',          40.00, 'granel',  1, 0),
(3, 'Sal Mineralizada Ceba 4% — Mochila 10kg',                 10.00, 'mochila', 1, 0);
 
-- ------------------------------------------------------------
-- 3.3  INVENTARIO  (2 bodegas reales en Sogamoso)
-- ------------------------------------------------------------
INSERT INTO inventario (nombre_sede, direccion_fisica, capacidad_maxima_bultos, estado_operativo) VALUES
('Bodega Principal Sogamoso',  'Calle 14 # 12-35, Sogamoso, Boyacá',      2000, 1),
('Bodega Secundaria Sogamoso', 'Carrera 9 # 22-10, Sogamoso, Boyacá',     800,  1);
 
-- ------------------------------------------------------------
-- 3.4  STOCK
-- Se crea un registro de stock por cada producto × bodega.
-- Bodega principal (id=1) tiene stock activo.
-- Bodega secundaria (id=2) tiene stock complementario para productos de mayor rotación.
-- ------------------------------------------------------------
INSERT INTO stock (id_producto, id_inventario, cantidad_actual, stock_minimo_seguridad, fecha_ultima_auditoria) VALUES
-- Bodega principal — los 12 productos
( 1, 1, 320, 30, '2026-04-01'),
( 2, 1, 280, 25, '2026-04-01'),
( 3, 1, 410, 40, '2026-04-01'),
( 4, 1, 180, 20, '2026-04-01'),
( 5, 1, 350, 30, '2026-04-01'),
( 6, 1, 300, 25, '2026-04-01'),
( 7, 1, 460, 40, '2026-04-01'),
( 8, 1, 200, 20, '2026-04-01'),
( 9, 1, 390, 35, '2026-04-01'),
(10, 1, 310, 25, '2026-04-01'),
(11, 1, 480, 40, '2026-04-01'),
(12, 1, 160, 15, '2026-04-01'),
-- Bodega secundaria — solo productos con mayor rotación (granel y 1kg)
( 3, 2, 120, 15, '2026-04-01'),
( 7, 2, 140, 15, '2026-04-01'),
(11, 2,  90, 10, '2026-04-01'),
( 1, 2,  80, 10, '2026-04-01'),
( 5, 2,  70, 10, '2026-04-01'),
( 9, 2,  60, 10, '2026-04-01');
 
-- ------------------------------------------------------------
-- 3.5  USUARIO  (2 admins + 50 vendedores = 52 usuarios)
-- ------------------------------------------------------------
INSERT INTO usuario (nombre_completo, username, password_hash, estado_activo, rol) VALUES
-- Administradores
('Carlos Andrés Rondón Suárez',  'carondons',   SHA2('Admin2026!',256), 1, 'ADMIN'),
('Luz Marina Vargas Pinto',      'lmvargasp',   SHA2('Admin2026!',256), 1, 'ADMIN'),
-- Vendedores (50)
('Andrés Felipe Morales Cruz',   'afmorales',   SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Sandra Milena Díaz Torres',    'smdiaz',      SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Juan Pablo Herrera López',     'jpherrera',   SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('María Camila Ospina Ruiz',     'mcospina',    SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Diego Alejandro Cárdenas Vega','dacardenas',  SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Claudia Patricia Niño Sosa',   'cpnino',      SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Ricardo Enrique Forero Muñoz', 'reforero',    SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Paola Andrea Castillo Bermúdez','pacastillo',  SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Hernán Darío Gómez Arenas',    'hdgomez',     SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Natalia Sofía Pedraza Cely',   'nspedraza',   SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Gustavo Adolfo Ríos Parra',    'garios',      SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Viviana Marcela Triana Huertas','vmtriana',   SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Édgar Humberto Salinas Bolaños','ehsalinas',  SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Adriana Lucía Ramírez Peña',   'alramirez',   SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Fabio Ernesto Camacho Uribe',  'fecamacho',   SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Olga Beatriz Lozano Córdoba',  'oblozano',    SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Mauricio Iván Pineda Acevedo', 'mipineda',    SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Yolanda Esperanza Cruz Varón', 'yecruz',      SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Jhon Fredy Álvarez Rojas',     'jfalvarez',   SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Catalina Isabel Roa Méndez',   'ciroa',       SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('William Javier Patiño Cardona','wjpatino',    SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Esperanza Nohemí Aguilar Soto','enaaguilar',  SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Rodrigo Hernán Bernal Torres', 'rhbernal',    SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Gloria Inés Montoya Salcedo',  'gimontoya',   SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Omar Armando Cuellar Duarte',  'oacuellar',   SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Stella Janeth Parra Mora',     'sjparra',     SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Álvaro José Pinzón Jiménez',   'ajpinzon',    SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Leonor Patricia Méndez Rozo',  'lpmendez',    SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Germán Alberto Fonseca Leal',  'gafonseca',   SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Bibiana Rocío Suárez Chaparro','brsuarez',    SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Néstor Camilo Rincón Duarte',  'ncrincón',    SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Piedad Consuelo Ávila Molina', 'pcavila',     SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Ernesto Luis Gaitán Barreto',  'elgaitan',    SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Amparo Cecilia Varón Zamudio', 'acvaron',     SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Víctor Manuel Rueda Pulido',   'vmrueda',     SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Consuelo Margarita Ossa Peña', 'cmossa',      SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Ferney Augusto Riveros Lara',  'fariveros',   SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Blanca Nubia Torres Castillo', 'bntorres',    SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Heber Alirio Pimiento Valero', 'hapimiento',  SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Sonia Patricia Caro Espinosa', 'spcaro',      SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Fabián Camilo Zuluaga Ortega', 'fczuluaga',   SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('María del Pilar Vargas Reyes', 'mpvargas',    SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Jairo Alfonso Salamanca Niño', 'jasalamanca', SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Elsa Yaneth Suárez Bojacá',    'eysuarez',    SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('César Augusto Herrera Farfán', 'caherrera',   SHA2('Vend2026#',256),  0, 'VENDEDOR'),
('Ana Milena Guerrero Téllez',   'amguerrero',  SHA2('Vend2026#',256),  0, 'VENDEDOR'),
('Roberto Carlos Mora Linares',  'rcmora',      SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Flor Marina Acosta Quintero',  'fmacosta',    SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Héctor Fabio Arias Pedreros',  'hfarias',     SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Nancy Beatriz Delgado Monroy', 'nbdelgado',   SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Jorge Enrique Solano Cáceres', 'jesolano',    SHA2('Vend2026#',256),  1, 'VENDEDOR'),
('Isabel Cristina Bonilla Lara', 'icbonilla',   SHA2('Vend2026#',256),  1, 'VENDEDOR');
 
-- ------------------------------------------------------------
-- 3.6  ADMINISTRADOR  (especializaciones para los 2 admins)
-- ------------------------------------------------------------
INSERT INTO administrador (id_usuario, ultimo_acceso_admin) VALUES
(1, '2026-04-20 08:30:00'),
(2, '2026-04-19 14:15:00');
 
-- ------------------------------------------------------------
-- 3.7  VENDEDOR  (50 registros: id_usuario 3..52)
-- ------------------------------------------------------------
INSERT INTO vendedor (id_usuario, codigo_terminal, ventas_mes_actual) VALUES
( 3,  'TRM-001',  18),
( 4,  'TRM-002',  22),
( 5,  'TRM-003',  15),
( 6,  'TRM-004',  31),
( 7,  'TRM-005',   9),
( 8,  'TRM-006',  27),
( 9,  'TRM-007',  11),
(10,  'TRM-008',  24),
(11,  'TRM-009',  19),
(12,  'TRM-010',  33),
(13,  'TRM-011',   7),
(14,  'TRM-012',  28),
(15,  'TRM-013',  14),
(16,  'TRM-014',  20),
(17,  'TRM-015',  35),
(18,  'TRM-016',  12),
(19,  'TRM-017',  26),
(20,  'TRM-018',  16),
(21,  'TRM-019',  21),
(22,  'TRM-020',   8),
(23,  'TRM-021',  30),
(24,  'TRM-022',  17),
(25,  'TRM-023',  25),
(26,  'TRM-024',  13),
(27,  'TRM-025',  29),
(28,  'TRM-026',  10),
(29,  'TRM-027',  23),
(30,  'TRM-028',  18),
(31,  'TRM-029',  32),
(32,  'TRM-030',   6),
(33,  'TRM-031',  20),
(34,  'TRM-032',  15),
(35,  'TRM-033',  27),
(36,  'TRM-034',  11),
(37,  'TRM-035',  24),
(38,  'TRM-036',  19),
(39,  'TRM-037',  34),
(40,  'TRM-038',   5),
(41,  'TRM-039',  22),
(42,  'TRM-040',  16),
(43,  'TRM-041',  28),
(44,  'TRM-042',  13),
(45,  'TRM-043',   0),  -- inactivo
(46,  'TRM-044',   0),  -- inactivo
(47,  'TRM-045',  21),
(48,  'TRM-046',  17),
(49,  'TRM-047',  26),
(50,  'TRM-048',  14),
(51,  'TRM-049',  29),
(52,  'TRM-050',  23);
 
-- ------------------------------------------------------------
-- 3.8  CLIENTE  (50 veterinarias reales de Boyacá / Cundinamarca)
-- ------------------------------------------------------------
INSERT INTO cliente (nit_cedula, nombre_cliente, telefono, direccion_entrega, tipo, estado_activo) VALUES
('900112233-1', 'Veterinaria El Potrero',           '3124456789', 'Calle 5 # 10-22, Sogamoso',       'VETERINARIA', 1),
('900223344-2', 'Agroveterinaria Los Andes',         '3135567890', 'Carrera 8 # 14-40, Sogamoso',     'VETERINARIA', 1),
('900334455-3', 'Clínica Veterinaria Boyacá',        '3146678901', 'Calle 12 # 5-18, Tunja',          'VETERINARIA', 1),
('900445566-4', 'Veterinaria Campo Verde',            '3157789012', 'Carrera 3 # 7-30, Duitama',       'VETERINARIA', 1),
('900556677-5', 'Agropecuaria La Sabana',             '3168890123', 'Calle 9 # 11-55, Chiquinquirá',   'VETERINARIA', 1),
('900667788-6', 'Veterinaria El Páramo',              '3179901234', 'Carrera 12 # 3-20, Paipa',        'VETERINARIA', 1),
('900778899-7', 'Distribuidora Ganadera del Norte',  '3180012345', 'Calle 6 # 8-44, Santa Rosa Viterbo','VETERINARIA',1),
('900889900-8', 'Veterinaria San Isidro Labrador',   '3191123456', 'Carrera 5 # 15-10, Nobsa',        'VETERINARIA', 1),
('901001122-9', 'Agroveterinaria El Llano',           '3102234567', 'Calle 3 # 2-60, Monguí',          'VETERINARIA', 1),
('901112233-0', 'Centro Veterinario Boyacá',          '3113345678', 'Carrera 7 # 9-35, Tibasosa',      'VETERINARIA', 1),
('901223344-1', 'Veterinaria El Altiplano',           '3124456780', 'Calle 15 # 4-28, Belén',          'VETERINARIA', 1),
('901334455-2', 'Agroservicios La Pradera',           '3135567881', 'Carrera 10 # 12-50, Paz de Río',  'VETERINARIA', 1),
('901445566-3', 'Veterinaria San Martín',             '3146678902', 'Calle 7 # 6-14, Corrales',        'VETERINARIA', 1),
('901556677-4', 'Distribuciones Ganaderas Oriente',  '3157789013', 'Carrera 2 # 18-22, Socotá',       'VETERINARIA', 1),
('901667788-5', 'Veterinaria La Esperanza',           '3168890124', 'Calle 11 # 13-40, Susacón',       'VETERINARIA', 1),
('901778899-6', 'Agroinsumos El Campo',               '3179901235', 'Carrera 4 # 7-55, Socha',         'VETERINARIA', 1),
('901889900-7', 'Clínica Veterinaria del Tundama',   '3180012346', 'Calle 8 # 10-30, Tópaga',         'VETERINARIA', 1),
('902001122-8', 'Veterinaria Las Vacas Felices',      '3191123457', 'Carrera 6 # 5-18, Gámeza',        'VETERINARIA', 1),
('902112233-9', 'Agropecuaria El Guavio',             '3102234568', 'Calle 4 # 3-44, Tasco',           'VETERINARIA', 1),
('902223344-0', 'Veterinaria Los Chibchas',           '3113345679', 'Carrera 9 # 11-60, Mongua',       'VETERINARIA', 1),
('902334455-1', 'Insuagro La Colonia',                '3124456781', 'Calle 16 # 2-38, Busbanzá',       'VETERINARIA', 1),
('902445566-2', 'Veterinaria El Encanto',             '3135567882', 'Carrera 11 # 14-22, Floresta',    'VETERINARIA', 1),
('902556677-3', 'Agroveterinaria Pantano de Vargas',  '3146678903', 'Calle 10 # 7-50, Paipa',          'VETERINARIA', 1),
('902667788-4', 'Distribuidora El Rancho',            '3157789014', 'Carrera 1 # 16-30, Cerinza',      'VETERINARIA', 1),
('902778899-5', 'Veterinaria El Trigal',              '3168890125', 'Calle 13 # 9-42, Betéitiva',      'VETERINARIA', 1),
('902889900-6', 'Agrovet La Montaña',                 '3179901236', 'Carrera 3 # 4-60, Tutazá',        'VETERINARIA', 1),
('903001122-7', 'Veterinaria La Vega',                '3180012347', 'Calle 6 # 12-24, Santa Rosa',     'VETERINARIA', 1),
('903112233-8', 'Insumos Ganaderos del Oriente',     '3191123458', 'Carrera 8 # 6-40, Jericó',        'VETERINARIA', 1),
('903223344-9', 'Clínica Veterinaria El Molino',      '3102234569', 'Calle 2 # 1-55, El Espino',       'VETERINARIA', 1),
('903334455-0', 'Veterinaria Puente Boyacá',          '3113345680', 'Carrera 5 # 8-30, Ventaquemada',  'VETERINARIA', 1),
('903445566-1', 'Agroveterinaria La Llanura',         '3124456782', 'Calle 14 # 3-48, Villa de Leyva', 'VETERINARIA', 1),
('903556677-2', 'Distribuciones El Páramo',           '3135567883', 'Carrera 7 # 15-20, Chíquiza',     'VETERINARIA', 1),
('903667788-3', 'Veterinaria San Rafael',             '3146678904', 'Calle 9 # 5-36, Arcabuco',        'VETERINARIA', 1),
('903778899-4', 'Agroservicios El Porvenir',          '3157789015', 'Carrera 2 # 10-44, Moniquirá',    'VETERINARIA', 1),
('903889900-5', 'Veterinaria El Prado',               '3168890126', 'Calle 11 # 4-52, Togüí',          'VETERINARIA', 1),
('904001122-6', 'Insuagro San Juan de Dios',          '3179901237', 'Carrera 4 # 13-28, San José Pare','VETERINARIA', 1),
('904112233-7', 'Veterinaria La Rivera',              '3180012348', 'Calle 7 # 8-34, Chitaraque',      'VETERINARIA', 1),
('904223344-8', 'Distribuidora Ganadera Sur',         '3191123459', 'Carrera 6 # 3-50, Santana',       'VETERINARIA', 1),
('904334455-9', 'Agroveterinaria El Nido',            '3102234570', 'Calle 3 # 6-22, Páez',            'VETERINARIA', 1),
('904445566-0', 'Veterinaria La Palma',               '3113345681', 'Carrera 9 # 7-40, Berbeo',        'VETERINARIA', 1),
('904556677-1', 'Clínica Veterinaria El Tesoro',      '3124456783', 'Calle 5 # 2-58, Miraflores',      'VETERINARIA', 1),
('904667788-2', 'Veterinaria Tierradentro',           '3135567884', 'Carrera 11 # 11-26, Zetaquira',   'VETERINARIA', 1),
('904778899-3', 'Agrovet El Manantial',               '3146678905', 'Calle 12 # 6-44, La Victoria',    'VETERINARIA', 1),
('904889900-4', 'Distribuidora El Establo',           '3157789016', 'Carrera 1 # 4-62, Macanal',       'VETERINARIA', 1),
('905001122-5', 'Veterinaria Las Gaviotas',           '3168890127', 'Calle 8 # 9-30, Guateque',        'VETERINARIA', 1),
('905112233-6', 'Insumos El Campesino',               '3179901238', 'Carrera 3 # 5-48, Tenza',         'VETERINARIA', 1),
('905223344-7', 'Agroveterinaria La Cumbre',          '3180012349', 'Calle 4 # 11-36, Garagoa',        'VETERINARIA', 1),
('905334455-8', 'Veterinaria Del Valle',              '3191123460', 'Carrera 7 # 14-20, Chinavita',    'VETERINARIA', 1),
('905445566-9', 'Distribuciones El Potrero Grande',  '3102234571', 'Calle 6 # 1-54, Pachavita',       'VETERINARIA', 1),
('905556677-0', 'Veterinaria El Cielo',               '3113345682', 'Carrera 5 # 3-30, Santa María',   'VETERINARIA', 0); -- inactivo
 
-- ------------------------------------------------------------
-- 3.9  MOVIMIENTO_INVENTARIO  (55 movimientos realistas)
-- Se usan id_stock correspondientes a la bodega principal (ids 1-12).
-- id_stock 1  = producto 1 (12% / 1kg)  en bodega 1
-- id_stock 3  = producto 3 (12% / granel) en bodega 1
-- id_stock 5  = producto 5 (8% / 1kg)   en bodega 1
-- id_stock 7  = producto 7 (8% / granel) en bodega 1
-- id_stock 9  = producto 9 (4% / 1kg)   en bodega 1
-- id_stock 11 = producto 11 (4% / granel) en bodega 1
-- ENTRADAS: id_usuario = administradores (1 ó 2), id_cliente = NULL
-- SALIDAS:  id_usuario = vendedores  (3..52), id_cliente requerido
-- AJUSTES:  id_usuario = administradores, id_cliente = NULL
-- ------------------------------------------------------------
INSERT INTO movimiento_inventario (id_stock, id_usuario, id_cliente, timestamp_mov, cantidad_bultos, tipo_mov, motivo) VALUES
-- ENTRADAS (reposición de inventario — ejecutadas por admins, con lote)
( 3, 1, NULL, '2026-01-05 08:00:00', 200, 'ENTRADA', 'LOTE: LOTE-2026-001. Reposición inicial de temporada — sal 12% granel'),
( 7, 1, NULL, '2026-01-05 08:30:00', 200, 'ENTRADA', 'LOTE: LOTE-2026-002. Reposición inicial de temporada — sal 8% granel'),
(11, 1, NULL, '2026-01-05 09:00:00', 150, 'ENTRADA', 'LOTE: LOTE-2026-003. Reposición inicial de temporada — sal 4% granel'),
( 1, 2, NULL, '2026-01-10 10:00:00', 100, 'ENTRADA', 'LOTE: LOTE-2026-004. Compra proveedor — sal 12% paquetes 1kg'),
( 5, 2, NULL, '2026-01-10 10:30:00', 100, 'ENTRADA', 'LOTE: LOTE-2026-005. Compra proveedor — sal 8% paquetes 1kg'),
( 9, 2, NULL, '2026-01-10 11:00:00',  80, 'ENTRADA', 'LOTE: LOTE-2026-006. Compra proveedor — sal 4% paquetes 1kg'),
( 2, 1, NULL, '2026-01-15 09:00:00',  80, 'ENTRADA', 'LOTE: LOTE-2026-007. Compra proveedor — sal 12% paquetes 5kg'),
( 6, 1, NULL, '2026-01-15 09:30:00',  80, 'ENTRADA', 'LOTE: LOTE-2026-008. Compra proveedor — sal 8% paquetes 5kg'),
(10, 2, NULL, '2026-01-15 10:00:00',  60, 'ENTRADA', 'LOTE: LOTE-2026-009. Compra proveedor — sal 4% paquetes 5kg'),
( 4, 2, NULL, '2026-01-20 08:00:00',  50, 'ENTRADA', 'LOTE: LOTE-2026-010. Compra proveedor — mochilas 12%'),
-- SALIDAS (ventas — ejecutadas por vendedores con cliente asociado)
( 3,  3,  1, '2026-01-12 09:00:00',  10, 'SALIDA', 'Venta — Veterinaria El Potrero'),
( 7,  4,  2, '2026-01-13 10:15:00',   8, 'SALIDA', 'Venta — Agroveterinaria Los Andes'),
( 1,  5,  3, '2026-01-14 11:00:00',  15, 'SALIDA', 'Venta — Clínica Veterinaria Boyacá'),
( 5,  6,  4, '2026-01-15 09:30:00',  12, 'SALIDA', 'Venta — Veterinaria Campo Verde'),
(11,  7,  5, '2026-01-16 14:00:00',  20, 'SALIDA', 'Venta — Agropecuaria La Sabana'),
( 3,  8,  6, '2026-01-17 10:45:00',   6, 'SALIDA', 'Venta — Veterinaria El Páramo'),
( 9,  9,  7, '2026-01-18 11:30:00',  18, 'SALIDA', 'Venta — Distribuidora Ganadera del Norte'),
( 7, 10,  8, '2026-01-19 15:00:00',  14, 'SALIDA', 'Venta — Veterinaria San Isidro Labrador'),
( 2, 11,  9, '2026-01-20 09:15:00',   5, 'SALIDA', 'Venta — Agroveterinaria El Llano'),
( 5, 12, 10, '2026-01-21 13:00:00',  22, 'SALIDA', 'Venta — Centro Veterinario Boyacá'),
( 1, 13, 11, '2026-01-22 10:00:00',   9, 'SALIDA', 'Venta — Veterinaria El Altiplano'),
( 3, 14, 12, '2026-01-23 11:45:00',  16, 'SALIDA', 'Venta — Agroservicios La Pradera'),
(11, 15, 13, '2026-01-24 14:30:00',  11, 'SALIDA', 'Venta — Veterinaria San Martín'),
( 7, 16, 14, '2026-01-25 09:00:00',  25, 'SALIDA', 'Venta — Distribuciones Ganaderas Oriente'),
( 5, 17, 15, '2026-02-02 10:30:00',  13, 'SALIDA', 'Venta — Veterinaria La Esperanza'),
( 9, 18, 16, '2026-02-03 11:00:00',  17, 'SALIDA', 'Venta — Agroinsumos El Campo'),
( 3, 19, 17, '2026-02-04 14:15:00',   8, 'SALIDA', 'Venta — Clínica Veterinaria del Tundama'),
( 1, 20, 18, '2026-02-05 09:45:00',  21, 'SALIDA', 'Venta — Veterinaria Las Vacas Felices'),
( 7, 21, 19, '2026-02-06 13:00:00',  19, 'SALIDA', 'Venta — Agropecuaria El Guavio'),
(11, 22, 20, '2026-02-07 10:30:00',  24, 'SALIDA', 'Venta — Veterinaria Los Chibchas'),
( 5, 23, 21, '2026-02-10 09:00:00',   7, 'SALIDA', 'Venta — Insuagro La Colonia'),
( 3, 24, 22, '2026-02-11 11:15:00',  12, 'SALIDA', 'Venta — Veterinaria El Encanto'),
( 9, 25, 23, '2026-02-12 14:45:00',  10, 'SALIDA', 'Venta — Agroveterinaria Pantano de Vargas'),
( 1, 26, 24, '2026-02-13 10:00:00',  16, 'SALIDA', 'Venta — Distribuidora El Rancho'),
( 7, 27, 25, '2026-02-14 09:30:00',  20, 'SALIDA', 'Venta — Veterinaria El Trigal'),
(11, 28, 26, '2026-02-17 11:00:00',  14, 'SALIDA', 'Venta — Agrovet La Montaña'),
( 5, 29, 27, '2026-02-18 13:30:00',  18, 'SALIDA', 'Venta — Veterinaria La Vega'),
( 3, 30, 28, '2026-02-19 10:15:00',   9, 'SALIDA', 'Venta — Insumos Ganaderos del Oriente'),
( 9, 31, 29, '2026-02-20 09:00:00',  23, 'SALIDA', 'Venta — Clínica Veterinaria El Molino'),
( 1, 32, 30, '2026-02-21 14:00:00',  11, 'SALIDA', 'Venta — Veterinaria Puente Boyacá'),
( 7, 33, 31, '2026-03-03 10:30:00',  15, 'SALIDA', 'Venta — Agroveterinaria La Llanura'),
(11, 34, 32, '2026-03-04 11:45:00',  17, 'SALIDA', 'Venta — Distribuciones El Páramo'),
( 5, 35, 33, '2026-03-05 09:00:00',  13, 'SALIDA', 'Venta — Veterinaria San Rafael'),
( 3, 36, 34, '2026-03-06 13:15:00',   8, 'SALIDA', 'Venta — Agroservicios El Porvenir'),
( 9, 37, 35, '2026-03-09 10:00:00',  22, 'SALIDA', 'Venta — Veterinaria El Prado'),
( 1, 38, 36, '2026-03-10 11:30:00',  14, 'SALIDA', 'Venta — Insuagro San Juan de Dios'),
( 7, 39, 37, '2026-03-11 14:00:00',  16, 'SALIDA', 'Venta — Veterinaria La Rivera'),
(11, 40, 38, '2026-03-12 09:30:00',  19, 'SALIDA', 'Venta — Distribuidora Ganadera Sur'),
( 5, 41, 39, '2026-03-13 10:45:00',  10, 'SALIDA', 'Venta — Agroveterinaria El Nido'),
( 3, 42, 40, '2026-03-16 11:00:00',   6, 'SALIDA', 'Venta — Veterinaria La Palma'),
( 9, 43, 41, '2026-03-17 13:30:00',  25, 'SALIDA', 'Venta — Clínica Veterinaria El Tesoro'),
( 1, 44, 42, '2026-03-18 09:15:00',  12, 'SALIDA', 'Venta — Veterinaria Tierradentro'),
( 7, 47, 43, '2026-03-19 10:30:00',  18, 'SALIDA', 'Venta — Agrovet El Manantial'),
(11, 48, 44, '2026-03-20 14:00:00',  21, 'SALIDA', 'Venta — Distribuidora El Establo'),
( 5, 49, 45, '2026-04-01 09:00:00',  15, 'SALIDA', 'Venta — Veterinaria Las Gaviotas'),
( 3, 50, 46, '2026-04-02 11:15:00',   9, 'SALIDA', 'Venta — Insumos El Campesino'),
( 9, 51, 47, '2026-04-03 13:00:00',  20, 'SALIDA', 'Venta — Agroveterinaria La Cumbre'),
-- AJUSTES (correcciones manuales — ejecutados por admins, sin cliente)
( 3, 1, NULL, '2026-02-01 07:00:00',  5, 'AJUSTE', 'Corrección auditoría — diferencia conteo físico sal 12% granel'),
( 7, 2, NULL, '2026-02-01 07:30:00',  3, 'AJUSTE', 'Corrección auditoría — diferencia conteo físico sal 8% granel'),
( 4, 1, NULL, '2026-03-01 08:00:00',  2, 'AJUSTE', 'Baja por daño en empaque — mochilas 12%'),
( 8, 2, NULL, '2026-03-01 08:30:00',  4, 'AJUSTE', 'Pérdida por humedad — mochilas 8%'),
(12, 1, NULL, '2026-04-01 07:00:00',  1, 'AJUSTE', 'Devolución proveedor — mochilas 4% defectuosas'),
( 6, 2, NULL, '2026-04-05 07:30:00',  3, 'AJUSTE', 'Ajuste por inventario físico — sal 8% paquetes 5kg'),
( 2, 1, NULL, '2026-04-10 08:00:00',  2, 'AJUSTE', 'Ajuste por inventario físico — sal 12% paquetes 5kg');
-- ------------------------------------------------------------
-- 3.10  REPORTE
-- Un reporte por cada movimiento (55 movimientos = 55 reportes).
-- tipo_reporte:
--   ENTRADA  → STOCK
--   SALIDA   → SALIDAS
--   AJUSTE   → HISTORIAL
-- ------------------------------------------------------------
INSERT INTO reporte (id_movimiento, fecha_emision, rango_fechas, tipo_reporte, resumen)
SELECT
    m.id_movimiento,
    m.timestamp_mov                                          AS fecha_emision,
    CONCAT(
        DATE_FORMAT(m.timestamp_mov, '%Y-%m-01'),
        ' / ',
        DATE_FORMAT(LAST_DAY(m.timestamp_mov), '%Y-%m-%d')
    )                                                        AS rango_fechas,
    CASE m.tipo_mov
        WHEN 'ENTRADA' THEN 'STOCK'
        WHEN 'SALIDA'  THEN 'SALIDAS'
        WHEN 'AJUSTE'  THEN 'HISTORIAL'
    END                                                      AS tipo_reporte,
    CONCAT(
        'Movimiento #', m.id_movimiento,
        ' | Tipo: ', m.tipo_mov,
        ' | Cantidad: ', m.cantidad_bultos, ' bultos',
        ' | Stock ID: ', m.id_stock,
        CASE WHEN m.id_cliente IS NOT NULL
             THEN CONCAT(' | Cliente ID: ', m.id_cliente)
             ELSE ''
        END,
        ' | ', COALESCE(m.motivo, 'Sin motivo registrado')
    )                                                        AS resumen
FROM movimiento_inventario m;

-- ============================================================
-- MÓDULO 4: CONTROL DE INVENTARIO
-- Implementación de requisitos funcionales RQF024 a RQF039
-- ============================================================

DELIMITER $$

-- ------------------------------------------------------------
-- RQF024: Registrar entrada de mercancía al inventario
-- Asocia un movimiento tipo ENTRADA y actualiza el stock correspondiente
-- RQF036: Trazabilidad por lote mediante el campo motivo (LOTE: XXXX)
-- ------------------------------------------------------------
CREATE PROCEDURE sp_registrar_entrada(
    IN p_id_producto INT,
    IN p_id_inventario INT,
    IN p_id_usuario INT,
    IN p_cantidad_bultos INT,
    IN p_motivo VARCHAR(255),
    IN p_lote VARCHAR(50)
)
BEGIN
    DECLARE v_id_stock INT;
    DECLARE v_stock_actual INT;
    DECLARE v_motivo_completo VARCHAR(255);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error al registrar entrada. Transacción revertida.';
    END;
    START TRANSACTION;
    -- Construir motivo incluyendo lote si se proporciona
    IF p_lote IS NOT NULL AND p_lote <> '' THEN
        SET v_motivo_completo = CONCAT('LOTE: ', p_lote, '. ', p_motivo);
    ELSE
        SET v_motivo_completo = p_motivo;
    END IF;
    -- Obtener el id_stock correspondiente al producto e inventario
    SELECT id_stock, cantidad_actual INTO v_id_stock, v_stock_actual
    FROM stock
    WHERE id_producto = p_id_producto AND id_inventario = p_id_inventario
    FOR UPDATE;
    -- Si no existe, crearlo (por si no se insertó previamente en el DML)
    IF v_id_stock IS NULL THEN
        INSERT INTO stock (id_producto, id_inventario, cantidad_actual, stock_minimo_seguridad, fecha_ultima_auditoria)
        VALUES (p_id_producto, p_id_inventario, 0, 10, CURDATE());
        SET v_id_stock = LAST_INSERT_ID();
        SET v_stock_actual = 0;
    END IF;
    -- Registrar el movimiento
    INSERT INTO movimiento_inventario (id_stock, id_usuario, id_cliente, timestamp_mov, cantidad_bultos, tipo_mov, motivo)
    VALUES (v_id_stock, p_id_usuario, NULL, NOW(), p_cantidad_bultos, 'ENTRADA', v_motivo_completo);
    -- Actualizar stock
    UPDATE stock SET cantidad_actual = cantidad_actual + p_cantidad_bultos WHERE id_stock = v_id_stock;
    COMMIT;
END$$

-- ------------------------------------------------------------
-- RQF025 / RQF026 / RQF028: Registrar salida de mercancía vinculada a cliente
-- Valida disponibilidad (RQF028), actualiza stock (RQF026) y registra la salida (RQF025)
-- ------------------------------------------------------------
CREATE PROCEDURE sp_registrar_salida(
    IN p_id_producto INT,
    IN p_id_inventario INT,
    IN p_id_usuario INT,
    IN p_id_cliente INT,
    IN p_cantidad_bultos INT,
    IN p_motivo VARCHAR(255)
)
BEGIN
    DECLARE v_id_stock INT;
    DECLARE v_stock_actual INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error al registrar salida. Verifique disponibilidad y datos.';
    END;
    START TRANSACTION;
    -- Obtener stock y bloquear fila
    SELECT id_stock, cantidad_actual INTO v_id_stock, v_stock_actual
    FROM stock
    WHERE id_producto = p_id_producto AND id_inventario = p_id_inventario
    FOR UPDATE;
    IF v_id_stock IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No existe registro de stock para ese producto en la bodega indicada.';
    END IF;
    -- Validar disponibilidad (RQF028)
    IF v_stock_actual < p_cantidad_bultos THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Stock insuficiente para realizar la salida.';
    END IF;
    -- Registrar movimiento de salida
    INSERT INTO movimiento_inventario (id_stock, id_usuario, id_cliente, timestamp_mov, cantidad_bultos, tipo_mov, motivo)
    VALUES (v_id_stock, p_id_usuario, p_id_cliente, NOW(), p_cantidad_bultos, 'SALIDA', p_motivo);
    -- Actualizar stock automáticamente (RQF026)
    UPDATE stock SET cantidad_actual = cantidad_actual - p_cantidad_bultos WHERE id_stock = v_id_stock;
    COMMIT;
END$$

-- ------------------------------------------------------------
-- RQF027: Consulta de stock actual por producto o todos
-- ------------------------------------------------------------
CREATE PROCEDURE sp_consultar_stock_actual(
    IN p_id_producto INT
)
BEGIN
    IF p_id_producto IS NULL THEN
        SELECT p.id_producto, p.nombre_sal_mineralizada, i.nombre_sede, s.cantidad_actual
        FROM producto p
        JOIN stock s ON p.id_producto = s.id_producto
        JOIN inventario i ON s.id_inventario = i.id_inventario
        ORDER BY p.id_producto, i.nombre_sede;
    ELSE
        SELECT p.id_producto, p.nombre_sal_mineralizada, i.nombre_sede, s.cantidad_actual
        FROM producto p
        JOIN stock s ON p.id_producto = s.id_producto
        JOIN inventario i ON s.id_inventario = i.id_inventario
        WHERE p.id_producto = p_id_producto;
    END IF;
END$$

-- ------------------------------------------------------------
-- RQF030: Registro de daños o pérdidas 
-- ------------------------------------------------------------
CREATE PROCEDURE sp_registrar_danio_perdida(
    IN p_id_producto INT,
    IN p_id_inventario INT,
    IN p_id_usuario INT,
    IN p_cantidad_bultos INT,
    IN p_motivo VARCHAR(255)
)
BEGIN
    DECLARE v_id_stock INT;
    DECLARE v_stock_actual INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error al registrar daño/pérdida.';
    END;
    START TRANSACTION;
    SELECT id_stock, cantidad_actual INTO v_id_stock, v_stock_actual
    FROM stock
    WHERE id_producto = p_id_producto AND id_inventario = p_id_inventario
    FOR UPDATE;
    IF v_id_stock IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No existe registro de stock para ese producto en la bodega.';
    END IF;
    IF v_stock_actual < p_cantidad_bultos THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se puede dar de baja una cantidad mayor al stock actual.';
    END IF;
    INSERT INTO movimiento_inventario (id_stock, id_usuario, id_cliente, timestamp_mov, cantidad_bultos, tipo_mov, motivo)
    VALUES (v_id_stock, p_id_usuario, NULL, NOW(), p_cantidad_bultos, 'AJUSTE', CONCAT('DAÑO/PÉRDIDA: ', p_motivo));
    UPDATE stock SET cantidad_actual = cantidad_actual - p_cantidad_bultos WHERE id_stock = v_id_stock;
    COMMIT;
END$$

-- ------------------------------------------------------------
-- RQF031 / RQF032: Alerta de inventario crítico
-- Procedimiento que devuelve productos por debajo del stock mínimo
-- ------------------------------------------------------------
CREATE PROCEDURE sp_consultar_inventario_critico()
BEGIN
    SELECT p.id_producto, p.nombre_sal_mineralizada, i.nombre_sede,
           s.cantidad_actual, s.stock_minimo_seguridad
    FROM stock s
    JOIN producto p ON s.id_producto = p.id_producto
    JOIN inventario i ON s.id_inventario = i.id_inventario
    WHERE s.cantidad_actual <= s.stock_minimo_seguridad;
END$$

-- ------------------------------------------------------------
-- RQF032: Configurar stock mínimo por producto/bodega
-- ------------------------------------------------------------
CREATE PROCEDURE sp_configurar_stock_minimo(
    IN p_id_producto INT,
    IN p_id_inventario INT,
    IN p_nuevo_minimo INT
)
BEGIN
    UPDATE stock
    SET stock_minimo_seguridad = p_nuevo_minimo
    WHERE id_producto = p_id_producto AND id_inventario = p_id_inventario;
    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se encontró el registro de stock especificado.';
    END IF;
END$$

-- ------------------------------------------------------------
-- RQF033: Registro de devoluciones 
-- ------------------------------------------------------------
CREATE PROCEDURE sp_registrar_devolucion(
    IN p_id_producto INT,
    IN p_id_inventario INT,
    IN p_id_usuario INT,
    IN p_id_cliente INT,
    IN p_cantidad_bultos INT,
    IN p_justificacion VARCHAR(255)
)
BEGIN
    DECLARE v_id_stock INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error al registrar devolución.';
    END;
    START TRANSACTION;
    SELECT id_stock INTO v_id_stock
    FROM stock
    WHERE id_producto = p_id_producto AND id_inventario = p_id_inventario
    FOR UPDATE;
    IF v_id_stock IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No existe stock para ese producto en la bodega.';
    END IF;
    -- Se registra como ENTRADA con motivo de devolución
    INSERT INTO movimiento_inventario (id_stock, id_usuario, id_cliente, timestamp_mov, cantidad_bultos, tipo_mov, motivo)
    VALUES (v_id_stock, p_id_usuario, p_id_cliente, NOW(), p_cantidad_bultos, 'ENTRADA', CONCAT('DEVOLUCIÓN: ', p_justificacion));
    UPDATE stock SET cantidad_actual = cantidad_actual + p_cantidad_bultos WHERE id_stock = v_id_stock;
    COMMIT;
END$$

-- ------------------------------------------------------------
-- RQF034: Historial de movimientos de inventario 
-- ------------------------------------------------------------
CREATE PROCEDURE sp_historial_movimientos()
BEGIN
    SELECT m.id_movimiento, p.nombre_sal_mineralizada, i.nombre_sede,
           m.cantidad_bultos, m.tipo_mov, m.timestamp_mov,
           u.nombre_completo AS usuario, c.nombre_cliente AS cliente,
           m.motivo
    FROM movimiento_inventario m
    JOIN stock s ON m.id_stock = s.id_stock
    JOIN producto p ON s.id_producto = p.id_producto
    JOIN inventario i ON s.id_inventario = i.id_inventario
    JOIN usuario u ON m.id_usuario = u.id_usuario
    LEFT JOIN cliente c ON m.id_cliente = c.id_cliente
    ORDER BY m.timestamp_mov DESC;
END$$

-- ------------------------------------------------------------
-- RQF035: Ajuste manual de inventario
-- ------------------------------------------------------------
CREATE PROCEDURE sp_ajuste_manual_inventario(
    IN p_id_producto INT,
    IN p_id_inventario INT,
    IN p_id_usuario INT,
    IN p_cantidad_bultos INT,
    IN p_motivo VARCHAR(255)
)
BEGIN
    DECLARE v_id_stock INT;
    DECLARE v_stock_actual INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error al realizar ajuste manual.';
    END;
    START TRANSACTION;
    SELECT id_stock, cantidad_actual INTO v_id_stock, v_stock_actual
    FROM stock
    WHERE id_producto = p_id_producto AND id_inventario = p_id_inventario
    FOR UPDATE;
    IF v_id_stock IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No existe stock para ese producto en la bodega.';
    END IF;
    -- Validar que no se intente dejar stock negativo en ajuste manual
    IF (v_stock_actual + p_cantidad_bultos) < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El ajuste resultaría en stock negativo.';
    END IF;
    INSERT INTO movimiento_inventario (id_stock, id_usuario, id_cliente, timestamp_mov, cantidad_bultos, tipo_mov, motivo)
    VALUES (v_id_stock, p_id_usuario, NULL, NOW(), ABS(p_cantidad_bultos), 'AJUSTE', CONCAT('AJUSTE MANUAL: ', p_motivo));
    UPDATE stock SET cantidad_actual = cantidad_actual + p_cantidad_bultos WHERE id_stock = v_id_stock;
    COMMIT;
END$$

-- ------------------------------------------------------------
-- RQF036: Trazabilidad por lote (consulta de movimientos por número de lote)
-- El número de lote se almacena en el campo 'motivo' con el formato 'LOTE: XXXXX.'
-- ------------------------------------------------------------
CREATE PROCEDURE sp_consultar_movimientos_por_lote(
    IN p_lote VARCHAR(50)
)
BEGIN
    SELECT m.id_movimiento, p.nombre_sal_mineralizada, i.nombre_sede,
           m.cantidad_bultos, m.tipo_mov, m.timestamp_mov,
           u.nombre_completo AS usuario, c.nombre_cliente AS cliente,
           m.motivo
    FROM movimiento_inventario m
    JOIN stock s ON m.id_stock = s.id_stock
    JOIN producto p ON s.id_producto = p.id_producto
    JOIN inventario i ON s.id_inventario = i.id_inventario
    JOIN usuario u ON m.id_usuario = u.id_usuario
    LEFT JOIN cliente c ON m.id_cliente = c.id_cliente
    WHERE m.motivo LIKE CONCAT('%LOTE: ', p_lote, '.%')
    ORDER BY m.timestamp_mov;
END$$

-- ------------------------------------------------------------
-- RQF037: Consulta de movimientos filtrados por rango de fechas
-- ------------------------------------------------------------
CREATE PROCEDURE sp_consulta_movimientos_por_fecha(
    IN p_fecha_inicio DATE,
    IN p_fecha_fin DATE
)
BEGIN
    SELECT m.id_movimiento, p.nombre_sal_mineralizada, i.nombre_sede,
           m.cantidad_bultos, m.tipo_mov, m.timestamp_mov,
           u.nombre_completo AS usuario, c.nombre_cliente AS cliente,
           m.motivo
    FROM movimiento_inventario m
    JOIN stock s ON m.id_stock = s.id_stock
    JOIN producto p ON s.id_producto = p.id_producto
    JOIN inventario i ON s.id_inventario = i.id_inventario
    JOIN usuario u ON m.id_usuario = u.id_usuario
    LEFT JOIN cliente c ON m.id_cliente = c.id_cliente
    WHERE DATE(m.timestamp_mov) BETWEEN p_fecha_inicio AND p_fecha_fin
    ORDER BY m.timestamp_mov;
END$$

-- ------------------------------------------------------------
-- RQF038: Consulta de movimientos filtrados por tipo de producto
-- ------------------------------------------------------------
CREATE PROCEDURE sp_consulta_movimientos_por_producto(
    IN p_id_producto INT
)
BEGIN
    SELECT m.id_movimiento, p.nombre_sal_mineralizada, i.nombre_sede,
           m.cantidad_bultos, m.tipo_mov, m.timestamp_mov,
           u.nombre_completo AS usuario, c.nombre_cliente AS cliente,
           m.motivo
    FROM movimiento_inventario m
    JOIN stock s ON m.id_stock = s.id_stock
    JOIN producto p ON s.id_producto = p.id_producto
    JOIN inventario i ON s.id_inventario = i.id_inventario
    JOIN usuario u ON m.id_usuario = u.id_usuario
    LEFT JOIN cliente c ON m.id_cliente = c.id_cliente
    WHERE p.id_producto = p_id_producto
    ORDER BY m.timestamp_mov DESC;
END$$

-- ------------------------------------------------------------
-- RQF039: Consulta de movimientos filtrados por cliente
-- ------------------------------------------------------------
CREATE PROCEDURE sp_consulta_movimientos_por_cliente(
    IN p_id_cliente INT
)
BEGIN
    SELECT m.id_movimiento, p.nombre_sal_mineralizada, i.nombre_sede,
           m.cantidad_bultos, m.tipo_mov, m.timestamp_mov,
           u.nombre_completo AS usuario, c.nombre_cliente AS cliente,
           m.motivo
    FROM movimiento_inventario m
    JOIN stock s ON m.id_stock = s.id_stock
    JOIN producto p ON s.id_producto = p.id_producto
    JOIN inventario i ON s.id_inventario = i.id_inventario
    JOIN usuario u ON m.id_usuario = u.id_usuario
    JOIN cliente c ON m.id_cliente = c.id_cliente
    WHERE m.id_cliente = p_id_cliente
    ORDER BY m.timestamp_mov DESC;
END$$

DELIMITER ;

-- ============================================================
-- PRUEBAS DE PROCEDIMIENTOS DEL MÓDULO 4 (CONTROL DE INVENTARIO)
-- Ejemplos de uso para cada RQF
-- Incluye consultas antes y después para verificar cambios.
-- ============================================================

-- ------------------------------------------------------------
-- RQF024: Registrar entrada de mercancía (con trazabilidad de lote RQF036)
-- ------------------------------------------------------------
-- Verificar stock antes de la entrada (producto 3, bodega 1)
SELECT s.cantidad_actual FROM stock s 
WHERE s.id_producto = 3 AND s.id_inventario = 1;

-- Registrar entrada de 50 bultos de "Sal 12% granel" (id_producto=3)
CALL sp_registrar_entrada(3, 1, 1, 50, 'Compra a producción propia', 'LOTE-2026-001');

-- Verificar stock después de la entrada (debe incrementar en 50)
SELECT s.cantidad_actual FROM stock s 
WHERE s.id_producto = 3 AND s.id_inventario = 1;

-- ------------------------------------------------------------
-- RQF025 / RQF026 / RQF028: Registrar salida de mercancía
-- ------------------------------------------------------------
-- Verificar stock antes de la salida
SELECT s.cantidad_actual FROM stock s 
WHERE s.id_producto = 3 AND s.id_inventario = 1;

-- Registrar venta de 5 bultos del mismo producto para cliente id=1
CALL sp_registrar_salida(3, 1, 3, 1, 5, 'Venta registrada - pedido normal');

-- Verificar stock después de la salida (debe disminuir en 5)
SELECT s.cantidad_actual FROM stock s 
WHERE s.id_producto = 3 AND s.id_inventario = 1;

-- ------------------------------------------------------------
-- RQF027: Consulta de stock actual
-- ------------------------------------------------------------
-- Consultar stock de un producto específico (id_producto=3)
CALL sp_consultar_stock_actual(3);
-- Consultar stock de todos los productos
CALL sp_consultar_stock_actual(NULL);

-- ------------------------------------------------------------
-- RQF030: Registro de daños o pérdidas
-- ------------------------------------------------------------
-- Verificar stock antes del daño (producto 7, bodega 1)
SELECT s.cantidad_actual FROM stock s 
WHERE s.id_producto = 7 AND s.id_inventario = 1;

-- Reportar daño de 2 bultos de "Sal 8% granel" (id_producto=7)
CALL sp_registrar_danio_perdida(7, 1, 2, 2, 'Bultos rotos por humedad en bodega');

-- Verificar stock después del daño (debe disminuir en 2)
SELECT s.cantidad_actual FROM stock s 
WHERE s.id_producto = 7 AND s.id_inventario = 1;

-- ------------------------------------------------------------
-- RQF031: Alerta de inventario crítico
-- ------------------------------------------------------------
-- Consultar productos con stock bajo o crítico
CALL sp_consultar_inventario_critico();

-- ------------------------------------------------------------
-- RQF032: Configurar stock mínimo
-- ------------------------------------------------------------
-- Verificar mínimo actual del producto 3 en bodega 1
SELECT s.stock_minimo_seguridad FROM stock s 
WHERE s.id_producto = 3 AND s.id_inventario = 1;

-- Cambiar el stock mínimo a 20 bultos
CALL sp_configurar_stock_minimo(3, 1, 20);

-- Verificar que se aplicó el cambio
SELECT s.stock_minimo_seguridad FROM stock s 
WHERE s.id_producto = 3 AND s.id_inventario = 1;

-- ------------------------------------------------------------
-- RQF033: Registro de devoluciones
-- ------------------------------------------------------------
-- Verificar stock antes de la devolución (producto 1, bodega 1)
SELECT s.cantidad_actual FROM stock s 
WHERE s.id_producto = 1 AND s.id_inventario = 1;

-- Cliente id=2 devuelve 1 bulto de "Sal 12% paquete 1kg" (id_producto=1)
CALL sp_registrar_devolucion(1, 1, 4, 2, 1, 'Devolución por paquete defectuoso');

-- Verificar stock después de la devolución (debe aumentar en 1)
SELECT s.cantidad_actual FROM stock s 
WHERE s.id_producto = 1 AND s.id_inventario = 1;

-- ------------------------------------------------------------
-- RQF034: Historial completo de movimientos
-- ------------------------------------------------------------
CALL sp_historial_movimientos();

-- ------------------------------------------------------------
-- RQF035: Ajuste manual de inventario
-- ------------------------------------------------------------
-- Nota: en el script de pruebas anterior se usó id_producto=11 pero texto decía 12.
-- Se usa id_producto=11 (Sal 4% granel) en bodega 2 (id_inventario=2)
-- Verificar stock antes del ajuste
SELECT s.cantidad_actual FROM stock s 
WHERE s.id_producto = 11 AND s.id_inventario = 2;

-- Ajuste positivo de 3 bultos
CALL sp_ajuste_manual_inventario(11, 2, 1, 3, 'Corrección por auditoría física');

-- Verificar stock después del ajuste (debe aumentar en 3)
SELECT s.cantidad_actual FROM stock s 
WHERE s.id_producto = 11 AND s.id_inventario = 2;

-- ------------------------------------------------------------
-- RQF036: Consulta de movimientos por número de lote
-- ------------------------------------------------------------
CALL sp_consultar_movimientos_por_lote('LOTE-2026-001');

-- ------------------------------------------------------------
-- RQF037: Consulta de movimientos por rango de fechas
-- ------------------------------------------------------------
CALL sp_consulta_movimientos_por_fecha('2026-01-01', '2026-03-31');

-- ------------------------------------------------------------
-- RQF038: Consulta de movimientos por producto
-- ------------------------------------------------------------
-- Movimientos del producto id=3
CALL sp_consulta_movimientos_por_producto(3);

-- ------------------------------------------------------------
-- RQF039: Consulta de movimientos por cliente
-- ------------------------------------------------------------
-- Movimientos del cliente id=5
CALL sp_consulta_movimientos_por_cliente(5);