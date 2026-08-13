-- ============================================================
-- EVOLUA ONE - MIGRAÇÃO V0.3 - ARQUITETURA INTEGRADA
-- Pessoa/Aluno -> Matrícula -> Contrato -> Financeiro
-- Execute APÓS V0.1 e V0.2.
-- Migração incremental: preserva todos os registros existentes.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- MATRÍCULAS COMO ENTIDADE PRÓPRIA
-- ------------------------------------------------------------
do $$ begin
  create type public.one_enrollment_status as enum (
    'pre_matricula','ativa','trancada','cancelada','concluida'
  );
exception when duplicate_object then null; end $$;

create table if not exists public.one_enrollments (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  enrollment_number text not null,
  student_id uuid not null references public.one_students(id) on delete restrict,
  product_id uuid not null references public.one_products(id) on delete restrict,
  company_id uuid references public.one_companies(id) on delete set null,
  status public.one_enrollment_status not null default 'pre_matricula',
  enrollment_date date not null default current_date,
  start_date date,
  end_date date,
  source text not null default 'secretaria',
  notes text,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(workspace_id, enrollment_number)
);

create index if not exists idx_one_enrollments_ws_status
  on public.one_enrollments(workspace_id, status, enrollment_date desc);
create index if not exists idx_one_enrollments_student
  on public.one_enrollments(student_id, created_at desc);
create index if not exists idx_one_enrollments_product
  on public.one_enrollments(product_id, created_at desc);

-- Contrato passa a pertencer à matrícula, sem quebrar os contratos antigos.
alter table public.one_contracts
  add column if not exists enrollment_id uuid references public.one_enrollments(id) on delete restrict;
create index if not exists idx_one_contracts_enrollment on public.one_contracts(enrollment_id);

-- Financeiro passa a saber de qual matrícula nasceu a cobrança.
alter table public.one_receivables
  add column if not exists enrollment_id uuid references public.one_enrollments(id) on delete restrict;
create index if not exists idx_one_receivables_enrollment on public.one_receivables(enrollment_id);

-- Atendimentos podem ser vinculados a uma matrícula específica.
alter table public.one_service_history
  add column if not exists enrollment_id uuid references public.one_enrollments(id) on delete set null;

-- ------------------------------------------------------------
-- MIGRAÇÃO AUTOMÁTICA DOS CONTRATOS JÁ EXISTENTES
-- Cada contrato antigo com aluno + produto ganha uma matrícula.
-- ------------------------------------------------------------
do $$
declare
  c record;
  new_enrollment uuid;
  base_number text;
begin
  for c in
    select c.*
      from public.one_contracts c
     where c.enrollment_id is null
       and c.student_id is not null
       and c.product_id is not null
  loop
    base_number := 'MIG-' || regexp_replace(coalesce(c.contract_number, c.id::text), '[^A-Za-z0-9_-]', '', 'g');

    select e.id into new_enrollment
      from public.one_enrollments e
     where e.workspace_id = c.workspace_id
       and e.enrollment_number = base_number
     limit 1;

    if new_enrollment is null then
      insert into public.one_enrollments (
        workspace_id, enrollment_number, student_id, product_id, company_id,
        status, enrollment_date, start_date, end_date, source, notes, created_by, created_at, updated_at
      ) values (
        c.workspace_id,
        base_number,
        c.student_id,
        c.product_id,
        c.company_id,
        case c.status
          when 'ativo' then 'ativa'::public.one_enrollment_status
          when 'trancado' then 'trancada'::public.one_enrollment_status
          when 'cancelado' then 'cancelada'::public.one_enrollment_status
          when 'concluido' then 'concluida'::public.one_enrollment_status
          else 'pre_matricula'::public.one_enrollment_status
        end,
        coalesce(c.contract_date, current_date),
        c.start_date,
        c.end_date,
        'migracao_v03',
        'Matrícula criada automaticamente a partir do contrato ' || coalesce(c.contract_number, ''),
        c.created_by,
        c.created_at,
        c.updated_at
      ) returning id into new_enrollment;
    end if;

    update public.one_contracts
       set enrollment_id = new_enrollment
     where id = c.id;
  end loop;
end $$;

update public.one_receivables r
   set enrollment_id = c.enrollment_id
  from public.one_contracts c
 where r.contract_id = c.id
   and r.enrollment_id is null
   and c.enrollment_id is not null;

-- ------------------------------------------------------------
-- COERÊNCIA: AO ESCOLHER MATRÍCULA, CONTRATO HERDA ALUNO/PRODUTO/EMPRESA
-- ------------------------------------------------------------
create or replace function public.one_sync_contract_from_enrollment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  e public.one_enrollments%rowtype;
begin
  if new.enrollment_id is null then
    return new;
  end if;

  select * into e from public.one_enrollments where id = new.enrollment_id;
  if e.id is null then
    raise exception 'Matrícula não encontrada.';
  end if;
  if e.workspace_id is distinct from new.workspace_id then
    raise exception 'A matrícula pertence a outro espaço de trabalho.';
  end if;

  new.student_id := e.student_id;
  new.product_id := e.product_id;
  new.company_id := coalesce(new.company_id, e.company_id);
  new.start_date := coalesce(new.start_date, e.start_date);
  new.end_date := coalesce(new.end_date, e.end_date);
  return new;
end;
$$;

drop trigger if exists trg_one_contract_sync_enrollment_insert on public.one_contracts;
create trigger trg_one_contract_sync_enrollment_insert
before insert on public.one_contracts
for each row execute function public.one_sync_contract_from_enrollment();

drop trigger if exists trg_one_contract_sync_enrollment_update on public.one_contracts;
create trigger trg_one_contract_sync_enrollment_update
before update of enrollment_id on public.one_contracts
for each row execute function public.one_sync_contract_from_enrollment();

-- ------------------------------------------------------------
-- PARCELAS GERADAS PELO CONTRATO HERDAM A MATRÍCULA
-- ------------------------------------------------------------
create or replace function public.one_generate_contract_receivables(target_contract uuid)
returns integer
language plpgsql
security definer
set search_path=public,private
as $$
declare
  c public.one_contracts%rowtype;
  base_date date;
  n integer;
  amount_value numeric(14,2);
  created_count integer:=0;
begin
  select * into c from public.one_contracts where id=target_contract;
  if c.id is null then raise exception 'Contrato não encontrado.'; end if;
  if not private.can_write_workspace(c.workspace_id) then raise exception 'Sem permissão.'; end if;

  base_date:=coalesce(c.first_due_date,c.start_date,c.contract_date,current_date);

  if c.enrollment_fee>0 then
    insert into public.one_receivables(
      workspace_id,contract_id,enrollment_id,student_id,guardian_id,company_id,
      entry_kind,description,installment_number,installment_total,due_date,original_amount
    ) values(
      c.workspace_id,c.id,c.enrollment_id,c.student_id,c.guardian_id,c.company_id,
      'matricula','Taxa de matrícula',0,c.installments,base_date,c.enrollment_fee
    ) on conflict do nothing;
    if found then created_count:=created_count+1; end if;
  end if;

  amount_value:=case
    when c.installment_value>0 then c.installment_value
    when c.installments>0 then round(c.contract_value/c.installments,2)
    else c.contract_value
  end;

  for n in 1..greatest(c.installments,1) loop
    insert into public.one_receivables(
      workspace_id,contract_id,enrollment_id,student_id,guardian_id,company_id,
      entry_kind,description,installment_number,installment_total,due_date,original_amount
    ) values(
      c.workspace_id,c.id,c.enrollment_id,c.student_id,c.guardian_id,c.company_id,
      'parcela',format('Parcela %s/%s - Contrato %s',n,c.installments,c.contract_number),
      n,c.installments,(base_date+make_interval(months=>n-1))::date,amount_value
    ) on conflict do nothing;
    if found then created_count:=created_count+1; end if;
  end loop;

  return created_count;
end;
$$;

revoke all on function public.one_generate_contract_receivables(uuid) from public,anon;
grant execute on function public.one_generate_contract_receivables(uuid) to authenticated;

-- ------------------------------------------------------------
-- STATUS DA MATRÍCULA PODE ACOMPANHAR O CONTRATO ATIVO/TRANCADO/CANCELADO/CONCLUÍDO
-- ------------------------------------------------------------
create or replace function public.one_sync_enrollment_status_from_contract()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if new.enrollment_id is null then return new; end if;

  if new.status = 'ativo' then
    update public.one_enrollments set status='ativa', updated_at=now() where id=new.enrollment_id;
  elsif new.status = 'trancado' then
    update public.one_enrollments set status='trancada', updated_at=now() where id=new.enrollment_id;
  elsif new.status = 'cancelado' then
    update public.one_enrollments set status='cancelada', updated_at=now() where id=new.enrollment_id;
  elsif new.status = 'concluido' then
    update public.one_enrollments set status='concluida', updated_at=now() where id=new.enrollment_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_one_contract_sync_enrollment_status_insert on public.one_contracts;
create trigger trg_one_contract_sync_enrollment_status_insert
after insert on public.one_contracts
for each row execute function public.one_sync_enrollment_status_from_contract();

drop trigger if exists trg_one_contract_sync_enrollment_status_update on public.one_contracts;
create trigger trg_one_contract_sync_enrollment_status_update
after update of status on public.one_contracts
for each row execute function public.one_sync_enrollment_status_from_contract();

-- ------------------------------------------------------------
-- RLS, UPDATED_AT E AUDITORIA DA NOVA ENTIDADE
-- ------------------------------------------------------------
drop trigger if exists trg_one_enrollments_updated_at on public.one_enrollments;
create trigger trg_one_enrollments_updated_at
before update on public.one_enrollments
for each row execute function public.set_updated_at();

drop trigger if exists trg_one_enrollments_audit on public.one_enrollments;
create trigger trg_one_enrollments_audit
after insert or update or delete on public.one_enrollments
for each row execute function public.one_write_audit();

alter table public.one_enrollments enable row level security;
drop policy if exists one_select on public.one_enrollments;
create policy one_select on public.one_enrollments
for select to authenticated using (private.is_workspace_member(workspace_id));
drop policy if exists one_insert on public.one_enrollments;
create policy one_insert on public.one_enrollments
for insert to authenticated with check (private.can_write_workspace(workspace_id));
drop policy if exists one_update on public.one_enrollments;
create policy one_update on public.one_enrollments
for update to authenticated using (private.can_write_workspace(workspace_id)) with check (private.can_write_workspace(workspace_id));
drop policy if exists one_delete on public.one_enrollments;
create policy one_delete on public.one_enrollments
for delete to authenticated using (private.is_workspace_admin(workspace_id));

commit;
-- Resultado esperado: Success. No rows returned
