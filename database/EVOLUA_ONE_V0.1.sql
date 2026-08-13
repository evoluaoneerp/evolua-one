-- ============================================================
-- EVOLUA ONE - FUNDAÇÃO V0.1
-- Migração incremental para o MESMO Supabase do Evolua CRM.
-- Não apaga tabelas nem dados existentes do CRM.
-- Execute este arquivo inteiro no SQL Editor do Supabase.
-- ============================================================

begin;

create extension if not exists pgcrypto;

-- ------------------------------------------------------------
-- TIPOS DO EVOLUA ONE
-- ------------------------------------------------------------

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
  where cpf is not null and cpf <> '';
create index if not exists idx_one_students_workspace_name
  on public.one_students(workspace_id, full_name);
create index if not exists idx_one_students_birth_date
  on public.one_students(workspace_id, birth_date)
  where birth_date is not null;

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
  where cpf is not null and cpf <> '';
create index if not exists idx_one_guardians_workspace_name
  on public.one_guardians(workspace_id, full_name);
create index if not exists idx_one_guardians_birth_date
  on public.one_guardians(workspace_id, birth_date)
  where birth_date is not null;

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
  where cnpj is not null and cnpj <> '';
create index if not exists idx_one_companies_workspace_name
  on public.one_companies(workspace_id, legal_name);

-- ------------------------------------------------------------
-- PRODUTOS: CURSOS, PACOTES, PLANOS E SERVIÇOS
-- ------------------------------------------------------------

create table if not exists public.one_products (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  legacy_course_id uuid references public.courses(id) on delete set null,
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
  created_at timestamptz not null default now(),
  unique(parent_product_id, child_product_id),
  check(parent_product_id <> child_product_id)
);

-- Importa os cursos já existentes no CRM para o novo catálogo.
insert into public.one_products (
  workspace_id, legacy_course_id, name, product_type, category, modality,
  list_price, active, created_by
)
select
  c.workspace_id, c.id, c.name,
  case when lower(coalesce(c.category,'')) like '%academy%' then 'plano'::public.one_product_type else 'curso'::public.one_product_type end,
  c.category, c.modality::text, c.list_price, c.active, c.created_by
from public.courses c
on conflict (workspace_id, name) do nothing;

-- ------------------------------------------------------------
-- CONTRATOS - PRIMEIRA FUNDAÇÃO
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

create index if not exists idx_one_contracts_workspace_status
  on public.one_contracts(workspace_id, status);
create index if not exists idx_one_contracts_student
  on public.one_contracts(student_id, created_at desc);

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

-- ------------------------------------------------------------
-- HISTÓRICO INDIVIDUAL DE ATENDIMENTO
-- ------------------------------------------------------------

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
-- UPDATED_AT
-- ------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path=public
as $$
begin
  new.updated_at=now();
  return new;
end;
$$;

create or replace function public.one_touch_contract()
returns trigger language plpgsql set search_path=public as $$
begin
  new.updated_at = now();
  new.updated_by = auth.uid();
  if old.status is distinct from new.status then
    new.status_changed_at = now();
  end if;
  return new;
end;
$$;

create or replace function public.one_log_contract_status()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_op='INSERT' then
    insert into public.one_contract_status_history(workspace_id,contract_id,old_status,new_status,reason,changed_by)
    values(new.workspace_id,new.id,null,new.status,new.status_reason,auth.uid());
  elsif old.status is distinct from new.status then
    insert into public.one_contract_status_history(workspace_id,contract_id,old_status,new_status,reason,changed_by)
    values(new.workspace_id,new.id,old.status,new.status,new.status_reason,auth.uid());
  end if;
  return new;
end;
$$;

-- Segurança de relacionamentos: não aceita vínculos cruzando workspaces.
create or replace function public.one_validate_workspace_links()
returns trigger language plpgsql set search_path=public as $$
declare target uuid;
begin
  if tg_table_name='one_student_guardians' then
    select workspace_id into target from public.one_students where id=new.student_id;
    if target is distinct from new.workspace_id then raise exception 'Aluno pertence a outro espaço de trabalho'; end if;
    select workspace_id into target from public.one_guardians where id=new.guardian_id;
    if target is distinct from new.workspace_id then raise exception 'Responsável pertence a outro espaço de trabalho'; end if;
  elsif tg_table_name='one_product_components' then
    select workspace_id into target from public.one_products where id=new.parent_product_id;
    if target is distinct from new.workspace_id then raise exception 'Produto principal pertence a outro espaço de trabalho'; end if;
    select workspace_id into target from public.one_products where id=new.child_product_id;
    if target is distinct from new.workspace_id then raise exception 'Componente pertence a outro espaço de trabalho'; end if;
  elsif tg_table_name='one_contracts' then
    if new.student_id is not null then select workspace_id into target from public.one_students where id=new.student_id; if target is distinct from new.workspace_id then raise exception 'Aluno pertence a outro espaço de trabalho'; end if; end if;
    if new.guardian_id is not null then select workspace_id into target from public.one_guardians where id=new.guardian_id; if target is distinct from new.workspace_id then raise exception 'Responsável pertence a outro espaço de trabalho'; end if; end if;
    if new.company_id is not null then select workspace_id into target from public.one_companies where id=new.company_id; if target is distinct from new.workspace_id then raise exception 'Empresa pertence a outro espaço de trabalho'; end if; end if;
    if new.product_id is not null then select workspace_id into target from public.one_products where id=new.product_id; if target is distinct from new.workspace_id then raise exception 'Produto pertence a outro espaço de trabalho'; end if; end if;
  end if;
  return new;
end;
$$;

-- Triggers de atualização.
do $$
declare t text;
begin
  foreach t in array array['one_students','one_guardians','one_companies','one_products','one_service_history'] loop
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

-- ------------------------------------------------------------
-- RLS
-- ------------------------------------------------------------

do $$
declare t text;
begin
  foreach t in array array[
    'one_students','one_guardians','one_student_guardians','one_companies','one_products',
    'one_product_components','one_contracts','one_service_history'
  ] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'one_students','one_guardians','one_student_guardians','one_companies','one_products',
    'one_product_components','one_contracts','one_service_history'
  ] loop
    execute format('drop policy if exists one_select on public.%I', t);
    execute format('create policy one_select on public.%I for select to authenticated using (public.is_workspace_member(workspace_id))', t);
    execute format('drop policy if exists one_insert on public.%I', t);
    execute format('create policy one_insert on public.%I for insert to authenticated with check (public.can_write_workspace(workspace_id))', t);
    execute format('drop policy if exists one_update on public.%I', t);
    execute format('create policy one_update on public.%I for update to authenticated using (public.can_write_workspace(workspace_id)) with check (public.can_write_workspace(workspace_id))', t);
    execute format('drop policy if exists one_delete on public.%I', t);
    execute format('create policy one_delete on public.%I for delete to authenticated using (public.is_workspace_admin(workspace_id))', t);
  end loop;
end $$;

-- Histórico de status contratual é somente leitura para usuários.
drop policy if exists one_select on public.one_contract_status_history;
create policy one_select on public.one_contract_status_history for select to authenticated
using (public.is_workspace_member(workspace_id));
drop policy if exists one_insert on public.one_contract_status_history;
drop policy if exists one_update on public.one_contract_status_history;
drop policy if exists one_delete on public.one_contract_status_history;

-- ------------------------------------------------------------
-- STORAGE PRIVADO PARA FOTOS
-- O caminho sempre começa pelo workspace UUID.
-- ------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'evolua-one',
  'evolua-one',
  false,
  5242880,
  array['image/jpeg','image/png','image/webp','image/heic','image/heif']
)
on conflict (id) do update set public=false, file_size_limit=5242880;

drop policy if exists one_storage_select on storage.objects;
create policy one_storage_select on storage.objects for select to authenticated
using (
  bucket_id='evolua-one'
  and public.is_workspace_member(((storage.foldername(name))[1])::uuid)
);

drop policy if exists one_storage_insert on storage.objects;
create policy one_storage_insert on storage.objects for insert to authenticated
with check (
  bucket_id='evolua-one'
  and public.can_write_workspace(((storage.foldername(name))[1])::uuid)
);

drop policy if exists one_storage_update on storage.objects;
create policy one_storage_update on storage.objects for update to authenticated
using (
  bucket_id='evolua-one'
  and public.can_write_workspace(((storage.foldername(name))[1])::uuid)
)
with check (
  bucket_id='evolua-one'
  and public.can_write_workspace(((storage.foldername(name))[1])::uuid)
);

drop policy if exists one_storage_delete on storage.objects;
create policy one_storage_delete on storage.objects for delete to authenticated
using (
  bucket_id='evolua-one'
  and public.is_workspace_admin(((storage.foldername(name))[1])::uuid)
);

commit;

-- Resultado esperado: Success. No rows returned
-- Os SELECTs que instalam RLS podem aparecer como resultados intermediários no editor.
