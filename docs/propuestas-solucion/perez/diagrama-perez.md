# Diagrama de flujo Javier Pérez

Codificado en mermaid y mostrado como archivo markDown. 

```mermaid
flowchart TD
    A[Inicio: Usuario inicia sesión] --> B{¿Credenciales válidas?}
    B -->|No| C[Mostrar error de autenticación]
    C --> A
    B -->|Sí| D{¿Rol de usuario?}
    
    D -->|Administrador| E[MENÚ ADMINISTRADOR]
    D -->|Vendedor| F[MENÚ VENDEDOR]
    
    E --> G[Gestión de Usuarios]
    E --> H[Gestión de Clientes]
    E --> I[Gestión de Productos]
    E --> J[Gestión de Inventario]
    E --> K[Reportes y Respaldos]
    
    F --> L[Registrar Cliente]
    F --> M[Consultar Catálogo]
    F --> N[Registrar Venta]
    F --> O[Consultar Historial]
    
    N --> P[Seleccionar productos y cantidades]
    P --> Q[Calcular total con descuentos]
    Q --> R[Registrar forma de pago]
    R --> S[Generar comprobante]
    S --> T[Actualizar inventario automáticamente en BD]
    T --> U[¿Otra venta?]
    U -->|Sí| P
    U -->|No| F
    
    G --> V[(Base de Datos Relacional - PostgreSQL)]
    H --> V
    I --> V
    J --> V
    K --> V
    L --> V
    M --> V
    O --> V
