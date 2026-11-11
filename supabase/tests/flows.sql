-- Pruebas de comportamiento del esquema. Se corren contra un Postgres con un `auth` simulado.
-- Cada bloque actúa como un usuario distinto (rol authenticated + sub del JWT).
\set ON_ERROR_STOP on
\set fercho '''11111111-1111-1111-1111-111111111111'''
\set pepito '''22222222-2222-2222-2222-222222222222'''
\set juancito '''33333333-3333-3333-3333-333333333333'''
\set bren '''44444444-4444-4444-4444-444444444444'''

reset role;
insert into auth.users (id, email, raw_user_meta_data) values
  (:fercho, 'Fercho@prueba.com', '{"name":"Fercho"}'),
  (:pepito, 'pepito@prueba.com', '{"name":"Pepito"}'),
  (:juancito, 'juancito@prueba.com', '{"name":"Juancito"}'),
  (:bren, 'bren@prueba.com', '{}');

create or replace function pg_temp.as_user(u uuid) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', u::text, false); end $$;
create or replace function pg_temp.ok(cond boolean, msg text) returns void language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'FALLÓ: %', msg; end if; raise notice 'ok: %', msg; end $$;

-- ---------- perfiles ----------
do $$ begin
  perform pg_temp.ok((select count(*) from public.profiles) = 4, 'se crearon 4 perfiles');
  perform pg_temp.ok((select display_name from public.profiles where email='bren@prueba.com') = 'bren', 'nombre por defecto = parte del mail');
  perform pg_temp.ok((select email from public.profiles where display_name='Fercho') = 'fercho@prueba.com', 'mail en minúsculas');
end $$;

-- ---------- contactos y solicitudes (recorrido Fercho → Pepito) ----------
set role authenticated;
select pg_temp.as_user(:fercho);
select public.add_contact('Pepito', 'Pepito@prueba.com');
do $$ begin
  perform pg_temp.ok((select state from public.my_contact_links() l join public.contacts c on c.id=l.contact_id where c.alias='Pepito') = 'pending', 'Fercho ve a Pepito pendiente');
end $$;
select pg_temp.as_user(:pepito);
do $$ begin
  perform pg_temp.ok((select count(*) from public.friend_requests where status='pending' and to_user='22222222-2222-2222-2222-222222222222') = 1, 'Pepito ve 1 solicitud');
  perform pg_temp.ok((select count(*) from public.contacts) = 0, 'Pepito no ve contactos ajenos');
end $$;
select public.respond_friend_request((select id from public.friend_requests where status='pending'), true);
do $$ begin
  perform pg_temp.ok((select alias from public.contacts) = 'Fercho', 'al aceptar, Pepito tiene a Fercho como contacto');
  perform pg_temp.ok((select state from public.my_contact_links()) = 'mutual', 'Pepito: relación mutua');
end $$;
select pg_temp.as_user(:fercho);
do $$ begin
  perform pg_temp.ok((select state from public.my_contact_links()) = 'mutual', 'Fercho: relación mutua, ya no está pendiente');
end $$;
-- Pepito quita a Fercho
select pg_temp.as_user(:pepito);
select public.remove_contact((select id from public.contacts where alias='Fercho'));
select pg_temp.as_user(:fercho);
do $$ begin
  perform pg_temp.ok((select state from public.my_contact_links()) = 'cut', 'Fercho ve que Pepito lo sacó (cut)');
end $$;
select public.reinvite_contact((select id from public.contacts where alias='Pepito'));
do $$ begin
  perform pg_temp.ok((select state from public.my_contact_links()) = 'pending', 'tras volver a invitar queda pendiente');
end $$;
select pg_temp.as_user(:pepito);
select public.respond_friend_request((select id from public.friend_requests where status='pending'), false);
select pg_temp.as_user(:fercho);
do $$ begin
  perform pg_temp.ok((select state from public.my_contact_links()) = 'rejected', 'si rechaza, Fercho ve "rechazó"');
end $$;
-- contacto que no usa la app: sin solicitud
select public.add_contact('Vale', 'vale@ejemplo.com');
do $$ begin
  perform pg_temp.ok((select state from public.my_contact_links() l join public.contacts c on c.id=l.contact_id where c.alias='Vale') = 'plain', 'Vale (no usa la app) es plain');
  perform pg_temp.ok((select count(*) from public.friend_requests where from_user='11111111-1111-1111-1111-111111111111') = 2, 'no se mandó solicitud a Vale (solo las 2 de Pepito)');
end $$;

-- ---------- alias: solo el dueño lo edita; los demás lo ven por regla ----------
select pg_temp.as_user(:pepito);
update public.profiles set transfer_alias = 'pepito.mp' where id = :pepito;
select pg_temp.as_user(:fercho);
do $$ begin
  begin update public.profiles set transfer_alias = 'hackeado' where id = '22222222-2222-2222-2222-222222222222';
  exception when others then null; end;
  perform pg_temp.ok((select transfer_alias from public.visible_aliases() where user_id='22222222-2222-2222-2222-222222222222') is null, 'Fercho (sin vínculo vigente ni grupo) no ve el alias de Pepito');
  begin perform transfer_alias from public.profiles; raise exception 'FALLÓ: se pudo leer transfer_alias por tabla';
  exception when insufficient_privilege then raise notice 'ok: transfer_alias no se lee por tabla'; end;
end $$;
reset role;
do $$ begin perform pg_temp.ok((select transfer_alias from public.profiles where id='22222222-2222-2222-2222-222222222222') = 'pepito.mp', 'el alias de Pepito no se pudo pisar'); end $$;

-- ---------- grupos ----------
set role authenticated;
select pg_temp.as_user(:fercho);
select public.create_group('Bariloche');
select public.invite_to_group((select id from public.groups), 'pepito@prueba.com');
select public.invite_to_group((select id from public.groups), 'juancito@prueba.com');
select public.invite_to_group((select id from public.groups), 'nuevo@prueba.com');
do $$ begin
  perform pg_temp.ok((select count(*) from public.group_members) = 3, 'grupo con 3 miembros');
  perform pg_temp.ok((select count(*) from public.group_invites) = 1, 'invitación pendiente por mail');
end $$;
-- gasto 100.00 entre 3 => 33.34 / 33.33 / 33.33, pagó Fercho
select public.save_group_expense((select id from public.groups), null, 'Super', 10000, :fercho, current_date, array[:fercho::uuid, :pepito::uuid, :juancito::uuid]);
do $$
declare g uuid := (select id from public.groups); f bigint; p bigint; j bigint;
begin
  select net_cents into f from public.group_balances(g) where user_id='11111111-1111-1111-1111-111111111111';
  select net_cents into p from public.group_balances(g) where user_id='22222222-2222-2222-2222-222222222222';
  select net_cents into j from public.group_balances(g) where user_id='33333333-3333-3333-3333-333333333333';
  perform pg_temp.ok(f = 6666 and p = -3333 and j = -3333, 'reparto 100,00 entre 3: el centavo sobrante va al primero (' || f || '/' || p || '/' || j || ')');
  perform pg_temp.ok(f + p + j = 0, 'los saldos suman cero');
end $$;
-- pago pendiente: no baja la deuda; lo confirma la otra parte
select pg_temp.as_user(:pepito);
select public.register_group_payment((select id from public.groups), :pepito, :fercho, 3333);
do $$
declare g uuid := (select id from public.groups);
begin
  perform pg_temp.ok((select net_cents from public.group_balances(g) where user_id='22222222-2222-2222-2222-222222222222') = -3333, 'pago pendiente no baja la deuda');
  begin perform public.respond_group_payment((select id from public.group_payments), true); raise exception 'FALLÓ: quien registró pudo confirmar';
  exception when others then if sqlerrm like 'FALLÓ%' then raise; end if; raise notice 'ok: quien lo registró no puede confirmarlo'; end;
end $$;
select pg_temp.as_user(:fercho);
select public.respond_group_payment((select id from public.group_payments), true);
do $$
declare g uuid := (select id from public.groups);
begin
  perform pg_temp.ok((select net_cents from public.group_balances(g) where user_id='22222222-2222-2222-2222-222222222222') = 0, 'al confirmar, Pepito queda en cero');
  perform pg_temp.ok((select net_cents from public.group_balances(g) where user_id='11111111-1111-1111-1111-111111111111') = 3333, 'Fercho queda con 33,33 a favor');
end $$;
-- editar gasto: actividad con diferencias y autor
select public.save_group_expense((select id from public.groups), (select id from public.group_expenses), 'Super grande', 15000, :fercho, current_date, array[:fercho::uuid, :pepito::uuid]);
do $$ begin
  perform pg_temp.ok((select text from public.group_activity where text like 'cambió%' order by created_at desc limit 1) like '%monto de $ 100,00 a $ 150,00%', 'la actividad registra el cambio de monto con formato argentino');
  perform pg_temp.ok((select actor from public.group_activity where text like 'cambió%' limit 1) = '11111111-1111-1111-1111-111111111111', 'la actividad guarda quién lo tocó');
end $$;
-- aislamiento: Bren no ve nada del grupo
select pg_temp.as_user(:bren);
do $$ begin
  perform pg_temp.ok((select count(*) from public.groups) = 0 and (select count(*) from public.group_expenses) = 0 and (select count(*) from public.group_activity) = 0, 'Bren (afuera) no ve el grupo');
  begin perform public.save_group_expense((select id from public.groups limit 1), null, 'x', 100, '44444444-4444-4444-4444-444444444444', current_date, array['44444444-4444-4444-4444-444444444444'::uuid]); raise exception 'FALLÓ: un extraño cargó un gasto';
  exception when others then if sqlerrm like 'FALLÓ%' then raise; end if; raise notice 'ok: un extraño no puede cargar gastos'; end;
  begin insert into public.group_expenses (group_id, description, amount_cents, paid_by, created_by) select id, 'x', 1, id, id from public.groups limit 1; raise notice 'ok: sin grupos no hay inserción'; exception when insufficient_privilege then raise notice 'ok: sin insert directo'; end;
end $$;
-- compañeros de grupo ven el alias
select pg_temp.as_user(:fercho);
do $$ begin perform pg_temp.ok((select transfer_alias from public.visible_aliases() where user_id='22222222-2222-2222-2222-222222222222') = 'pepito.mp', 'compañeros de grupo ven el alias de Pepito'); end $$;
-- Nuevo usuario invitado por mail entra solo al grupo
reset role;
insert into auth.users (id, email, raw_user_meta_data) values ('55555555-5555-5555-5555-555555555555', 'nuevo@prueba.com', '{"name":"Nuevo"}');
do $$ begin perform pg_temp.ok((select count(*) from public.group_members) = 4 and (select count(*) from public.group_invites) = 0, 'el invitado por mail entra al grupo al registrarse'); end $$;

-- ---------- datos personales: aislamiento ----------
set role authenticated;
select pg_temp.as_user(:fercho);
insert into public.statements (owner_id, issuer, label, pay_month, total_cents) values (:fercho, 'galicia-visa', 'Galicia Visa', '2026-11', 21400000);
select pg_temp.as_user(:pepito);
do $$ begin
  perform pg_temp.ok((select count(*) from public.statements) = 0, 'Pepito no ve resúmenes de Fercho');
  begin insert into public.statements (owner_id, issuer, label, pay_month) values ('11111111-1111-1111-1111-111111111111', 'mp', 'x', '2026-11'); raise exception 'FALLÓ: escribió en datos ajenos';
  exception when others then if sqlerrm like 'FALLÓ%' then raise; end if; raise notice 'ok: no se puede escribir datos de otro'; end;
end $$;
reset role;
\echo '=== TODO OK ==='
