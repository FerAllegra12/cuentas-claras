-- Cuentas Claras · esquema inicial (Supabase / Postgres)
--
-- Reglas de oro:
--  * La plata va en centavos (bigint). Nunca decimales flotantes.
--  * NO se guarda número de tarjeta, DNI, CUIL, domicilio ni CBU. Solo el alias de transferencia.
--  * Lo de cada persona (resúmenes, gastos propios) lo ve solo esa persona.
--  * Lo de un grupo lo ven solo sus miembros.
--  * Toda escritura de grupos, contactos y pagos pasa por funciones (RPC): así queda
--    registrado quién hizo cada cosa y nadie puede falsificarlo.

-- =====================================================================
-- Utilidades
-- =====================================================================

-- $ 1.234,50 (formato argentino) para los textos de la actividad
create or replace function public.fmt_ars(p_cents bigint) returns text
language sql immutable as $$
  select '$ ' || regexp_replace((abs(p_cents) / 100)::text, '(\d)(?=(\d{3})+$)', '\1.', 'g')
         || ',' || lpad((abs(p_cents) % 100)::text, 2, '0');
$$;

-- =====================================================================
-- Perfiles (uno por usuario de auth.users)
-- =====================================================================

create table public.profiles (
  id             uuid primary key references auth.users(id) on delete cascade,
  email          text not null,
  display_name   text not null,
  transfer_alias text,                         -- solo el alias, nunca CBU ni número de cuenta
  created_at     timestamptz not null default now(),
  constraint profiles_alias_len check (transfer_alias is null or char_length(transfer_alias) between 1 and 40)
);
create unique index profiles_email_key on public.profiles (lower(email));

-- =====================================================================
-- Contactos (libreta de cada usuario) y solicitudes de amistad
-- =====================================================================

create table public.contacts (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references public.profiles(id) on delete cascade,
  alias       text not null check (char_length(alias) between 1 and 30),  -- como lo ve el dueño
  email       text not null,
  linked_user uuid references public.profiles(id) on delete set null,     -- si el mail es de un usuario de la app
  removed_at  timestamptz,                                                -- quitado por el dueño (la deuda sigue a la vista)
  created_at  timestamptz not null default now()
);
create unique index contacts_owner_email_key on public.contacts (owner_id, lower(email));
create index contacts_linked_idx on public.contacts (linked_user);

create table public.friend_requests (
  id          uuid primary key default gen_random_uuid(),
  from_user   uuid not null references public.profiles(id) on delete cascade,
  to_user     uuid not null references public.profiles(id) on delete cascade,
  status      text not null default 'pending' check (status in ('pending', 'accepted', 'rejected')),
  created_at  timestamptz not null default now(),
  resolved_at timestamptz,
  check (from_user <> to_user)
);
create index friend_requests_to_idx on public.friend_requests (to_user, status);
create index friend_requests_from_idx on public.friend_requests (from_user, status);
create unique index friend_requests_one_pending on public.friend_requests (from_user, to_user) where status = 'pending';

-- =====================================================================
-- Grupos
-- =====================================================================

create table public.groups (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (char_length(name) between 1 and 60),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.group_members (
  group_id  uuid not null references public.groups(id) on delete cascade,
  user_id   uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index group_members_user_idx on public.group_members (user_id);

-- invitados por mail que todavía no se registraron
create table public.group_invites (
  id         uuid primary key default gen_random_uuid(),
  group_id   uuid not null references public.groups(id) on delete cascade,
  email      text not null,
  invited_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);
create unique index group_invites_key on public.group_invites (group_id, lower(email));

create table public.group_expenses (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references public.groups(id) on delete cascade,
  description  text not null check (char_length(description) between 1 and 120),
  amount_cents bigint not null check (amount_cents > 0),
  paid_by      uuid not null references public.profiles(id),
  expense_date date not null default current_date,
  src_key      text,                       -- si vino de un resumen de tarjeta: "gasto:resumen"
  created_by   uuid not null references public.profiles(id),
  created_at   timestamptz not null default now()
);
create index group_expenses_group_idx on public.group_expenses (group_id, expense_date);
create unique index group_expenses_src on public.group_expenses (group_id, src_key) where src_key is not null;

-- reparto en partes iguales entre estos usuarios; position decide a quién le toca el centavo sobrante
create table public.group_expense_splits (
  expense_id uuid not null references public.group_expenses(id) on delete cascade,
  user_id    uuid not null references public.profiles(id),
  position   int not null,
  primary key (expense_id, user_id)
);

create table public.group_payments (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references public.groups(id) on delete cascade,
  from_user    uuid not null references public.profiles(id),   -- quien paga
  to_user      uuid not null references public.profiles(id),   -- quien cobra
  amount_cents bigint not null check (amount_cents > 0),
  status       text not null default 'pending' check (status in ('pending', 'confirmed')),
  created_by   uuid not null references public.profiles(id),
  created_at   timestamptz not null default now(),
  confirmed_at timestamptz,
  check (from_user <> to_user),
  check (created_by in (from_user, to_user))
);
create index group_payments_group_idx on public.group_payments (group_id, created_at);

create table public.group_activity (
  id         uuid primary key default gen_random_uuid(),
  group_id   uuid not null references public.groups(id) on delete cascade,
  actor      uuid not null references public.profiles(id),
  text       text not null,
  created_at timestamptz not null default now()
);
create index group_activity_group_idx on public.group_activity (group_id, created_at);

-- =====================================================================
-- Datos personales (solo el dueño)
-- =====================================================================

create table public.statements (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null references public.profiles(id) on delete cascade,
  issuer          text not null,                      -- galicia-visa | galicia-mc | mp
  label           text not null,
  close_date      date,
  due_date        date,
  pay_month       text not null check (pay_month ~ '^\d{4}-\d{2}$'),
  total_cents     bigint not null default 0,
  total_usd_cents bigint not null default 0,
  line_count      int not null default 0,
  netted          jsonb not null default '[]'::jsonb, -- cargos y anulaciones que se compensaron
  imported_at     timestamptz not null default now()
);
create index statements_owner_idx on public.statements (owner_id, pay_month);

create table public.card_expenses (
  id                 uuid primary key default gen_random_uuid(),
  owner_id           uuid not null references public.profiles(id) on delete cascade,
  issuer             text not null,
  kind               text not null check (kind in ('cuota', 'recurrente', 'unico')),
  description        text not null,                   -- como figura en el resumen
  custom_name        text not null default '',        -- como lo llama el usuario
  tag                text,
  status             text not null default 'activo' check (status in ('activo', 'terminado', 'anulado')),
  key_ref            text,                            -- número de comprobante
  key_date           date,
  total_cuotas       int,
  key_aliases        text[] not null default '{}',
  split_contact_id   uuid references public.contacts(id) on delete set null,   -- con quién se divide (mitad y mitad)
  group_id           uuid references public.groups(id) on delete set null,     -- grupo donde se carga la otra mitad
  created_at         timestamptz not null default now()
);
create index card_expenses_owner_idx on public.card_expenses (owner_id);

create table public.card_expense_entries (
  id           uuid primary key default gen_random_uuid(),
  expense_id   uuid not null references public.card_expenses(id) on delete cascade,
  statement_id uuid not null references public.statements(id) on delete cascade,
  cuota        int,
  total        int,
  amount_cents bigint not null,
  currency     text not null default 'ARS' check (currency in ('ARS', 'USD')),
  ref          text,
  entry_date   date,
  raw_desc     text
);
create index card_entries_expense_idx on public.card_expense_entries (expense_id);
create index card_entries_statement_idx on public.card_expense_entries (statement_id);

-- correcciones manuales de cuota/monto en meses sin resumen: desde ahí el hilo sigue
create table public.card_expense_anchors (
  expense_id   uuid not null references public.card_expenses(id) on delete cascade,
  pay_month    text not null check (pay_month ~ '^\d{4}-\d{2}$'),
  cuota        int not null,
  total        int not null,
  amount_cents bigint not null,
  primary key (expense_id, pay_month)
);

create table public.manual_expenses (
  id               uuid primary key default gen_random_uuid(),
  owner_id         uuid not null references public.profiles(id) on delete cascade,
  description      text not null,
  amount_cents     bigint not null,
  currency         text not null default 'ARS' check (currency in ('ARS', 'USD')),
  start_month      text not null check (start_month ~ '^\d{4}-\d{2}$'),
  cuota_actual     int,
  cuota_total      int,
  monthly          boolean not null default false,
  end_month        text,
  split_contact_id uuid references public.contacts(id) on delete set null,
  created_at       timestamptz not null default now()
);
create index manual_expenses_owner_idx on public.manual_expenses (owner_id);

-- "Me pagó" / "Ya pagué" fuera de los grupos
create table public.personal_payments (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null references public.profiles(id) on delete cascade,
  person_key   text not null,                         -- "c:<contact_id>" o "u:<user_id>"
  amount_cents bigint not null check (amount_cents > 0),
  paid_on      date not null default current_date,
  created_at   timestamptz not null default now()
);
create index personal_payments_owner_idx on public.personal_payments (owner_id);

-- actividad general: quién tocó qué (cuota, monto, contactos, alias…)
create table public.activity_log (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null references public.profiles(id) on delete cascade,
  actor      uuid not null references public.profiles(id),
  text       text not null,
  created_at timestamptz not null default now()
);
create index activity_log_owner_idx on public.activity_log (owner_id, created_at);

-- =====================================================================
-- Funciones de ayuda para la seguridad (security definer = evitan recursión de RLS)
-- =====================================================================

create or replace function public.is_group_member(p_group uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.group_members where group_id = p_group and user_id = auth.uid());
$$;

create or replace function public.shares_group_with(p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.group_members a join public.group_members b on a.group_id = b.group_id
    where a.user_id = auth.uid() and b.user_id = p_user
  );
$$;

-- ¿somos contactos los dos (cada uno tiene al otro, sin quitar)?
create or replace function public.is_mutual_contact(p_a uuid, p_b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.contacts where owner_id = p_a and linked_user = p_b and removed_at is null)
     and exists (select 1 from public.contacts where owner_id = p_b and linked_user = p_a and removed_at is null);
$$;

create or replace function public.has_request_with(p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.friend_requests
    where (from_user = auth.uid() and to_user = p_user) or (from_user = p_user and to_user = auth.uid())
  );
$$;

-- =====================================================================
-- Alta de usuario: perfil automático + vínculos pendientes
-- =====================================================================

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_name text;
begin
  v_name := coalesce(nullif(trim(new.raw_user_meta_data ->> 'name'), ''), split_part(new.email, '@', 1));
  insert into public.profiles (id, email, display_name) values (new.id, lower(new.email), v_name);

  -- los contactos que ya tenían este mail quedan vinculados
  update public.contacts set linked_user = new.id where lower(email) = lower(new.email) and linked_user is null;

  -- las invitaciones a grupos por mail se convierten en membresía
  insert into public.group_members (group_id, user_id)
    select group_id, new.id from public.group_invites where lower(email) = lower(new.email)
    on conflict do nothing;
  delete from public.group_invites where lower(email) = lower(new.email);
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- =====================================================================
-- RPC: contactos y solicitudes
-- =====================================================================

-- ¿hace falta mandar solicitud? (el mail es de un usuario y todavía no son contactos mutuos)
create or replace function public._send_request_if_needed(p_owner uuid, p_contact public.contacts) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if p_contact.linked_user is null or p_contact.linked_user = p_owner or p_contact.removed_at is not null then return false; end if;
  if public.is_mutual_contact(p_owner, p_contact.linked_user) then return false; end if;
  if exists (select 1 from public.friend_requests where from_user = p_owner and to_user = p_contact.linked_user and status = 'pending') then return false; end if;
  insert into public.friend_requests (from_user, to_user) values (p_owner, p_contact.linked_user);
  return true;
end $$;

create or replace function public.add_contact(p_alias text, p_email text) returns public.contacts
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  v_email text := lower(trim(p_email));
  v_alias text := trim(p_alias);
  c public.contacts;
begin
  if me is null then raise exception 'No autenticado'; end if;
  if v_alias = '' then raise exception 'Poné un alias.'; end if;
  if v_email !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' then raise exception 'Revisá el mail, no parece válido.'; end if;
  if exists (select 1 from public.contacts where owner_id = me and removed_at is null and lower(alias) = lower(v_alias) and lower(email) <> v_email) then
    raise exception 'Ya tenés un contacto con ese alias.';
  end if;

  select * into c from public.contacts where owner_id = me and lower(email) = v_email;
  if found then
    update public.contacts set alias = v_alias, removed_at = null where id = c.id returning * into c;
    insert into public.activity_log (owner_id, actor, text) values (me, me, 'volvió a agregar a ' || v_alias || ' como contacto');
  else
    insert into public.contacts (owner_id, alias, email, linked_user)
      values (me, v_alias, v_email, (select id from public.profiles where lower(email) = v_email and id <> me))
      returning * into c;
  end if;

  if public._send_request_if_needed(me, c) then
    insert into public.activity_log (owner_id, actor, text) values (me, me, 'mandó solicitud de contacto a ' || v_alias);
  end if;
  return c;
end $$;

-- relación de cada contacto mío: plain (no usa la app) | mutual | pending | rejected | cut (me sacó)
create or replace function public.my_contact_links() returns table (contact_id uuid, state text)
language sql stable security definer set search_path = public as $$
  select c.id,
    case
      when c.linked_user is null then 'plain'
      when public.is_mutual_contact(c.owner_id, c.linked_user) then 'mutual'
      else coalesce((
        select case fr.status when 'pending' then 'pending' when 'rejected' then 'rejected' else 'cut' end
        from public.friend_requests fr
        where fr.from_user = c.owner_id and fr.to_user = c.linked_user
        order by fr.created_at desc limit 1), 'cut')
    end
  from public.contacts c
  where c.owner_id = auth.uid() and c.removed_at is null;
$$;

create or replace function public.reinvite_contact(p_contact uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); c public.contacts; sent boolean;
begin
  select * into c from public.contacts where id = p_contact and owner_id = me;
  if not found then raise exception 'Contacto inexistente'; end if;
  sent := public._send_request_if_needed(me, c);
  if sent then insert into public.activity_log (owner_id, actor, text) values (me, me, 'volvió a mandar la solicitud de contacto a ' || c.alias); end if;
  return sent;
end $$;

-- invitar a un contacto a partir de alguien que conozco de un grupo
create or replace function public.invite_group_mate(p_user uuid) returns public.contacts
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); p public.profiles;
begin
  if not public.shares_group_with(p_user) then raise exception 'Esa persona no está en ninguno de tus grupos.'; end if;
  select * into p from public.profiles where id = p_user;
  insert into public.activity_log (owner_id, actor, text) values (me, me, 'invitó a ' || p.display_name || ' a ser contacto');
  return public.add_contact(p.display_name, p.email);
end $$;

create or replace function public.respond_friend_request(p_request uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r public.friend_requests; f public.profiles; m public.profiles;
begin
  select * into r from public.friend_requests where id = p_request and to_user = me and status = 'pending';
  if not found then raise exception 'Solicitud inexistente o ya respondida.'; end if;
  select * into f from public.profiles where id = r.from_user;
  select * into m from public.profiles where id = me;

  -- cierra todas las solicitudes iguales (evita que quede una colgada)
  update public.friend_requests set status = case when p_accept then 'accepted' else 'rejected' end, resolved_at = now()
    where from_user = r.from_user and to_user = r.to_user and status = 'pending';

  if p_accept then
    insert into public.contacts (owner_id, alias, email, linked_user) values (me, f.display_name, f.email, f.id)
      on conflict (owner_id, lower(email)) do update set removed_at = null, linked_user = excluded.linked_user;
    insert into public.activity_log (owner_id, actor, text) values (me, me, 'aceptó la solicitud de ' || f.display_name || ': ahora son contactos');
    insert into public.activity_log (owner_id, actor, text) values (f.id, me, m.display_name || ' aceptó tu solicitud de contacto');
  else
    insert into public.activity_log (owner_id, actor, text) values (me, me, 'rechazó la solicitud de ' || f.display_name);
  end if;
end $$;

create or replace function public.remove_contact(p_contact uuid) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); c public.contacts;
begin
  update public.contacts set removed_at = now() where id = p_contact and owner_id = me and removed_at is null returning * into c;
  if not found then raise exception 'Contacto inexistente'; end if;
  insert into public.activity_log (owner_id, actor, text) values (me, me, 'quitó a ' || c.alias || ' de sus contactos (las deudas siguen a la vista)');
end $$;

-- =====================================================================
-- RPC: grupos
-- =====================================================================

create or replace function public._log_group(p_group uuid, p_text text) returns void
language sql security definer set search_path = public as $$
  insert into public.group_activity (group_id, actor, text) values (p_group, auth.uid(), p_text);
$$;

create or replace function public._uname(p_user uuid) returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select display_name from public.profiles where id = p_user), 'Alguien');
$$;

create or replace function public.create_group(p_name text) returns public.groups
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); g public.groups;
begin
  if me is null then raise exception 'No autenticado'; end if;
  insert into public.groups (name, created_by) values (trim(p_name), me) returning * into g;
  insert into public.group_members (group_id, user_id) values (g.id, me);
  perform public._log_group(g.id, 'creó el grupo');
  return g;
end $$;

create or replace function public.invite_to_group(p_group uuid, p_email text) returns text
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); v_email text := lower(trim(p_email)); u public.profiles;
begin
  if not public.is_group_member(p_group) then raise exception 'No sos parte de este grupo.'; end if;
  select * into u from public.profiles where lower(email) = v_email;
  if found then
    insert into public.group_members (group_id, user_id) values (p_group, u.id) on conflict do nothing;
    perform public._log_group(p_group, 'invitó a ' || u.display_name || ' (ya está en el grupo)');
    return 'member';
  end if;
  insert into public.group_invites (group_id, email, invited_by) values (p_group, v_email, me) on conflict do nothing;
  perform public._log_group(p_group, 'invitó a ' || v_email);
  return 'invited';
end $$;

-- cargar o editar un gasto. p_expense null = alta. Reparto en partes iguales entre p_split (el orden importa para el centavo sobrante)
create or replace function public.save_group_expense(
  p_group uuid, p_expense uuid, p_description text, p_amount_cents bigint,
  p_paid_by uuid, p_date date, p_split uuid[]
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid(); old public.group_expenses; v_id uuid; i int; d text[] := '{}'; old_split uuid[]; u uuid; v_desc text := trim(p_description);
begin
  if not public.is_group_member(p_group) then raise exception 'No sos parte de este grupo.'; end if;
  if v_desc = '' then raise exception 'Poné qué fue el gasto.'; end if;
  if p_amount_cents is null or p_amount_cents <= 0 then raise exception 'El monto tiene que ser mayor a cero.'; end if;
  if coalesce(array_length(p_split, 1), 0) = 0 then raise exception 'Elegí al menos una persona para repartir.'; end if;
  if not exists (select 1 from public.group_members where group_id = p_group and user_id = p_paid_by) then raise exception 'Quien pagó no es del grupo.'; end if;
  foreach u in array p_split loop
    if not exists (select 1 from public.group_members where group_id = p_group and user_id = u) then raise exception 'Alguien del reparto no es del grupo.'; end if;
  end loop;

  if p_expense is null then
    insert into public.group_expenses (group_id, description, amount_cents, paid_by, expense_date, created_by)
      values (p_group, v_desc, p_amount_cents, p_paid_by, coalesce(p_date, current_date), me) returning id into v_id;
    perform public._log_group(p_group, 'cargó "' || v_desc || '" por ' || public.fmt_ars(p_amount_cents) || ', pagó ' || public._uname(p_paid_by));
  else
    select * into old from public.group_expenses where id = p_expense and group_id = p_group;
    if not found then raise exception 'Gasto inexistente'; end if;
    v_id := old.id;
    select coalesce(array_agg(user_id order by position), '{}') into old_split from public.group_expense_splits where expense_id = v_id;
    if old.description <> v_desc then d := d || ('nombre de "' || old.description || '" a "' || v_desc || '"'); end if;
    if old.amount_cents <> p_amount_cents then d := d || ('monto de ' || public.fmt_ars(old.amount_cents) || ' a ' || public.fmt_ars(p_amount_cents)); end if;
    if old.paid_by <> p_paid_by then d := d || ('quién pagó: de ' || public._uname(old.paid_by) || ' a ' || public._uname(p_paid_by)); end if;
    if (select array_agg(x order by x) from unnest(old_split) x) is distinct from (select array_agg(x order by x) from unnest(p_split) x) then
      d := d || ('reparto: de ' || (select string_agg(public._uname(x), ', ') from unnest(old_split) x) || ' a ' || (select string_agg(public._uname(x), ', ') from unnest(p_split) x));
    end if;
    if old.expense_date <> coalesce(p_date, old.expense_date) then d := d || ('fecha de ' || to_char(old.expense_date, 'DD/MM/YYYY') || ' a ' || to_char(p_date, 'DD/MM/YYYY')); end if;
    update public.group_expenses set description = v_desc, amount_cents = p_amount_cents, paid_by = p_paid_by, expense_date = coalesce(p_date, expense_date) where id = v_id;
    delete from public.group_expense_splits where expense_id = v_id;
    if array_length(d, 1) > 0 then perform public._log_group(p_group, 'cambió "' || old.description || '": ' || array_to_string(d, '; ')); end if;
  end if;

  delete from public.group_expense_splits where expense_id = v_id;
  for i in 1 .. array_length(p_split, 1) loop
    insert into public.group_expense_splits (expense_id, user_id, position) values (v_id, p_split[i], i);
  end loop;
  return v_id;
end $$;

create or replace function public.delete_group_expense(p_expense uuid) returns void
language plpgsql security definer set search_path = public as $$
declare e public.group_expenses;
begin
  select * into e from public.group_expenses where id = p_expense;
  if not found or not public.is_group_member(e.group_id) then raise exception 'Gasto inexistente'; end if;
  delete from public.group_expenses where id = p_expense;
  perform public._log_group(e.group_id, 'quitó "' || e.description || '" (' || public.fmt_ars(e.amount_cents) || ')');
end $$;

-- registrar un pago: queda pendiente hasta que lo confirme la otra parte
create or replace function public.register_group_payment(p_group uuid, p_from uuid, p_to uuid, p_amount_cents bigint) returns uuid
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); v_id uuid; other uuid;
begin
  if not public.is_group_member(p_group) then raise exception 'No sos parte de este grupo.'; end if;
  if me not in (p_from, p_to) then raise exception 'Solo quien paga o quien cobra puede registrar el pago.'; end if;
  if p_amount_cents is null or p_amount_cents <= 0 then raise exception 'El monto tiene que ser mayor a cero.'; end if;
  if not exists (select 1 from public.group_members where group_id = p_group and user_id = p_from)
     or not exists (select 1 from public.group_members where group_id = p_group and user_id = p_to) then raise exception 'Alguien no es del grupo.'; end if;
  other := case when me = p_from then p_to else p_from end;
  insert into public.group_payments (group_id, from_user, to_user, amount_cents, created_by) values (p_group, p_from, p_to, p_amount_cents, me) returning id into v_id;
  perform public._log_group(p_group, 'registró que ' || public._uname(p_from) || ' le pagó ' || public.fmt_ars(p_amount_cents) || ' a ' || public._uname(p_to) || ' (falta que ' || public._uname(other) || ' lo confirme)');
  return v_id;
end $$;

create or replace function public.respond_group_payment(p_payment uuid, p_confirm boolean) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); p public.group_payments; txt text;
begin
  select * into p from public.group_payments where id = p_payment and status = 'pending';
  if not found or not public.is_group_member(p.group_id) then raise exception 'Pago inexistente o ya confirmado.'; end if;
  if me = p.created_by or me not in (p.from_user, p.to_user) then raise exception 'Lo tiene que confirmar la otra parte.'; end if;
  txt := public._uname(p.from_user) || ' → ' || public._uname(p.to_user) || ' ' || public.fmt_ars(p.amount_cents);
  if p_confirm then
    update public.group_payments set status = 'confirmed', confirmed_at = now() where id = p.id;
    perform public._log_group(p.group_id, 'confirmó el pago ' || txt);
  else
    delete from public.group_payments where id = p.id;
    perform public._log_group(p.group_id, 'rechazó el pago ' || txt);
  end if;
end $$;

create or replace function public.cancel_group_payment(p_payment uuid) returns void
language plpgsql security definer set search_path = public as $$
declare p public.group_payments;
begin
  select * into p from public.group_payments where id = p_payment and status = 'pending' and created_by = auth.uid();
  if not found then raise exception 'Pago inexistente o no es tuyo.'; end if;
  delete from public.group_payments where id = p.id;
  perform public._log_group(p.group_id, 'canceló el pago pendiente ' || public._uname(p.from_user) || ' → ' || public._uname(p.to_user) || ' ' || public.fmt_ars(p.amount_cents));
end $$;

-- saldo de cada miembro: + puso de más / - le falta poner. Ignora pagos pendientes.
-- El centavo sobrante del reparto va a los primeros de la lista (igual que en el prototipo).
create or replace function public.group_balances(p_group uuid) returns table (user_id uuid, net_cents bigint)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public.is_group_member(p_group) then raise exception 'No sos parte de este grupo.'; end if;
  return query
  with shares as (
    select s.user_id,
           (e.amount_cents / n.cnt) + case when s.position <= (e.amount_cents % n.cnt) then 1 else 0 end as share
    from public.group_expenses e
    join public.group_expense_splits s on s.expense_id = e.id
    join lateral (select count(*) as cnt from public.group_expense_splits x where x.expense_id = e.id) n on true
    where e.group_id = p_group
  ), movs as (
    select e.paid_by as uid, e.amount_cents as amt from public.group_expenses e where e.group_id = p_group
    union all select user_id, -share from shares
    union all select from_user, amount_cents from public.group_payments where group_id = p_group and status = 'confirmed'
    union all select to_user, -amount_cents from public.group_payments where group_id = p_group and status = 'confirmed'
  )
  select m.user_id, coalesce((select sum(amt) from movs where uid = m.user_id), 0)::bigint
  from public.group_members m where m.group_id = p_group;
end $$;

-- alias de transferencia que puedo ver: el mío, el de mis contactos mutuos y el de mis compañeros de grupo
create or replace function public.visible_aliases() returns table (user_id uuid, transfer_alias text)
language sql stable security definer set search_path = public as $$
  select p.id, p.transfer_alias from public.profiles p
  where p.transfer_alias is not null
    and (p.id = auth.uid() or public.shares_group_with(p.id) or public.is_mutual_contact(auth.uid(), p.id));
$$;

-- =====================================================================
-- Seguridad por fila (RLS)
-- =====================================================================

alter table public.profiles              enable row level security;
alter table public.contacts              enable row level security;
alter table public.friend_requests       enable row level security;
alter table public.groups                enable row level security;
alter table public.group_members         enable row level security;
alter table public.group_invites         enable row level security;
alter table public.group_expenses        enable row level security;
alter table public.group_expense_splits  enable row level security;
alter table public.group_payments        enable row level security;
alter table public.group_activity        enable row level security;
alter table public.statements            enable row level security;
alter table public.card_expenses         enable row level security;
alter table public.card_expense_entries  enable row level security;
alter table public.card_expense_anchors  enable row level security;
alter table public.manual_expenses       enable row level security;
alter table public.personal_payments     enable row level security;
alter table public.activity_log          enable row level security;

-- perfiles: nombre y mail los ven yo, mis compañeros de grupo, mis contactos y quienes tienen solicitud conmigo.
-- El alias de transferencia NO se lee por tabla: va por visible_aliases().
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.shares_group_with(id) or public.is_mutual_contact(auth.uid(), id) or public.has_request_with(id));
create policy profiles_update_self on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- contactos: del dueño (alta y quitar por RPC; el dueño puede ver y cambiar el alias con que lo ve)
create policy contacts_select on public.contacts for select to authenticated using (owner_id = auth.uid());
create policy contacts_update on public.contacts for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy friend_requests_select on public.friend_requests for select to authenticated
  using (from_user = auth.uid() or to_user = auth.uid());

-- grupos: solo miembros; todo lo que se escribe va por RPC
create policy groups_select on public.groups for select to authenticated using (public.is_group_member(id));
create policy group_members_select on public.group_members for select to authenticated using (public.is_group_member(group_id));
create policy group_invites_select on public.group_invites for select to authenticated using (public.is_group_member(group_id));
create policy group_expenses_select on public.group_expenses for select to authenticated using (public.is_group_member(group_id));
create policy group_splits_select on public.group_expense_splits for select to authenticated
  using (exists (select 1 from public.group_expenses e where e.id = expense_id and public.is_group_member(e.group_id)));
create policy group_payments_select on public.group_payments for select to authenticated using (public.is_group_member(group_id));
create policy group_activity_select on public.group_activity for select to authenticated using (public.is_group_member(group_id));

-- datos personales: solo el dueño, lectura y escritura
create policy statements_all on public.statements for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy card_expenses_all on public.card_expenses for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy card_entries_all on public.card_expense_entries for all to authenticated
  using (exists (select 1 from public.card_expenses e where e.id = expense_id and e.owner_id = auth.uid()))
  with check (exists (select 1 from public.card_expenses e where e.id = expense_id and e.owner_id = auth.uid()));
create policy card_anchors_all on public.card_expense_anchors for all to authenticated
  using (exists (select 1 from public.card_expenses e where e.id = expense_id and e.owner_id = auth.uid()))
  with check (exists (select 1 from public.card_expenses e where e.id = expense_id and e.owner_id = auth.uid()));
create policy manual_expenses_all on public.manual_expenses for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy personal_payments_all on public.personal_payments for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy activity_log_select on public.activity_log for select to authenticated using (owner_id = auth.uid());
create policy activity_log_insert on public.activity_log for insert to authenticated with check (owner_id = auth.uid() and actor = auth.uid());

-- =====================================================================
-- Permisos: nada de escritura directa donde manda una función
-- =====================================================================

revoke all on all tables in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;

grant usage on schema public to authenticated;

-- lectura
grant select on public.groups, public.group_members, public.group_invites, public.group_expenses,
  public.group_expense_splits, public.group_payments, public.group_activity, public.friend_requests,
  public.contacts to authenticated;
grant select (id, email, display_name) on public.profiles to authenticated;
-- escritura directa solo donde corresponde
grant update (display_name, transfer_alias) on public.profiles to authenticated;
grant update (alias) on public.contacts to authenticated;
grant select, insert, update, delete on public.statements, public.card_expenses, public.card_expense_entries,
  public.card_expense_anchors, public.manual_expenses, public.personal_payments to authenticated;
grant select, insert on public.activity_log to authenticated;

-- funciones que puede llamar la app
grant execute on function
  public.add_contact(text, text), public.my_contact_links(), public.reinvite_contact(uuid),
  public.invite_group_mate(uuid), public.respond_friend_request(uuid, boolean), public.remove_contact(uuid),
  public.create_group(text), public.invite_to_group(uuid, text),
  public.save_group_expense(uuid, uuid, text, bigint, uuid, date, uuid[]), public.delete_group_expense(uuid),
  public.register_group_payment(uuid, uuid, uuid, bigint), public.respond_group_payment(uuid, boolean),
  public.cancel_group_payment(uuid), public.group_balances(uuid), public.visible_aliases(), public.fmt_ars(bigint)
  to authenticated;
-- las ayudantes de RLS también las usan las políticas
grant execute on function public.is_group_member(uuid), public.shares_group_with(uuid),
  public.is_mutual_contact(uuid, uuid), public.has_request_with(uuid) to authenticated;
