# Diccionario de Datos - Salinas del Cravo

Base de datos: `salinas_del_cravo`

## Tabla: categoria
| Campo | Tipo | Nulo | Predeterminado | Clave | Referencia | Descripción |
|-------|------|------|----------------|-------|------------|-------------|
| id_categoria | INT | NO | AUTO_INCREMENT | PK | - | Identificador único de la categoría |
| nombre_categoria | VARCHAR(100) | NO | - | UNIQUE | - | Nombre comercial de la categoría (ej. Sal Mineralizada 12%) |
| descripcion_uso | VARCHAR(255) | NO | - | - | - | Descripción del uso recomendado de la sal |
| porcentaje_fosforo | DECIMAL(4,1) | NO | - | - | - | Porcentaje de fósforo contenido en la sal |

## Tabla: producto
| Campo | Tipo | Nulo | Predeterminado | Clave | Referencia | Descripción |
|-------|------|------|----------------|-------|------------|-------------|
| id_producto | INT | NO | AUTO_INCREMENT | PK | - | Identificador único del producto |
| id_categoria | INT | NO | - | FK | categoria(id_categoria) | Categoría a la que pertenece el producto |
| nombre_sal_mineralizada | VARCHAR(150) | NO | - | - | - | Nombre completo del producto (incluye concentración y presentación) |
| peso_bulto_kg | DECIMAL(6,2) | NO | - | - | - | Peso en kilogramos del bulto o unidad de venta |
| unidad_medida | VARCHAR(50) | NO | - | - | - | Tipo de unidad (1kg, 5kg, granel, mochila) |
| paquetes_por_bulto | INT | NO | - | - | - | Cantidad de paquetes individuales contenidos en un bulto |
| descontinuado | TINYINT(1) | NO | 0 | - | - | Indica si el producto ya no se comercializa (1=descontinuado, 0=activo) |

## Tabla: inventario
| Campo | Tipo | Nulo | Predeterminado | Clave | Referencia | Descripción |
|-------|------|------|----------------|-------|------------|-------------|
| id_inventario | INT | NO | AUTO_INCREMENT | PK | - | Identificador único de la bodega/sede |
| nombre_sede | VARCHAR(100) | NO | - | - | - | Nombre de la bodega (ej. Bodega Principal Sogamoso) |
| direccion_fisica | VARCHAR(255) | NO | - | - | - | Dirección física completa de la bodega |
| capacidad_maxima_bultos | INT | NO | - | - | - | Capacidad máxima de almacenamiento en bultos |
| estado_operativo | TINYINT(1) | NO | 1 | - | - | Indica si la bodega está operativa (1=activa, 0=inactiva) |

## Tabla: stock
| Campo | Tipo | Nulo | Predeterminado | Clave | Referencia | Descripción |
|-------|------|------|----------------|-------|------------|-------------|
| id_stock | INT | NO | AUTO_INCREMENT | PK | - | Identificador único del registro de stock |
| id_producto | INT | NO | - | FK | producto(id_producto) | Producto al que corresponde el stock |
| id_inventario | INT | NO | - | FK | inventario(id_inventario) | Bodega donde se almacena el producto |
| cantidad_actual | INT | NO | 0 | - | - | Cantidad de bultos disponibles actualmente |
| stock_minimo_seguridad | INT | NO | 10 | - | - | Nivel mínimo de stock antes de generar alerta |
| fecha_ultima_auditoria | DATE | NO | - | - | - | Fecha de la última auditoría física realizada |

**Restricciones adicionales:**
- `UNIQUE (id_producto, id_inventario)`: No puede haber dos registros del mismo producto en la misma bodega.
- `CHECK (cantidad_actual >= 0)`: El stock no puede ser negativo.
- `CHECK (stock_minimo_seguridad >= 0)`: El mínimo de seguridad no puede ser negativo.

## Tabla: usuario
| Campo | Tipo | Nulo | Predeterminado | Clave | Referencia | Descripción |
|-------|------|------|----------------|-------|------------|-------------|
| id_usuario | INT | NO | AUTO_INCREMENT | PK | - | Identificador único del usuario |
| nombre_completo | VARCHAR(150) | NO | - | - | - | Nombre completo del usuario |
| username | VARCHAR(60) | NO | - | UNIQUE | - | Nombre de usuario para autenticación |
| password_hash | VARCHAR(255) | NO | - | - | - | Hash SHA2 de la contraseña |
| estado_activo | TINYINT(1) | NO | 1 | - | - | Indica si el usuario está activo (1=activo, 0=inactivo) |
| rol | ENUM('ADMIN','VENDEDOR') | NO | - | - | - | Rol del usuario en el sistema |

## Tabla: administrador
| Campo | Tipo | Nulo | Predeterminado | Clave | Referencia | Descripción |
|-------|------|------|----------------|-------|------------|-------------|
| id_usuario | INT | NO | - | PK, FK | usuario(id_usuario) | Identificador del usuario con rol ADMIN |
| ultimo_acceso_admin | DATETIME | SI | NULL | - | - | Fecha y hora del último acceso al sistema |

## Tabla: vendedor
| Campo | Tipo | Nulo | Predeterminado | Clave | Referencia | Descripción |
|-------|------|------|----------------|-------|------------|-------------|
| id_usuario | INT | NO | - | PK, FK | usuario(id_usuario) | Identificador del usuario con rol VENDEDOR |
| codigo_terminal | VARCHAR(20) | NO | - | UNIQUE | - | Código único de la terminal o dispositivo del vendedor |
| ventas_mes_actual | INT | NO | 0 | - | - | Cantidad de ventas realizadas en el mes en curso |

## Tabla: cliente
| Campo | Tipo | Nulo | Predeterminado | Clave | Referencia | Descripción |
|-------|------|------|----------------|-------|------------|-------------|
| id_cliente | INT | NO | AUTO_INCREMENT | PK | - | Identificador único del cliente |
| nit_cedula | VARCHAR(20) | NO | - | UNIQUE | - | NIT o cédula del cliente (identificación única) |
| nombre_cliente | VARCHAR(150) | NO | - | - | - | Nombre comercial o razón social |
| telefono | VARCHAR(20) | SI | NULL | - | - | Número de contacto del cliente |
| direccion_entrega | VARCHAR(255) | SI | NULL | - | - | Dirección física para la entrega de pedidos |
| tipo | ENUM('VETERINARIA','GANADERO') | NO | 'VETERINARIA' | - | - | Tipo de cliente (veterinaria o ganadero directo) |
| estado_activo | TINYINT(1) | NO | 1 | - | - | Indica si el cliente está activo (1=activo, 0=inactivo) |

## Tabla: movimiento_inventario
| Campo | Tipo | Nulo | Predeterminado | Clave | Referencia | Descripción |
|-------|------|------|----------------|-------|------------|-------------|
| id_movimiento | INT | NO | AUTO_INCREMENT | PK | - | Identificador único del movimiento |
| id_stock | INT | NO | - | FK | stock(id_stock) | Registro de stock afectado |
| id_usuario | INT | NO | - | FK | usuario(id_usuario) | Usuario que ejecuta el movimiento |
| id_cliente | INT | SI | NULL | FK | cliente(id_cliente) | Cliente asociado (obligatorio en SALIDA) |
| timestamp_mov | DATETIME | NO | CURRENT_TIMESTAMP | - | - | Fecha y hora en que se registra el movimiento |
| cantidad_bultos | INT | NO | - | - | - | Cantidad de bultos involucrados en la transacción |
| tipo_mov | ENUM('ENTRADA','SALIDA','AJUSTE') | NO | - | - | - | Tipo de movimiento de inventario |
| motivo | VARCHAR(255) | SI | NULL | - | - | Razón o justificación del movimiento (puede incluir lote) |

**Restricciones adicionales:**
- `CHECK (cantidad_bultos > 0)`: La cantidad debe ser positiva.
- `CHECK (tipo_mov <> 'SALIDA' OR id_cliente IS NOT NULL)`: Las salidas deben tener un cliente asociado.

## Tabla: reporte
| Campo | Tipo | Nulo | Predeterminado | Clave | Referencia | Descripción |
|-------|------|------|----------------|-------|------------|-------------|
| id_reporte | INT | NO | AUTO_INCREMENT | PK | - | Identificador único del reporte |
| id_movimiento | INT | NO | - | FK, UNIQUE | movimiento_inventario(id_movimiento) | Movimiento al que corresponde el reporte |
| fecha_emision | DATETIME | NO | CURRENT_TIMESTAMP | - | - | Fecha y hora de generación del reporte |
| rango_fechas | VARCHAR(100) | SI | NULL | - | - | Período que cubre el reporte (mes en formato YYYY-MM-01 / YYYY-MM-DD) |
| tipo_reporte | ENUM('STOCK','SALIDAS','HISTORIAL') | NO | - | - | - | Clasificación del reporte según el tipo de movimiento |
| resumen | TEXT | SI | NULL | - | - | Descripción automática generada a partir del movimiento |
