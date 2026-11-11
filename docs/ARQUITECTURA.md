# Cuentas Claras · arquitectura de la app real

## Qué hay en este repo

| Carpeta | Qué es |
|---|---|
| `index.html` | El prototipo web (se ve en GitHub Pages). Sirve de especificación de pantallas y de comportamiento. |
| `supabase/migrations` | El esquema de la base (tablas, seguridad por fila, funciones). |
| `supabase/tests` | Pruebas del esquema: contactos, solicitudes, grupos, pagos, saldos, privacidad. |
| `app/` | La app Flutter (Android y web). |
| `.github/workflows/ci.yml` | Corre las pruebas y compila el APK en GitHub. |

## Capas

1. **Lógica pura** (`app/lib/core`): plata en centavos, reparto, saldos, "quién le paga a quién", hilo de cuotas.
   Sin pantallas ni red. Cada función tiene pruebas y se porta del prototipo con los mismos resultados.
2. **Datos** (`app/lib/data`): habla con Supabase. Nada de lógica de negocio acá.
3. **Interfaz** (`app/lib/ui`): pantallas. Solo muestra y pide acciones.

## Reglas de diseño

- **Plata siempre en centavos** (`bigint` en la base, `int` en Dart). Nunca decimales.
- **No se guarda** número de tarjeta, DNI, CUIL, domicilio ni CBU. De otra persona, solo mail y nombre. Del alias de transferencia, solo el alias.
- **Lo personal lo ve solo su dueño** (resúmenes, gastos, pagos personales). **Lo de un grupo lo ven solo sus miembros.**
- **Todo lo que mueve plata entre personas pasa por funciones de la base** (`save_group_expense`, `register_group_payment`, `respond_group_payment`…): así queda registrado quién hizo cada cosa y nadie lo puede falsificar desde la app.
- **Pagos con confirmación:** quien registra un pago no lo puede confirmar; lo confirma la otra parte. Mientras tanto la deuda no baja.
- **Alias de transferencia:** solo lo edita su dueño. Lo ven los contactos mutuos y los compañeros de grupo; no se lee por tabla sino por `visible_aliases()`.
- **Contactos:** cada usuario tiene los suyos. Si el mail es de otro usuario, se manda una solicitud. Estados: `mutual`, `pending`, `rejected`, `cut` (te sacó de sus contactos), `plain` (no usa la app). Quitar un contacto no borra deudas.
- **Sin IA y sin costo:** los PDF se leen con reglas, en el teléfono. No se sube el PDF a ningún servidor.

## Orden de trabajo

1. ✅ Esquema de base + pruebas.
2. ✅ Núcleo de plata, saldos y cuotas en Dart + pruebas. Login y pantalla de prueba.
3. Portar el lector de resúmenes (Galicia Visa, Galicia Mastercard, Mercado Pago) a Dart, validado con los PDF reales.
4. Pantallas: Inicio, Cargar, Gastos, Grupos, Contactos, Ajustes.
5. Guardar lo personal en Supabase (resúmenes, cuotas, gastos manuales) y migrar desde el prototipo.
6. Web (Flutter web) y APK firmado.

## Cómo conectar tu proyecto de Supabase

1. Creá el proyecto en supabase.com (plan gratuito).
2. En **SQL Editor**, pegá el contenido de `supabase/migrations/0001_init.sql` y ejecutalo.
3. En **Project Settings → API**, copiá la **Project URL** y la clave **anon public**.
4. En GitHub: **Settings → Secrets and variables → Actions → New repository secret**, y creá `SUPABASE_URL` y `SUPABASE_ANON_KEY`.
5. Para probar en tu computadora: `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`

La clave anon es pública por diseño. **Nunca** pegues la clave `service_role` en la app ni en GitHub.
