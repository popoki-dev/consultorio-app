-- Esquema do servidor (Supabase / PostgreSQL) para a sincronização.
-- Rode no SQL Editor do projeto Supabase.
--
-- Colunas espelham o banco local. Datas ficam em texto (mesmo formato do
-- aparelho) para não haver conversão de fuso. server_updated_at é gerado
-- pelo banco e serve de cursor para cada aparelho baixar só o que mudou.
-- Row Level Security garante que cada usuário só acessa os próprios dados.

create or replace function public.touch_server_updated_at()
returns trigger language plpgsql as $$
begin
  new.server_updated_at := clock_timestamp();
  return new;
end;
$$;

-- Última alteração vence também no servidor: se um aparelho envia uma
-- versão mais antiga que a guardada, a gravação é ignorada (a linha não
-- volta no upsert e o app baixa a versão mais nova). O nome do gatilho
-- ("trg_keep") vem antes de "trg_touch" porque o Postgres dispara gatilhos
-- BEFORE em ordem alfabética.
create or replace function public.keep_newest()
returns trigger language plpgsql as $$
begin
  if new.updated_at::timestamptz < old.updated_at::timestamptz then
    return null;
  end if;
  return new;
end;
$$;

create table if not exists public.care_lines (
  id text primary key,
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null,
  color bigint not null,
  default_return_days integer,
  updated_at text not null,
  deleted_at text,
  server_updated_at timestamptz not null default clock_timestamp()
);

create table if not exists public.patients (
  id text primary key,
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null,
  birth_date text,
  sex text,
  phone text,
  document text,
  care_line_id text,
  cid_codes text,
  notes text,
  created_at text not null,
  updated_at text not null,
  deleted_at text,
  server_updated_at timestamptz not null default clock_timestamp()
);

-- v1.2: gestação (DUM e data do parto/encerramento).
alter table public.patients add column if not exists dum text;
alter table public.patients add column if not exists pregnancy_end text;

-- v1.3: paciente em várias linhas de cuidado (care_line_id continua com a
-- primeira, para aparelhos com versão anterior do app).
alter table public.patients add column if not exists care_line_ids text;

create table if not exists public.appointments (
  id text primary key,
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  patient_id text not null,
  start_at text not null,
  duration_min integer not null default 30,
  status text not null,
  notes text,
  return_due text,
  return_resolved integer not null default 0,
  updated_at text not null,
  deleted_at text,
  server_updated_at timestamptz not null default clock_timestamp()
);

create table if not exists public.prescriptions (
  id text primary key,
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  patient_id text not null,
  medication text not null,
  dosage text,
  issued_at text not null,
  expires_at text not null,
  resolved integer not null default 0,
  notes text,
  updated_at text not null,
  deleted_at text,
  server_updated_at timestamptz not null default clock_timestamp()
);

-- v1.3: receituário com vários medicamentos.
alter table public.prescriptions add column if not exists group_id text;

create table if not exists public.exams (
  id text primary key,
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  patient_id text not null,
  name text not null,
  performed_at text not null,
  result text,
  next_due text,
  resolved integer not null default 0,
  updated_at text not null,
  deleted_at text,
  server_updated_at timestamptz not null default clock_timestamp()
);

do $$
declare t text;
begin
  foreach t in array array['care_lines','patients','appointments','prescriptions','exams'] loop
    execute format('drop trigger if exists trg_keep on public.%I', t);
    execute format(
      'create trigger trg_keep before update on public.%I
         for each row execute function public.keep_newest()', t);
    execute format('drop trigger if exists trg_touch on public.%I', t);
    execute format(
      'create trigger trg_touch before insert or update on public.%I
         for each row execute function public.touch_server_updated_at()', t);
    execute format('create index if not exists %I on public.%I (owner_id, server_updated_at)',
                   t || '_sync_idx', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists owner_only on public.%I', t);
    execute format(
      'create policy owner_only on public.%I for all
         using (owner_id = auth.uid()) with check (owner_id = auth.uid())', t);
  end loop;
end $$;
