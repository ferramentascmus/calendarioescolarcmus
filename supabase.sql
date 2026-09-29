-- =====================================================================
--  Calendario do curso 2026-27 · votación anónima (un voto por dispositivo)
--  e versión do profesorado.
--
--  TODO o que crea este script empeza por  ccc_  (3 táboas e 13 funcións),
--  para que non choque con nada que xa teñas no proxecto de Supabase.
--  Non modifica nin borra nada que non empece por ccc_.
--
--  Pega TODO isto no SQL Editor de Supabase e preme Run.
--  ANTES DE EXECUTAR: cambia CAMBIA_ESTA_CLAVE (unha máis abaixo) por unha clave túa.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------- Táboas (ninguén pode lelas directamente: só as funcións de abaixo) ----------
create table if not exists public.ccc_config (
  id            int primary key default 1 check (id = 1),
  clave_hash    text not null,
  ronda         int  not null default 0,
  pin           text,
  opcions       jsonb not null default '[]'::jsonb,
  publicado     jsonb,
  abre_a        timestamptz,
  pecha_a       timestamptz,
  pechada_man   boolean not null default true,
  res_publicos  boolean not null default true,
  barallada     boolean not null default false
);

-- Un rexistro por dispositivo e ronda: só di "este dispositivo xa votou". Sen nome.
create table if not exists public.ccc_dispositivos (
  token  text not null,
  ronda  int  not null,
  primary key (token, ronda)
);

-- A urna: só ronda e opción. Sen id, sen data, sen dispositivo.
create table if not exists public.ccc_urna (
  ronda  int  not null,
  opcion text not null
);

alter table public.ccc_config       enable row level security;
alter table public.ccc_dispositivos enable row level security;
alter table public.ccc_urna         enable row level security;
revoke all on public.ccc_config, public.ccc_dispositivos, public.ccc_urna from anon, authenticated;

-- ---------- CLAVE DE ADMINISTRACIÓN (cámbiaa aquí) ----------
insert into public.ccc_config (id, clave_hash)
values (1, extensions.crypt('CAMBIA_ESTA_CLAVE', extensions.gen_salt('bf')))
on conflict (id) do nothing;

-- ---------- Utilidades ----------
create or replace function public.ccc_admin(p_clave text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not exists (select 1 from ccc_config where id = 1 and clave_hash = crypt(coalesce(p_clave,''), clave_hash)) then
    raise exception 'clave_incorrecta';
  end if;
end $$;

-- Estado efectivo segundo a hora: programada / aberta / pechada
create or replace function public.ccc_ef(c public.ccc_config) returns text
language sql stable as $$
  select case
    when c.ronda = 0 or c.pechada_man then 'pechada'
    when c.abre_a  is not null and now() <  c.abre_a  then 'programada'
    when c.pecha_a is not null and now() >= c.pecha_a then 'pechada'
    else 'aberta' end
$$;

-- Ao pechar (a man ou por hora), a urna BARÁLLASE unha vez para romper calquera orde de inserción.
create or replace function public.ccc_baralla() returns void
language plpgsql security definer set search_path = public as $$
declare c ccc_config%rowtype;
begin
  if not exists (select 1 from ccc_config x where x.id = 1 and x.ronda > 0 and not x.barallada and public.ccc_ef(x) = 'pechada') then
    return;
  end if;
  select * into c from ccc_config where id = 1 for update;
  if c.ronda > 0 and not c.barallada and public.ccc_ef(c) = 'pechada' then
    with b as (delete from ccc_urna where ronda = c.ronda returning opcion)
    insert into ccc_urna (ronda, opcion) select c.ronda, opcion from b order by random();
    update ccc_config set barallada = true where id = 1;
  end if;
end $$;

-- ---------- Funcións públicas ----------
create or replace function public.ccc_estado() returns jsonb
language plpgsql security definer set search_path = public as $$
declare c ccc_config%rowtype;
begin
  perform public.ccc_baralla();
  select * into c from ccc_config where id = 1;
  return jsonb_build_object('ronda', c.ronda, 'estado', public.ccc_ef(c), 'opcions', c.opcions,
                            'abre_a', c.abre_a, 'pecha_a', c.pecha_a, 'agora', now(), 'res_publicos', c.res_publicos);
end $$;

create or replace function public.ccc_resultados() returns jsonb
language plpgsql security definer set search_path = public as $$
declare c ccc_config%rowtype;
begin
  perform public.ccc_baralla();
  select * into c from ccc_config where id = 1;
  if c.ronda = 0 or public.ccc_ef(c) <> 'pechada' or not c.res_publicos then return null; end if;
  return jsonb_build_object('ronda', c.ronda,
    'conta', coalesce((select jsonb_object_agg(t.opcion, t.n)
                       from (select opcion, count(*) as n from ccc_urna where ronda = c.ronda group by opcion) t), '{}'::jsonb));
end $$;

create or replace function public.ccc_publicado() returns jsonb
language sql security definer set search_path = public as $$
  select publicado from ccc_config where id = 1
$$;

-- Votar: comproba o código e o estado, marca o dispositivo e mete o voto na urna SEN identificación.
create or replace function public.ccc_votar(p_pin text, p_token text, p_opcion text) returns void
language plpgsql security definer set search_path = public as $$
declare c ccc_config%rowtype; v_n int;
begin
  select * into c from ccc_config where id = 1 for update;
  if public.ccc_ef(c) <> 'aberta' then raise exception 'votacion_pechada'; end if;
  if c.pin is null or p_pin is distinct from c.pin then raise exception 'pin_incorrecto'; end if;
  if p_token is null or length(p_token) < 16 or length(p_token) > 80 then raise exception 'dispositivo_invalido'; end if;
  if not (p_opcion = 'X' or exists (select 1 from jsonb_array_elements(c.opcions) o where o->>'l' = p_opcion)) then
    raise exception 'opcion_invalida';
  end if;
  insert into ccc_dispositivos (token, ronda) values (p_token, c.ronda) on conflict do nothing;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'xa_votou'; end if;
  insert into ccc_urna (ronda, opcion) values (c.ronda, p_opcion);
end $$;

-- ---------- Funcións de administración (piden a clave) ----------
create or replace function public.ccc_admin_estado(p_clave text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare c ccc_config%rowtype; v_ef text;
begin
  perform public.ccc_admin(p_clave);
  perform public.ccc_baralla();
  select * into c from ccc_config where id = 1;
  v_ef := public.ccc_ef(c);
  return jsonb_build_object(
    'ronda', c.ronda, 'estado', v_ef, 'pin', c.pin, 'opcions', c.opcions,
    'abre_a', c.abre_a, 'pecha_a', c.pecha_a, 'agora', now(), 'res_publicos', c.res_publicos,
    'total', (select count(*) from ccc_urna where ronda = c.ronda),
    'conta', case when v_ef = 'pechada' and c.ronda > 0
                  then coalesce((select jsonb_object_agg(t.opcion, t.n)
                                 from (select opcion, count(*) as n from ccc_urna where ronda = c.ronda group by opcion) t), '{}'::jsonb)
                  else null end
  );
end $$;

-- Abrir unha ronda nova. p_abre_a = null → agora. Peche: p_pecha_a (hora exacta) ou p_minutos (desde a apertura); nada → a man.
create or replace function public.ccc_admin_abrir(p_clave text, p_opcions jsonb, p_abre_a timestamptz,
                                                  p_pecha_a timestamptz, p_minutos int, p_res_publicos boolean) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_pin text; v_ronda int; v_old int; v_pecha timestamptz;
begin
  perform public.ccc_admin(p_clave);
  if jsonb_typeof(p_opcions) <> 'array' or jsonb_array_length(p_opcions) < 2 then raise exception 'opcion_invalida'; end if;
  v_pecha := p_pecha_a;
  if v_pecha is null and p_minutos is not null and p_minutos > 0 then
    v_pecha := coalesce(p_abre_a, now()) + make_interval(mins => p_minutos);
  end if;
  if v_pecha is not null and p_abre_a is not null and v_pecha <= p_abre_a then raise exception 'datas_invalidas'; end if;
  if v_pecha is not null and p_abre_a is null and v_pecha <= now() then raise exception 'datas_invalidas'; end if;
  select ronda into v_old from ccc_config where id = 1 for update;
  if v_old > 0 then  -- baralla a urna da ronda anterior antes de deixala
    with b as (delete from ccc_urna where ronda = v_old returning opcion)
    insert into ccc_urna (ronda, opcion) select v_old, opcion from b order by random();
  end if;
  v_pin := lpad((floor(random() * 10000))::int::text, 4, '0');
  update ccc_config set ronda = ronda + 1, pechada_man = false, barallada = false, pin = v_pin, opcions = p_opcions,
         abre_a = p_abre_a, pecha_a = v_pecha, res_publicos = coalesce(p_res_publicos, true)
  where id = 1 returning ronda into v_ronda;
  return jsonb_build_object('ronda', v_ronda, 'pin', v_pin);
end $$;

create or replace function public.ccc_admin_pechar(p_clave text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ccc_admin(p_clave);
  update ccc_config set pechada_man = true where id = 1;
  perform public.ccc_baralla();
end $$;

-- Reabrir a ronda actual (sen peche automático, agás que despois o axustes).
create or replace function public.ccc_admin_reabrir(p_clave text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ccc_admin(p_clave);
  update ccc_config set pechada_man = false, barallada = false,
         pecha_a = case when pecha_a is not null and pecha_a <= now() then null else pecha_a end,
         abre_a  = case when abre_a  is not null and abre_a  >  now() then abre_a else null end
  where id = 1 and ronda > 0;
end $$;

-- Axustes sobre a marcha: estender o peche, quitar o peche automático, abrir agora, resultados públicos.
create or replace function public.ccc_admin_axustar(p_clave text, p_minutos int, p_quitar_pecha boolean,
                                                    p_res_publicos boolean, p_abrir_agora boolean) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ccc_admin(p_clave);
  perform 1 from ccc_config where id = 1 for update;
  if coalesce(p_abrir_agora, false) then update ccc_config set abre_a = null where id = 1; end if;
  if coalesce(p_quitar_pecha, false) then update ccc_config set pecha_a = null where id = 1; end if;
  if p_minutos is not null and p_minutos > 0 then
    update ccc_config set pecha_a = greatest(coalesce(pecha_a, now()), now()) + make_interval(mins => p_minutos),
                          pechada_man = false, barallada = false
    where id = 1 and ronda > 0;
  end if;
  if p_res_publicos is not null then update ccc_config set res_publicos = p_res_publicos where id = 1; end if;
end $$;

create or replace function public.ccc_admin_publicar(p_clave text, p_datos jsonb) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ccc_admin(p_clave);
  update ccc_config set publicado = p_datos where id = 1;
end $$;

-- ---------- Permisos: a web (clave anon) só pode chamar estas funcións ----------
revoke all on function public.ccc_ef(public.ccc_config) from public, anon, authenticated;
revoke all on function public.ccc_baralla() from public, anon, authenticated;
grant execute on function public.ccc_estado()                                                  to anon, authenticated;
grant execute on function public.ccc_resultados()                                              to anon, authenticated;
grant execute on function public.ccc_publicado()                                               to anon, authenticated;
grant execute on function public.ccc_votar(text, text, text)                                   to anon, authenticated;
grant execute on function public.ccc_admin_estado(text)                                        to anon, authenticated;
grant execute on function public.ccc_admin_abrir(text, jsonb, timestamptz, timestamptz, int, boolean) to anon, authenticated;
grant execute on function public.ccc_admin_pechar(text)                                        to anon, authenticated;
grant execute on function public.ccc_admin_reabrir(text)                                       to anon, authenticated;
grant execute on function public.ccc_admin_axustar(text, int, boolean, boolean, boolean)       to anon, authenticated;
grant execute on function public.ccc_admin_publicar(text, jsonb)                               to anon, authenticated;

-- ---------------------------------------------------------------------
--  (Opcional) Se antes executaras unha versión anterior deste script,
--  que usaba o prefixo cal_, podes borrar aquelas cousas con isto.
--  Está comentado a propósito: descomenta só se sabes que eran as túas.
-- ---------------------------------------------------------------------
-- drop function if exists public.cal_estado(), public.cal_resultados(), public.cal_publicado(),
--   public.cal_votar(text,text,text), public.cal_admin_estado(text), public.cal_admin_pechar(text),
--   public.cal_admin_reabrir(text), public.cal_admin_axustar(text,int,boolean,boolean,boolean),
--   public.cal_admin_publicar(text,jsonb), public.cal_admin(text), public.cal_baralla(), public.cal_nomes(text),
--   public.cal_admin_abrir(text,jsonb,timestamptz,timestamptz,int,boolean), public.cal_admin_abrir(text,jsonb,text[]);
-- drop table if exists public.cal_urna, public.cal_dispositivos, public.cal_votantes, public.cal_config;
