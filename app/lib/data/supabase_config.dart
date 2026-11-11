/// Se pasan al compilar:
///   flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJ...
/// La anon key es pública por diseño: la seguridad real la dan las reglas (RLS) de la base.
class SupabaseConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static bool get isSet => url.isNotEmpty && anonKey.isNotEmpty;
}
