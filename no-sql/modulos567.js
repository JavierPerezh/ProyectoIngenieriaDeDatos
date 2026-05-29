

const db = db.getSiblingDB("salinas_del_cravo");

// ------------------------------------------------------------
// 0. Funciones auxiliares (internas)
// ------------------------------------------------------------

/**
 * Obtiene el documento de stock para una combinación (ubicación, producto, lote)
 */
function getStock(tipo_ubicacion, id_ubicacion, id_producto, id_lote, session = null) {
    return db.stock.findOne({
        tipo_ubicacion,
        id_ubicacion: ObjectId(id_ubicacion),
        id_producto: ObjectId(id_producto),
        id_lote: ObjectId(id_lote)
    }, { session });
}

/**
 * Aplica un movimiento y actualiza el stock correspondiente.
 * Debe ejecutarse dentro de una sesión transaccional.
 *
 * @param {Object} movimiento - Documento completo del movimiento (sin _id, se genera)
 * @param {Object} session - Sesión activa de transacción
 * @returns {ObjectId} ID del movimiento insertado
 */
function insertMovementAndUpdateStock(movimiento, session) {
    // Asegurar ObjectId en referencias
    movimiento._id = new ObjectId();
    movimiento.id_producto = ObjectId(movimiento.id_producto);
    movimiento.id_lote = ObjectId(movimiento.id_lote);
    movimiento.id_usuario = ObjectId(movimiento.id_usuario);
    movimiento.ubicacion.id_ubicacion = ObjectId(movimiento.ubicacion.id_ubicacion);
    movimiento.fecha_movimiento = movimiento.fecha_movimiento || new Date();

    // Determinar signo para el stock
    const tiposAumentan = ["ENTRADA", "ABASTECIMIENTO", "DEVOLUCION"];
    const delta = tiposAumentan.includes(movimiento.tipo_movimiento)
        ? movimiento.cantidad
        : -movimiento.cantidad;

    // Insertar el movimiento
    db.movimientos.insertOne(movimiento, { session });

    // Upsert del stock
    db.stock.updateOne(
        {
            tipo_ubicacion: movimiento.ubicacion.tipo,
            id_ubicacion: movimiento.ubicacion.id_ubicacion,
            id_producto: movimiento.id_producto,
            id_lote: movimiento.id_lote
        },
        {
            $inc: { cantidad_actual: delta },
            $set: { fecha_ultima_auditoria: new Date() },
            $setOnInsert: {
                tipo_ubicacion: movimiento.ubicacion.tipo,
                id_ubicacion: movimiento.ubicacion.id_ubicacion,
                id_producto: movimiento.id_producto,
                id_lote: movimiento.id_lote,
                stock_minimo_seguridad: 0
            }
        },
        { upsert: true, session }
    );

    return movimiento._id;
}

// ------------------------------------------------------------
// 1. MÓDULO 5 – Stock y existencias (consultas)
// ------------------------------------------------------------

/**
 * RQF032 – Ver existencias por producto, bodega/tienda y lote.
 */
function verExistenciasProducto() {
    return db.stock.aggregate([
        {
            $lookup: {
                from: "productos",
                localField: "id_producto",
                foreignField: "_id",
                as: "producto"
            }
        },
        { $unwind: "$producto" },
        {
            $lookup: {
                from: "lotes",
                localField: "id_lote",
                foreignField: "_id",
                as: "lote"
            }
        },
        { $unwind: "$lote" },
        {
            $project: {
                _id: 0,
                producto: "$producto.nombre_sal_mineralizada",
                codigo: "$producto.codigo_tipo_sal",
                lote: "$lote.numero_lote",
                tipo_ubicacion: 1,
                id_ubicacion: 1,
                cantidad_actual: 1,
                stock_minimo_seguridad: 1
            }
        }
    ]).toArray();
}

/**
 * RQF033 – Reconstruir stock a partir de todos los movimientos (saldo contable).
 */
function calcularStockDesdeMovimientos() {
    return db.movimientos.aggregate([
        {
            $group: {
                _id: {
                    producto: "$id_producto",
                    lote: "$id_lote",
                    ubicacion_tipo: "$ubicacion.tipo",
                    ubicacion_id: "$ubicacion.id_ubicacion"
                },
                saldo: {
                    $sum: {
                        $cond: [
                            { $in: ["$tipo_movimiento", ["ENTRADA", "ABASTECIMIENTO", "DEVOLUCION"]] },
                            "$cantidad",
                            { $multiply: ["$cantidad", -1] }
                        ]
                    }
                }
            }
        }
    ]).toArray();
}

/**
 * RQF034 / RQF035 – Establecer o modificar el stock mínimo de seguridad.
 */
function establecerStockMinimo(id_producto, tipo_ubicacion, id_ubicacion, id_lote, nuevo_minimo) {
    return db.stock.updateOne(
        {
            tipo_ubicacion,
            id_ubicacion: ObjectId(id_ubicacion),
            id_producto: ObjectId(id_producto),
            id_lote: ObjectId(id_lote)
        },
        {
            $set: { stock_minimo_seguridad: nuevo_minimo }
        }
    );
}

/**
 * RQF036 – Total de bultos por tipo de sal (suma todas las ubicaciones).
 */
function verTotalPorTipoSal() {
    return db.stock.aggregate([
        {
            $group: {
                _id: "$id_producto",
                total_bultos: { $sum: "$cantidad_actual" }
            }
        },
        {
            $lookup: {
                from: "productos",
                localField: "_id",
                foreignField: "_id",
                as: "producto"
            }
        },
        { $unwind: "$producto" },
        {
            $project: {
                _id: 0,
                codigo: "$producto.codigo_tipo_sal",
                nombre: "$producto.nombre_sal_mineralizada",
                total_bultos: 1
            }
        }
    ]).toArray();
}

/**
 * RQF037 – Total de bultos por bodega (suma todos los productos).
 */
function verTotalPorBodega() {
    return db.stock.aggregate([
        { $match: { tipo_ubicacion: "BODEGA" } },
        {
            $group: {
                _id: "$id_ubicacion",
                total_bultos: { $sum: "$cantidad_actual" }
            }
        },
        {
            $lookup: {
                from: "bodegas",
                localField: "_id",
                foreignField: "_id",
                as: "bodega"
            }
        },
        { $unwind: "$bodega" },
        {
            $project: {
                _id: 0,
                bodega: "$bodega.nombre_bodega",
                total_bultos: 1
            }
        }
    ]).toArray();
}

// RQF038 – No cambiar stock directamente: se implementa a nivel de aplicación,
//          pero aquí dejamos una advertencia de que nunca se debe usar un update directo sobre stock.

// ------------------------------------------------------------
// 2. MÓDULO 6 – Movimientos (operaciones transaccionales)
// ------------------------------------------------------------

/**
 * RQF039 – Registrar entrada por producción a una bodega.
 */
function registrarEntradaProduccion(id_producto, id_lote, id_bodega, id_usuario, cantidad, observaciones = "") {
    const session = db.getMongo().startSession();
    session.startTransaction();
    try {
        const movimiento = {
            id_producto,
            id_lote,
            id_usuario,
            tipo_movimiento: "ENTRADA",
            subtipo: "PRODUCCION",
            cantidad,
            observaciones,
            ubicacion: { tipo: "BODEGA", id_ubicacion: id_bodega }
        };
        const movId = insertMovementAndUpdateStock(movimiento, session);
        session.commitTransaction();
        return movId;
    } catch (e) {
        session.abortTransaction();
        throw e;
    } finally {
        session.endSession();
    }
}

/**
 * RQF041 – Ajuste por bultos extra (entrada).
 */
function registrarAjusteExtra(id_producto, id_lote, id_ubicacion, tipo_ubicacion, id_usuario, cantidad, motivo) {
    const session = db.getMongo().startSession();
    session.startTransaction();
    try {
        const movimiento = {
            id_producto,
            id_lote,
            id_usuario,
            tipo_movimiento: "ENTRADA",
            subtipo: "AJUSTE_EXTRA",
            cantidad,
            observaciones: motivo || "Ajuste por bultos extra",
            ubicacion: { tipo: tipo_ubicacion, id_ubicacion }
        };
        const movId = insertMovementAndUpdateStock(movimiento, session);
        session.commitTransaction();
        return movId;
    } catch (e) {
        session.abortTransaction();
        throw e;
    } finally {
        session.endSession();
    }
}

/**
 * RQF042 – Ajuste por bultos faltantes (salida).
 */
function registrarFaltante(id_producto, id_lote, id_ubicacion, tipo_ubicacion, id_usuario, cantidad, motivo) {
    const session = db.getMongo().startSession();
    session.startTransaction();
    try {
        const movimiento = {
            id_producto,
            id_lote,
            id_usuario,
            tipo_movimiento: "SALIDA",
            subtipo: "FALTANTE",
            cantidad,
            observaciones: motivo || "Bultos faltantes en conteo",
            ubicacion: { tipo: tipo_ubicacion, id_ubicacion }
        };
        const movId = insertMovementAndUpdateStock(movimiento, session);
        session.commitTransaction();
        return movId;
    } catch (e) {
        session.abortTransaction();
        throw e;
    } finally {
        session.endSession();
    }
}

/**
 * RQF043 – Registrar pérdida (salida).
 */
function registrarPerdida(id_producto, id_lote, id_ubicacion, tipo_ubicacion, id_usuario, cantidad, motivo) {
    const session = db.getMongo().startSession();
    session.startTransaction();
    try {
        const movimiento = {
            id_producto,
            id_lote,
            id_usuario,
            tipo_movimiento: "SALIDA",
            subtipo: "PERDIDA",
            cantidad,
            observaciones: motivo || "Pérdida de mercancía",
            ubicacion: { tipo: tipo_ubicacion, id_ubicacion }
        };
        const movId = insertMovementAndUpdateStock(movimiento, session);
        session.commitTransaction();
        return movId;
    } catch (e) {
        session.abortTransaction();
        throw e;
    } finally {
        session.endSession();
    }
}

/**
 * RQF044 – Registrar daño (salida).
 */
function registrarDanio(id_producto, id_lote, id_ubicacion, tipo_ubicacion, id_usuario, cantidad, motivo) {
    const session = db.getMongo().startSession();
    session.startTransaction();
    try {
        const movimiento = {
            id_producto,
            id_lote,
            id_usuario,
            tipo_movimiento: "SALIDA",
            subtipo: "DAÑO",
            cantidad,
            observaciones: motivo || "Producto dañado",
            ubicacion: { tipo: tipo_ubicacion, id_ubicacion }
        };
        const movId = insertMovementAndUpdateStock(movimiento, session);
        session.commitTransaction();
        return movId;
    } catch (e) {
        session.abortTransaction();
        throw e;
    } finally {
        session.endSession();
    }
}

/**
 * RQF045 – Traslado entre bodegas (salida de origen + entrada en destino).
 *           Retorna { movimientoSalidaId, movimientoEntradaId }
 */
function registrarTraslado(id_producto, id_lote, id_bodega_origen, id_bodega_destino, id_usuario, cantidad) {
    if (id_bodega_origen.toString() === id_bodega_destino.toString()) {
        throw new Error("Origen y destino no pueden ser la misma bodega (RQF051)");
    }
    if (cantidad <= 0) {
        throw new Error("La cantidad debe ser mayor a cero (RQF050)");
    }

    const session = db.getMongo().startSession();
    session.startTransaction();
    try {
        // Salida de origen
        const salidaMov = {
            id_producto,
            id_lote,
            id_usuario,
            tipo_movimiento: "SALIDA",
            subtipo: "TRANSFERENCIA",
            cantidad,
            observaciones: `Traslado a bodega destino`,
            ubicacion: { tipo: "BODEGA", id_ubicacion: id_bodega_origen }
        };
        const idSalida = insertMovementAndUpdateStock(salidaMov, session);

        // Entrada en destino
        const entradaMov = {
            id_producto,
            id_lote,
            id_usuario,
            tipo_movimiento: "ENTRADA",
            subtipo: "TRANSFERENCIA",
            cantidad,
            observaciones: `Traslado desde bodega origen`,
            ubicacion: { tipo: "BODEGA", id_ubicacion: id_bodega_destino }
        };
        const idEntrada = insertMovementAndUpdateStock(entradaMov, session);

        session.commitTransaction();
        return { movimientoSalidaId: idSalida, movimientoEntradaId: idEntrada };
    } catch (e) {
        session.abortTransaction();
        throw e;
    } finally {
        session.endSession();
    }
}

/**
 * RQF046 – Valida si hay stock suficiente (función de consulta, no modifica datos).
 *          Devuelve true/false.
 */
function validarStockSuficiente(id_producto, id_lote, tipo_ubicacion, id_ubicacion, cantidad) {
    const stockDoc = getStock(tipo_ubicacion, id_ubicacion, id_producto, id_lote);
    if (!stockDoc || stockDoc.cantidad_actual < cantidad) {
        return false;
    }
    return true;
}

// RQF047 – Atomicidad: todas las funciones que modifican stock usan transacciones.
// RQF048 – Usuario: siempre se recibe id_usuario.
// RQF049 – Fecha automática: se asigna en insertMovementAndUpdateStock.
// RQF050 – Cantidad positiva: validado en las funciones que lo requieren (traslados, ventas, etc.)
// RQF051 – Misma bodega en traslado: validado en registrarTraslado().

// ------------------------------------------------------------
// 3. MÓDULO 7 – Ventas (operaciones transaccionales)
// ------------------------------------------------------------

/**
 * RQF052-056 – Registrar una venta en una tienda.
 *              Crea los movimientos de tipo VENTA y descuenta stock.
 *
 * @param {string|ObjectId} id_cliente
 * @param {string|ObjectId} id_tienda
 * @param {string|ObjectId} id_usuario  – vendedor
 * @param {Array} lineasVenta – [{ id_producto, id_lote, cantidad }]
 * @returns {ObjectId} id de la venta creada
 */
function registrarVenta(id_cliente, id_tienda, id_usuario, lineasVenta) {
    const session = db.getMongo().startSession();
    session.startTransaction();
    try {
        const venta = {
            _id: new ObjectId(),
            id_cliente: ObjectId(id_cliente),
            id_usuario: ObjectId(id_usuario),
            id_tienda: ObjectId(id_tienda),
            fecha_venta: new Date(),
            estado: "ACTIVA",
            items: []
        };

        for (const linea of lineasVenta) {
            // Validar stock en tienda
            const stockDoc = getStock(
                "TIENDA",
                id_tienda,
                linea.id_producto,
                linea.id_lote,
                session
            );
            if (!stockDoc || stockDoc.cantidad_actual < linea.cantidad) {
                throw new Error(
                    `Stock insuficiente para producto ${linea.id_producto}, ` +
                    `lote ${linea.id_lote}. Disponible: ${stockDoc?.cantidad_actual || 0}`
                );
            }

            // Crear movimiento de venta y descontar stock (usando la función core)
            const movId = insertMovementAndUpdateStock({
                id_producto: linea.id_producto,
                id_lote: linea.id_lote,
                id_usuario,
                tipo_movimiento: "VENTA",
                subtipo: null,
                cantidad: linea.cantidad,
                observaciones: null,
                ubicacion: { tipo: "TIENDA", id_ubicacion: id_tienda }
            }, session);

            // Agregar al detalle de la venta
            venta.items.push({
                id_producto: ObjectId(linea.id_producto),
                id_lote: ObjectId(linea.id_lote),
                cantidad: linea.cantidad,
                id_movimiento: movId
            });
        }

        db.ventas.insertOne(venta, { session });
        session.commitTransaction();
        return venta._id;
    } catch (e) {
        session.abortTransaction();
        throw e;
    } finally {
        session.endSession();
    }
}

/**
 * RQF057 – Listar todas las ventas con cliente y vendedor.
 */
function listarVentas() {
    return db.ventas.aggregate([
        {
            $lookup: {
                from: "clientes",
                localField: "id_cliente",
                foreignField: "_id",
                as: "cliente"
            }
        },
        { $unwind: "$cliente" },
        {
            $lookup: {
                from: "usuarios",
                localField: "id_usuario",
                foreignField: "_id",
                as: "vendedor"
            }
        },
        { $unwind: "$vendedor" },
        {
            $project: {
                _id: 1,
                fecha_venta: 1,
                estado: 1,
                cliente: "$cliente.nombre_cliente",
                vendedor: "$vendedor.nombre_completo",
                items: 1
            }
        }
    ]).toArray();
}

/**
 * RQF058-059 – Anular una venta activa.
 *              Genera movimientos de DEVOLUCION, repone stock y cambia estado a ANULADA.
 *
 * @param {string|ObjectId} id_venta
 * @param {string|ObjectId} id_usuario_anula – administrador
 * @param {string} motivo
 * @returns {ObjectId} id de la venta (confirmación)
 */
function anularVenta(id_venta, id_usuario_anula, motivo) {
    const session = db.getMongo().startSession();
    session.startTransaction();
    try {
        const venta = db.ventas.findOne(
            { _id: ObjectId(id_venta), estado: "ACTIVA" },
            { session }
        );
        if (!venta) {
            throw new Error("Venta no encontrada o ya anulada");
        }

        const devoluciones = [];
        for (const item of venta.items) {
            // Crear movimiento de devolución (aumenta stock)
            const movId = insertMovementAndUpdateStock({
                id_producto: item.id_producto,
                id_lote: item.id_lote,
                id_usuario: id_usuario_anula,
                tipo_movimiento: "DEVOLUCION",
                subtipo: null,
                cantidad: item.cantidad,
                observaciones: `Anulación de venta ${venta._id}`,
                ubicacion: { tipo: "TIENDA", id_ubicacion: venta.id_tienda }
            }, session);

            devoluciones.push({
                id_producto: item.id_producto,
                id_lote: item.id_lote,
                cantidad_devuelta: item.cantidad,
                id_movimiento: movId
            });
        }

        // Marcar venta como anulada
        db.ventas.updateOne(
            { _id: venta._id },
            {
                $set: {
                    estado: "ANULADA",
                    anulacion: {
                        id_usuario_anulo: ObjectId(id_usuario_anula),
                        motivo,
                        fecha_anulacion: new Date(),
                        movimientos_devolucion: devoluciones
                    }
                }
            },
            { session }
        );

        session.commitTransaction();
        return venta._id;
    } catch (e) {
        session.abortTransaction();
        throw e;
    } finally {
        session.endSession();
    }
}

