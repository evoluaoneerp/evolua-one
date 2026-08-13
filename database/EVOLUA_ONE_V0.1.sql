-- ============================================================
-- EVOLUA ONE - FUNDAÇÃO V0.1 | BANCO NOVO
-- Supabase PostgreSQL + Auth + Storage + RLS
-- NÃO depende do banco antigo do Evolua CRM.
-- Execute este arquivo inteiro no SQL Editor do novo projeto.
-- ============================================================

begin;

create extension if not exists pgcrypto;
create schema if not exists private;

-- ------------------------------------------------------------
-- TIPOS
-- ------------------------------------------------------------

do $$ begin
  create type public.app_role as enum (
    'owner',
    'admin',
    'commercial',
    'financial',
    'reception',
    'student_management',
    'viewer'
  );
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.one_student_status as enum ('ativo','inativo','trancado','cancelado','concluido');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.one_product_type as enum ('curso','pacote','plano','servico');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.one_contract_status as enum ('rascunho','aguardando_assinatura','ativo','trancado','cancelado','concluido','substituido');
exception when duplicate_object then null;
end $$;

-- ------------------------------------------------------------
-- BASE: PERFIS, WORKSPACE E MEMBROS
-- ------------------------------------------------------------

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  email text,
  phone text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.workspaces (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.workspace_members (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.app_role not null default 'viewer',
  active boolean not null default true,
  custom_permissions jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (workspace_id, user_id)
);

create index if not exists idx_workspace_members_user on public.workspace_members(user_id, active);

-- ------------------------------------------------------------
-- CADASTROS
-- ------------------------------------------------------------

create table if not exists public.one_students (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  full_name text not null,
  preferred_name text,
  birth_date date,
  cpf text,
  rg text,
  rg_issuer text,
  sex text,
  phone text,
  whatsapp text,
  email text,
  cep text,
  street text,
  number text,
  complement text,
  neighborhood text,
  city text,
  state text,
  reference_point text,
  photo_path text,
  status public.one_student_status not null default 'ativo',
  notes text,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists idx_one_students_workspace_cpf
  on public.one_students(workspace_id, cpf)
  where cpf is not null and btrim(cpf) <> '';
create index if not exists idx_one_students_workspace_name on public.one_students(workspace_id, full_name);
create index if not exists idx_one_students_birth_date on public.one_students(workspace_id, birth_date) where birth_date is not null;

create table if not exists public.one_guardians (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  full_name text not null,
  birth_date date,
  cpf text,
  rg text,
  rg_issuer text,
  phone text,
  whatsapp text,
  email text,
  profession text,
  workplace text,
  cep text,
  street text,
  number text,
  complement text,
  neighborhood text,
  city text,
  state text,
  reference_point text,
  photo_path text,
  active boolean not null default true,
  notes text,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists idx_one_guardians_workspace_cpf
  on public.one_guardians(workspace_id, cpf)
  where cpf is not null and btrim(cpf) <> '';
create index if not exists idx_one_guardians_workspace_name on public.one_guardians(workspace_id, full_name);
create index if not exists idx_one_guardians_birth_date on public.one_guardians(workspace_id, birth_date) where birth_date is not null;

create table if not exists public.one_student_guardians (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  student_id uuid not null references public.one_students(id) on delete cascade,
  guardian_id uuid not null references public.one_guardians(id) on delete cascade,
  relationship text,
  is_legal boolean not null default false,
  is_financial boolean not null default false,
  is_primary boolean not null default false,
  is_emergency boolean not null default false,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  unique(student_id, guardian_id)
);

create table if not exists public.one_companies (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  legal_name text not null,
  trade_name text,
  cnpj text,
  state_registration text,
  opening_date date,
  segment text,
  phone text,
  whatsapp text,
  email text,
  website text,
  contact_name text,
  contact_role text,
  cep text,
  street text,
  number text,
  complement text,
  neighborhood text,
  city text,
  state text,
  reference_point text,
  photo_path text,
  active boolean not null default true,
  notes text,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists idx_one_companies_workspace_cnpj
  on public.one_companies(workspace_id, cnpj)
  where cnpj is not null and btrim(cnpj) <> '';
create index if not exists idx_one_companies_workspace_name on public.one_companies(workspace_id, legal_name);

-- ------------------------------------------------------------
-- PRODUTOS, CURSOS, PACOTES, PLANOS E SERVIÇOS
-- ------------------------------------------------------------

create table if not exists public.one_products (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  name text not null,
  code text,
  product_type public.one_product_type not null default 'curso',
  category text,
  modality text,
  workload_hours integer check (workload_hours is null or workload_hours >= 0),
  description text,
  list_price numeric(12,2) not null default 0 check (list_price >= 0),
  enrollment_fee numeric(12,2) not null default 0 check (enrollment_fee >= 0),
  max_installments integer not null default 1 check (max_installments > 0),
  access_months integer check (access_months is null or access_months >= 0),
  certification text,
  active boolean not null default true,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(workspace_id, name)
);

create table if not exists public.one_product_components (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  parent_product_id uuid not null references public.one_products(id) on delete cascade,
  child_product_id uuid not null references public.one_products(id) on delete restrict,
  quantity integer not null default 1 check (quantity > 0),
  notes text,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  unique(parent_product_id, child_product_id),
  check(parent_product_id <> child_product_id)
);

-- ------------------------------------------------------------
-- GESTÃO DO ALUNO E CONTRATOS
-- ------------------------------------------------------------

create table if not exists public.one_contracts (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  contract_number text not null,
  contract_date date not null default current_date,
  student_id uuid references public.one_students(id) on delete restrict,
  guardian_id uuid references public.one_guardians(id) on delete restrict,
  company_id uuid references public.one_companies(id) on delete restrict,
  product_id uuid references public.one_products(id) on delete restrict,
  status public.one_contract_status not null default 'rascunho',
  start_date date,
  end_date date,
  enrollment_fee numeric(12,2) not null default 0 check (enrollment_fee >= 0),
  contract_value numeric(12,2) not null default 0 check (contract_value >= 0),
  installments integer not null default 1 check (installments > 0),
  installment_value numeric(12,2) not null default 0 check (installment_value >= 0),
  due_day integer check (due_day is null or due_day between 1 and 31),
  payment_method text,
  notes text,
  pdf_path text,
  signed_at timestamptz,
  status_changed_at timestamptz not null default now(),
  status_reason text,
  created_by uuid not null default auth.uid() references auth.users(id),
  updated_by uuid default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(workspace_id, contract_number),
  check(student_id is not null or company_id is not null)
);

create index if not exists idx_one_contracts_workspace_status on public.one_contracts(workspace_id, status);
create index if not exists idx_one_contracts_student on public.one_contracts(student_id, created_at desc);

create table if not exists public.one_contract_status_history (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  contract_id uuid not null references public.one_contracts(id) on delete cascade,
  old_status public.one_contract_status,
  new_status public.one_contract_status not null,
  reason text,
  changed_by uuid default auth.uid() references auth.users(id),
  changed_at timestamptz not null default now()
);

create table if not exists public.one_service_history (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  student_id uuid references public.one_students(id) on delete cascade,
  guardian_id uuid references public.one_guardians(id) on delete cascade,
  company_id uuid references public.one_companies(id) on delete cascade,
  occurred_at timestamptz not null default now(),
  channel text,
  category text,
  summary text not null,
  outcome text,
  next_action text,
  return_at timestamptz,
  status text not null default 'concluido',
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(
    (case when student_id is not null then 1 else 0 end) +
    (case when guardian_id is not null then 1 else 0 end) +
    (case when company_id is not null then 1 else 0 end) = 1
  )
);

-- ------------------------------------------------------------
-- AUDITORIA
-- ------------------------------------------------------------

create table if not exists public.one_audit_log (
  id bigint generated always as identity primary key,
  workspace_id uuid,
  table_name text not null,
  record_id uuid,
  action text not null check (action in ('INSERT','UPDATE','DELETE')),
  old_data jsonb,
  new_data jsonb,
  changed_by uuid default auth.uid() references auth.users(id) on delete set null,
  changed_at timestamptz not null default now()
);

create index if not exists idx_one_audit_workspace_date on public.one_audit_log(workspace_id, changed_at desc);
create index if not exists idx_one_audit_record on public.one_audit_log(table_name, record_id, changed_at desc);

-- ------------------------------------------------------------
-- FUNÇÕES DE ATUALIZAÇÃO E PERFIL
-- ------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, email)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', split_part(coalesce(new.email, ''), '@', 1)),
    new.email
  )
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

insert into public.profiles (id, full_name, email)
select
  u.id,
  coalesce(u.raw_user_meta_data ->> 'full_name', split_part(coalesce(u.email, ''), '@', 1)),
  u.email
from auth.users u
on conflict (id) do update set email = excluded.email;

-- ------------------------------------------------------------
-- FUNÇÕES PRIVADAS DE SEGURANÇA
-- ------------------------------------------------------------

create or replace function private.is_workspace_member(target_workspace uuid)
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select exists (
    select 1
    from public.workspace_members wm
    where wm.workspace_id = target_workspace
      and wm.user_id = (select auth.uid())
      and wm.active = true
  );
$$;

create or replace function private.is_workspace_admin(target_workspace uuid)
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select exists (
    select 1
    from public.workspace_members wm
    where wm.workspace_id = target_workspace
      and wm.user_id = (select auth.uid())
      and wm.active = true
      and wm.role in ('owner','admin')
  );
$$;

create or replace function private.can_write_workspace(target_workspace uuid)
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select exists (
    select 1
    from public.workspace_members wm
    where wm.workspace_id = target_workspace
      and wm.user_id = (select auth.uid())
      and wm.active = true
      and wm.role <> 'viewer'
  );
$$;

create or replace function private.shares_workspace(other_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select exists (
    select 1
    from public.workspace_members mine
    join public.workspace_members theirs on theirs.workspace_id = mine.workspace_id
    where mine.user_id = (select auth.uid())
      and mine.active = true
      and theirs.user_id = other_user
      and theirs.active = true
  );
$$;

-- ------------------------------------------------------------
-- BOOTSTRAP DO PRIMEIRO PROPRIETÁRIO
-- Primeiro usuário autenticado cria o workspace Evolua One.
-- Usuários seguintes precisam ser vinculados pelo administrador.
-- ------------------------------------------------------------

create or replace function public.bootstrap_current_user(workspace_name text default 'Evolua One')
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_workspace uuid;
  workspace_count integer;
begin
  if current_user_id is null then
    raise exception 'Usuário não autenticado';
  end if;

  insert into public.profiles (id, full_name, email)
  select
    u.id,
    coalesce(u.raw_user_meta_data ->> 'full_name', split_part(coalesce(u.email, ''), '@', 1)),
    u.email
  from auth.users u
  where u.id = current_user_id
  on conflict (id) do update set email = excluded.email;

  select wm.workspace_id
    into target_workspace
  from public.workspace_members wm
  where wm.user_id = current_user_id
    and wm.active = true
  order by wm.created_at
  limit 1;

  if target_workspace is not null then
    return target_workspace;
  end if;

  select count(*) into workspace_count from public.workspaces;

  if workspace_count = 0 then
    insert into public.workspaces (name, slug, created_by)
    values (coalesce(nullif(trim(workspace_name), ''), 'Evolua One'), 'evolua-one', current_user_id)
    returning id into target_workspace;

    insert into public.workspace_members (workspace_id, user_id, role, active)
    values (target_workspace, current_user_id, 'owner', true);

    return target_workspace;
  end if;

  raise exception 'Usuário ainda não está vinculado ao Evolua One. Solicite acesso ao proprietário.';
end;
$$;

-- ------------------------------------------------------------
-- VALIDAÇÃO ENTRE TABELAS
-- ------------------------------------------------------------

create or replace function public.one_validate_workspace_links()
returns trigger
language plpgsql
set search_path = public
as $$
declare target uuid;
begin
  if tg_table_name = 'one_student_guardians' then
    select workspace_id into target from public.one_students where id = new.student_id;
    if target is distinct from new.workspace_id then raise exception 'Aluno pertence a outro espaço de trabalho'; end if;
    select workspace_id into target from public.one_guardians where id = new.guardian_id;
    if target is distinct from new.workspace_id then raise exception 'Responsável pertence a outro espaço de trabalho'; end if;
  elsif tg_table_name = 'one_product_components' then
    select workspace_id into target from public.one_products where id = new.parent_product_id;
    if target is distinct from new.workspace_id then raise exception 'Produto principal pertence a outro espaço de trabalho'; end if;
    select workspace_id into target from public.one_products where id = new.child_product_id;
    if target is distinct from new.workspace_id then raise exception 'Componente pertence a outro espaço de trabalho'; end if;
  elsif tg_table_name = 'one_contracts' then
    if new.student_id is not null then
      select workspace_id into target from public.one_students where id = new.student_id;
      if target is distinct from new.workspace_id then raise exception 'Aluno pertence a outro espaço de trabalho'; end if;
    end if;
    if new.guardian_id is not null then
      select workspace_id into target from public.one_guardians where id = new.guardian_id;
      if target is distinct from new.workspace_id then raise exception 'Responsável pertence a outro espaço de trabalho'; end if;
    end if;
    if new.company_id is not null then
      select workspace_id into target from public.one_companies where id = new.company_id;
      if target is distinct from new.workspace_id then raise exception 'Empresa pertence a outro espaço de trabalho'; end if;
    end if;
    if new.product_id is not null then
      select workspace_id into target from public.one_products where id = new.product_id;
      if target is distinct from new.workspace_id then raise exception 'Produto pertence a outro espaço de trabalho'; end if;
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.one_touch_contract()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  new.updated_by = auth.uid();
  if old.status is distinct from new.status then new.status_changed_at = now(); end if;
  return new;
end;
$$;

create or replace function public.one_log_contract_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.one_contract_status_history(workspace_id,contract_id,old_status,new_status,reason,changed_by)
    values(new.workspace_id,new.id,null,new.status,new.status_reason,auth.uid());
  elsif old.status is distinct from new.status then
    insert into public.one_contract_status_history(workspace_id,contract_id,old_status,new_status,reason,changed_by)
    values(new.workspace_id,new.id,old.status,new.status,new.status_reason,auth.uid());
  end if;
  return new;
end;
$$;

create or replace function public.one_write_audit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  ws uuid;
  rid uuid;
begin
  if tg_op = 'DELETE' then
    ws := old.workspace_id;
    rid := old.id;
    insert into public.one_audit_log(workspace_id, table_name, record_id, action, old_data, new_data, changed_by)
    values(ws, tg_table_name, rid, tg_op, to_jsonb(old), null, auth.uid());
    return old;
  elsif tg_op = 'UPDATE' then
    ws := new.workspace_id;
    rid := new.id;
    insert into public.one_audit_log(workspace_id, table_name, record_id, action, old_data, new_data, changed_by)
    values(ws, tg_table_name, rid, tg_op, to_jsonb(old), to_jsonb(new), auth.uid());
    return new;
  else
    ws := new.workspace_id;
    rid := new.id;
    insert into public.one_audit_log(workspace_id, table_name, record_id, action, old_data, new_data, changed_by)
    values(ws, tg_table_name, rid, tg_op, null, to_jsonb(new), auth.uid());
    return new;
  end if;
end;
$$;

-- ------------------------------------------------------------
-- TRIGGERS
-- ------------------------------------------------------------

do $$
declare t text;
begin
  foreach t in array array['profiles','workspaces','workspace_members','one_students','one_guardians','one_companies','one_products','one_service_history'] loop
    execute format('drop trigger if exists trg_%I_updated_at on public.%I', t, t);
    execute format('create trigger trg_%I_updated_at before update on public.%I for each row execute function public.set_updated_at()', t, t);
  end loop;
end $$;

drop trigger if exists trg_one_contract_touch on public.one_contracts;
create trigger trg_one_contract_touch before update on public.one_contracts
for each row execute function public.one_touch_contract();

drop trigger if exists trg_one_contract_status_history on public.one_contracts;
create trigger trg_one_contract_status_history after insert or update of status on public.one_contracts
for each row execute function public.one_log_contract_status();

drop trigger if exists trg_one_validate_student_guardians on public.one_student_guardians;
create trigger trg_one_validate_student_guardians before insert or update on public.one_student_guardians
for each row execute function public.one_validate_workspace_links();

drop trigger if exists trg_one_validate_product_components on public.one_product_components;
create trigger trg_one_validate_product_components before insert or update on public.one_product_components
for each row execute function public.one_validate_workspace_links();

drop trigger if exists trg_one_validate_contracts on public.one_contracts;
create trigger trg_one_validate_contracts before insert or update on public.one_contracts
for each row execute function public.one_validate_workspace_links();

do $$
declare t text;
begin
  foreach t in array array['one_students','one_guardians','one_student_guardians','one_companies','one_products','one_product_components','one_contracts','one_service_history'] loop
    execute format('drop trigger if exists trg_%I_audit on public.%I', t, t);
    execute format('create trigger trg_%I_audit after insert or update or delete on public.%I for each row execute function public.one_write_audit()', t, t);
  end loop;
end $$;

-- ------------------------------------------------------------
-- RLS
-- ------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.workspaces enable row level security;
alter table public.workspace_members enable row level security;

do $$
declare t text;
begin
  foreach t in array array[
    'one_students','one_guardians','one_student_guardians','one_companies','one_products',
    'one_product_components','one_contracts','one_contract_status_history','one_service_history','one_audit_log'
  ] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- Perfis
DROP POLICY IF EXISTS profile_select ON public.profiles;
CREATE POLICY profile_select ON public.profiles FOR SELECT TO authenticated
USING ((select auth.uid()) = id OR private.shares_workspace(id));
DROP POLICY IF EXISTS profile_update ON public.profiles;
CREATE POLICY profile_update ON public.profiles FOR UPDATE TO authenticated
USING ((select auth.uid()) = id) WITH CHECK ((select auth.uid()) = id);

-- Workspaces
DROP POLICY IF EXISTS workspace_select ON public.workspaces;
CREATE POLICY workspace_select ON public.workspaces FOR SELECT TO authenticated
USING (private.is_workspace_member(id));
DROP POLICY IF EXISTS workspace_update ON public.workspaces;
CREATE POLICY workspace_update ON public.workspaces FOR UPDATE TO authenticated
USING (private.is_workspace_admin(id)) WITH CHECK (private.is_workspace_admin(id));

-- Membros
DROP POLICY IF EXISTS member_select ON public.workspace_members;
CREATE POLICY member_select ON public.workspace_members FOR SELECT TO authenticated
USING (private.is_workspace_member(workspace_id));
DROP POLICY IF EXISTS member_insert ON public.workspace_members;
CREATE POLICY member_insert ON public.workspace_members FOR INSERT TO authenticated
WITH CHECK (private.is_workspace_admin(workspace_id));
DROP POLICY IF EXISTS member_update ON public.workspace_members;
CREATE POLICY member_update ON public.workspace_members FOR UPDATE TO authenticated
USING (private.is_workspace_admin(workspace_id)) WITH CHECK (private.is_workspace_admin(workspace_id));
DROP POLICY IF EXISTS member_delete ON public.workspace_members;
CREATE POLICY member_delete ON public.workspace_members FOR DELETE TO authenticated
USING (private.is_workspace_admin(workspace_id) AND role <> 'owner');

-- Tabelas operacionais
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'one_students','one_guardians','one_student_guardians','one_companies','one_products',
    'one_product_components','one_contracts','one_service_history'
  ] LOOP
    EXECUTE format('drop policy if exists one_select on public.%I', t);
    EXECUTE format('create policy one_select on public.%I for select to authenticated using (private.is_workspace_member(workspace_id))', t);
    EXECUTE format('drop policy if exists one_insert on public.%I', t);
    EXECUTE format('create policy one_insert on public.%I for insert to authenticated with check (private.can_write_workspace(workspace_id))', t);
    EXECUTE format('drop policy if exists one_update on public.%I', t);
    EXECUTE format('create policy one_update on public.%I for update to authenticated using (private.can_write_workspace(workspace_id)) with check (private.can_write_workspace(workspace_id))', t);
    EXECUTE format('drop policy if exists one_delete on public.%I', t);
    EXECUTE format('create policy one_delete on public.%I for delete to authenticated using (private.is_workspace_admin(workspace_id))', t);
  END LOOP;
END $$;

-- Históricos são leitura, gravação somente por trigger.
DROP POLICY IF EXISTS one_history_select ON public.one_contract_status_history;
CREATE POLICY one_history_select ON public.one_contract_status_history FOR SELECT TO authenticated
USING (private.is_workspace_member(workspace_id));

DROP POLICY IF EXISTS one_audit_select ON public.one_audit_log;
CREATE POLICY one_audit_select ON public.one_audit_log FOR SELECT TO authenticated
USING (private.is_workspace_admin(workspace_id));

-- ------------------------------------------------------------
-- STORAGE PRIVADO PARA FOTOS E FUTUROS ARQUIVOS LEVES
-- ------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'evolua-one',
  'evolua-one',
  false,
  5242880,
  array['image/jpeg','image/png','image/webp','image/heic','image/heif']
)
on conflict (id) do update set
  public = false,
  file_size_limit = 5242880,
  allowed_mime_types = excluded.allowed_mime_types;

DROP POLICY IF EXISTS one_storage_select ON storage.objects;
CREATE POLICY one_storage_select ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'evolua-one'
  AND private.is_workspace_member(((storage.foldername(name))[1])::uuid)
);

DROP POLICY IF EXISTS one_storage_insert ON storage.objects;
CREATE POLICY one_storage_insert ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'evolua-one'
  AND private.can_write_workspace(((storage.foldername(name))[1])::uuid)
);

DROP POLICY IF EXISTS one_storage_update ON storage.objects;
CREATE POLICY one_storage_update ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'evolua-one'
  AND private.can_write_workspace(((storage.foldername(name))[1])::uuid)
)
WITH CHECK (
  bucket_id = 'evolua-one'
  AND private.can_write_workspace(((storage.foldername(name))[1])::uuid)
);

DROP POLICY IF EXISTS one_storage_delete ON storage.objects;
CREATE POLICY one_storage_delete ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'evolua-one'
  AND private.is_workspace_admin(((storage.foldername(name))[1])::uuid)
);

-- ------------------------------------------------------------
-- PERMISSÕES DE EXECUÇÃO
-- ------------------------------------------------------------

revoke all on function public.bootstrap_current_user(text) from public, anon;
grant execute on function public.bootstrap_current_user(text) to authenticated;

grant usage on schema private to authenticated;
revoke all on function private.is_workspace_member(uuid) from public;
revoke all on function private.is_workspace_admin(uuid) from public;
revoke all on function private.can_write_workspace(uuid) from public;
revoke all on function private.shares_workspace(uuid) from public;
grant execute on function private.is_workspace_member(uuid) to authenticated;
grant execute on function private.is_workspace_admin(uuid) to authenticated;
grant execute on function private.can_write_workspace(uuid) to authenticated;
grant execute on function private.shares_workspace(uuid) to authenticated;

commit;

-- Resultado esperado no SQL Editor:
-- Success. No rows returned
