// ============================================================
// módulos 5, 6 y 7 
// Base de datos: salinas_del_cravo
// ============================================================
const db = db.getSiblingDB("salinas_del_cravo");

// ---------- AUXILIAR ----------
function getStock(tipo_ubicacion, id_ubicacion, id_producto, id_lote) {
    return db.stock.findOne({
        tipo_ubicacion,
        id_ubicacion: ObjectId(id_ubicacion),
        id_producto: ObjectId(id_producto),
        id_lote: ObjectId(id_lote)
    });
}

function insertMovementAndUpdateStock(movimiento) {
    movimiento._id = new ObjectId();
    movimiento.id_producto = ObjectId(movimiento.id_producto);
    movimiento.id_lote = ObjectId(movimiento.id_lote);
    movimiento.id_usuario = ObjectId(movimiento.id_usuario);
    movimiento.ubicacion.id_ubicacion = ObjectId(movimiento.ubicacion.id_ubicacion);
    movimiento.fecha_movimiento = movimiento.fecha_movimiento || new Date();

    const tiposAumentan = ["ENTRADA", "ABASTECIMIENTO", "DEVOLUCION"];
    const delta = tiposAumentan.includes(movimiento.tipo_movimiento)
        ? movimiento.cantidad
        : -movimiento.cantidad;

    db.movimientos.insertOne(movimiento);
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
        { upsert: true }
    );
    return movimiento._id;
}

// ---------- MÓDULO 5 ----------
function verExistenciasProducto() {
    return db.stock.aggregate([
        { $lookup: { from: "productos", localField: "id_producto", foreignField: "_id", as: "producto" } },
        { $unwind: "$producto" },
        { $lookup: { from: "lotes", localField: "id_lote", foreignField: "_id", as: "lote" } },
        { $unwind: "$lote" },
        { $project: { _id:0, producto:"$producto.nombre_sal_mineralizada", codigo:"$producto.codigo_tipo_sal", lote:"$lote.numero_lote", tipo_ubicacion:1, id_ubicacion:1, cantidad_actual:1, stock_minimo_seguridad:1 } }
    ]).toArray();
}

function verTotalPorTipoSal() {
    return db.stock.aggregate([
        { $group: { _id:"$id_producto", total_bultos: { $sum: "$cantidad_actual" } } },
        { $lookup: { from:"productos", localField:"_id", foreignField:"_id", as:"producto" } },
        { $unwind:"$producto" },
        { $project: { _id:0, codigo:"$producto.codigo_tipo_sal", nombre:"$producto.nombre_sal_mineralizada", total_bultos:1 } }
    ]).toArray();
}

function verTotalPorBodega() {
    return db.stock.aggregate([
        { $match: { tipo_ubicacion:"BODEGA" } },
        { $group: { _id:"$id_ubicacion", total_bultos: { $sum:"$cantidad_actual" } } },
        { $lookup: { from:"bodegas", localField:"_id", foreignField:"_id", as:"bodega" } },
        { $unwind:"$bodega" },
        { $project: { _id:0, bodega:"$bodega.nombre_bodega", total_bultos:1 } }
    ]).toArray();
}

function establecerStockMinimo(id_producto, tipo_ubicacion, id_ubicacion, id_lote, nuevo_minimo) {
    return db.stock.updateOne(
        {
            tipo_ubicacion,
            id_ubicacion: ObjectId(id_ubicacion),
            id_producto: ObjectId(id_producto),
            id_lote: ObjectId(id_lote)
        },
        {
            $set: { stock_minimo_seguridad: nuevo_minimo },
            $setOnInsert: {
                tipo_ubicacion,
                id_ubicacion: ObjectId(id_ubicacion),
                id_producto: ObjectId(id_producto),
                id_lote: ObjectId(id_lote),
                cantidad_actual: 0,
                fecha_ultima_auditoria: new Date()
            }
        },
        { upsert: true }
    );
}

// ---------- MÓDULO 6 ----------
function registrarEntradaProduccion(id_producto, id_lote, id_bodega, id_usuario, cantidad, obs="") {
    const mov = {
        id_producto, id_lote, id_usuario,
        tipo_movimiento: "ENTRADA", subtipo: "PRODUCCION", cantidad,
        observaciones: obs,
        ubicacion: { tipo:"BODEGA", id_ubicacion: id_bodega }
    };
    return insertMovementAndUpdateStock(mov);
}
function registrarAjusteExtra(id_producto, id_lote, id_ubicacion, tipo_ubicacion, id_usuario, cantidad, motivo) {
    const mov = {
        id_producto, id_lote, id_usuario,
        tipo_movimiento:"ENTRADA", subtipo:"AJUSTE_EXTRA", cantidad,
        observaciones: motivo || "Ajuste extra",
        ubicacion: { tipo: tipo_ubicacion, id_ubicacion }
    };
    return insertMovementAndUpdateStock(mov);
}
function registrarFaltante(id_producto, id_lote, id_ubicacion, tipo_ubicacion, id_usuario, cantidad, motivo) {
    const mov = {
        id_producto, id_lote, id_usuario,
        tipo_movimiento:"SALIDA", subtipo:"FALTANTE", cantidad,
        observaciones: motivo || "Faltante",
        ubicacion: { tipo: tipo_ubicacion, id_ubicacion }
    };
    return insertMovementAndUpdateStock(mov);
}
function registrarPerdida(id_producto, id_lote, id_ubicacion, tipo_ubicacion, id_usuario, cantidad, motivo) {
    const mov = {
        id_producto, id_lote, id_usuario,
        tipo_movimiento:"SALIDA", subtipo:"PERDIDA", cantidad,
        observaciones: motivo || "Pérdida",
        ubicacion: { tipo: tipo_ubicacion, id_ubicacion }
    };
    return insertMovementAndUpdateStock(mov);
}
function registrarDanio(id_producto, id_lote, id_ubicacion, tipo_ubicacion, id_usuario, cantidad, motivo) {
    const mov = {
        id_producto, id_lote, id_usuario,
        tipo_movimiento:"SALIDA", subtipo:"DAÑO", cantidad,
        observaciones: motivo || "Daño",
        ubicacion: { tipo: tipo_ubicacion, id_ubicacion }
    };
    return insertMovementAndUpdateStock(mov);
}
function registrarTraslado(id_producto, id_lote, id_org, id_dst, id_usuario, cantidad) {
    if (id_org.toString() === id_dst.toString()) throw new Error("Misma bodega no permitido");
    if (cantidad <= 0) throw new Error("Cantidad debe ser >0");

    const salidaId = insertMovementAndUpdateStock({
        id_producto, id_lote, id_usuario,
        tipo_movimiento:"SALIDA", subtipo:"TRANSFERENCIA", cantidad,
        observaciones: "Traslado a destino",
        ubicacion: { tipo:"BODEGA", id_ubicacion: id_org }
    });
    const entradaId = insertMovementAndUpdateStock({
        id_producto, id_lote, id_usuario,
        tipo_movimiento:"ENTRADA", subtipo:"TRANSFERENCIA", cantidad,
        observaciones: "Traslado desde origen",
        ubicacion: { tipo:"BODEGA", id_ubicacion: id_dst }
    });
    return { movimientoSalidaId: salidaId, movimientoEntradaId: entradaId };
}
function validarStockSuficiente(id_producto, id_lote, tipo_ubicacion, id_ubicacion, cantidad) {
    const s = getStock(tipo_ubicacion, id_ubicacion, id_producto, id_lote);
    return s && s.cantidad_actual >= cantidad;
}

// ---------- MÓDULO 7 ----------
function registrarVenta(id_cliente, id_tienda, id_usuario, lineas) {
    const venta = {
        _id: new ObjectId(),
        id_cliente: ObjectId(id_cliente),
        id_usuario: ObjectId(id_usuario),
        id_tienda: ObjectId(id_tienda),
        fecha_venta: new Date(),
        estado: "ACTIVA",
        items: []
    };
    for (let linea of lineas) {
        let s = getStock("TIENDA", id_tienda, linea.id_producto, linea.id_lote);
        if (!s || s.cantidad_actual < linea.cantidad)
            throw new Error(`Stock insuficiente para ${linea.id_producto}, lote ${linea.id_lote}`);
        const movId = insertMovementAndUpdateStock({
            id_producto: linea.id_producto, id_lote: linea.id_lote, id_usuario,
            tipo_movimiento:"VENTA", subtipo:null, cantidad: linea.cantidad,
            observaciones: null,
            ubicacion: { tipo:"TIENDA", id_ubicacion: id_tienda }
        });
        venta.items.push({
            id_producto: ObjectId(linea.id_producto),
            id_lote: ObjectId(linea.id_lote),
            cantidad: linea.cantidad,
            id_movimiento: movId
        });
    }
    db.ventas.insertOne(venta);
    return venta._id;
}
function listarVentas() {
    return db.ventas.aggregate([
        { $lookup:{ from:"clientes", localField:"id_cliente", foreignField:"_id", as:"cliente" } },
        { $unwind:"$cliente" },
        { $lookup:{ from:"usuarios", localField:"id_usuario", foreignField:"_id", as:"vendedor" } },
        { $unwind:"$vendedor" },
        { $project:{ _id:1, fecha_venta:1, estado:1, cliente:"$cliente.nombre_cliente", vendedor:"$vendedor.nombre_completo", items:1 } }
    ]).toArray();
}
function anularVenta(id_venta, id_usuario_anula, motivo) {
    const venta = db.ventas.findOne({ _id: ObjectId(id_venta), estado: "ACTIVA" });
    if (!venta) throw new Error("Venta no encontrada o ya anulada");
    const devoluciones = [];
    for (let item of venta.items) {
        const movId = insertMovementAndUpdateStock({
            id_producto: item.id_producto, id_lote: item.id_lote, id_usuario: id_usuario_anula,
            tipo_movimiento:"DEVOLUCION", subtipo:null, cantidad: item.cantidad,
            observaciones: `Anulación venta ${venta._id}`,
            ubicacion: { tipo:"TIENDA", id_ubicacion: venta.id_tienda }
        });
        devoluciones.push({
            id_producto: item.id_producto,
            id_lote: item.id_lote,
            cantidad_devuelta: item.cantidad,
            id_movimiento: movId
        });
    }
    db.ventas.updateOne(
        { _id: venta._id },
        { $set: { estado:"ANULADA", anulacion: { id_usuario_anulo: ObjectId(id_usuario_anula), motivo, fecha_anulacion: new Date(), movimientos_devolucion: devoluciones } } }
    );
    return venta._id;
}
