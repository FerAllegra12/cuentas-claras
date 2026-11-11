/// Conexión con Supabase.
///
/// Estos dos datos son públicos por diseño: la clave "publishable" solo deja hacer lo que
/// permiten las reglas de seguridad (RLS) de la base. La clave "secret" / "service_role"
/// NUNCA va en la app ni en GitHub.
///
/// Se pueden pisar al compilar:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://kslmbvghezzxadqekwws.supabase.co',
  );
  static const anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_nqXs-jfeuMnER4g9OP1RUQ_Ey0E8fD3',
  );
  static bool get isSet => url.isNotEmpty && anonKey.isNotEmpty;
}
