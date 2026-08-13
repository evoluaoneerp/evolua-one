-- ============================================================
-- EVOLUA ONE - MIGRAÇÃO V0.2
-- Financeiro, agenda, documentos, relatórios e backup.
-- Execute APÓS a fundação V0.1 já aplicada com sucesso.
-- Migração incremental: não apaga dados existentes.
-- ============================================================

begin;

do $$ begin create type public.one_receivable_status as enum ('aberto','parcial','pago','renegociado','cancelado','estornado'); exception when duplicate_object then null; end $$;
do $$ begin create type public.one_payable_status as enum ('aberto','parcial','pago','cancelado'); exception when duplicate_object then null; end $$;
do $$ begin create type public.one_task_status as enum ('pendente','em_andamento','concluida','cancelada'); exception when duplicate_object then null; end $$;
do $$ begin create type public.one_task_priority as enum ('baixa','normal','alta','urgente'); exception when duplicate_object then null; end $$;

alter table public.one_contracts add column if not exists first_due_date date;

create table if not exists public.one_financial_accounts (
  id uuid primary key default gen_random_uuid(), workspace_id uuid not null references public.workspaces(id) on delete cascade,
  name text not null, account_type text not null default 'banco', opening_balance numeric(14,2) not null default 0,
  active boolean not null default true, notes text, created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(workspace_id,name)
);

create table if not exists public.one_financial_categories (
  id uuid primary key default gen_random_uuid(), workspace_id uuid not null references public.workspaces(id) on delete cascade,
  name text not null, kind text not null default 'despesa' check(kind in ('receita','despesa','ambos')), cost_center text,
  active boolean not null default true, created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(workspace_id,name,kind)
);

create table if not exists public.one_receivables (
  id uuid primary key default gen_random_uuid(), workspace_id uuid not null references public.workspaces(id) on delete cascade,
  contract_id uuid references public.one_contracts(id) on delete restrict, student_id uuid references public.one_students(id) on delete restrict,
  guardian_id uuid references public.one_guardians(id) on delete restrict, company_id uuid references public.one_companies(id) on delete restrict,
  category_id uuid references public.one_financial_categories(id) on delete set null,
  entry_kind text not null default 'avulso' check(entry_kind in ('matricula','parcela','avulso','renegociacao')),
  description text not null, installment_number integer, installment_total integer, due_date date not null,
  original_amount numeric(14,2) not null default 0 check(original_amount>=0), discount_amount numeric(14,2) not null default 0 check(discount_amount>=0),
  fine_amount numeric(14,2) not null default 0 check(fine_amount>=0), interest_amount numeric(14,2) not null default 0 check(interest_amount>=0),
  status public.one_receivable_status not null default 'aberto', notes text,
  created_by uuid not null default auth.uid() references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists idx_one_receivables_ws_due on public.one_receivables(workspace_id,due_date,status);
create index if not exists idx_one_receivables_contract on public.one_receivables(contract_id);
create unique index if not exists idx_one_receivables_contract_generated on public.one_receivables(contract_id,entry_kind,coalesce(installment_number,0)) where contract_id is not null and entry_kind in ('matricula','parcela');

create table if not exists public.one_receipts (
  id uuid primary key default gen_random_uuid(), workspace_id uuid not null references public.workspaces(id) on delete cascade,
  receivable_id uuid not null references public.one_receivables(id) on delete restrict, account_id uuid references public.one_financial_accounts(id) on delete set null,
  amount numeric(14,2) not null check(amount>0), paid_at timestamptz not null default now(), payment_method text, notes text,
  reversed boolean not null default false, reversed_at timestamptz, reversed_reason text,
  created_by uuid not null default auth.uid() references auth.users(id), created_at timestamptz not null default now()
);
create index if not exists idx_one_receipts_ws_date on public.one_receipts(workspace_id,paid_at desc);
create index if not exists idx_one_receipts_receivable on public.one_receipts(receivable_id);

create table if not exists public.one_payables (
  id uuid primary key default gen_random_uuid(), workspace_id uuid not null references public.workspaces(id) on delete cascade,
  company_id uuid references public.one_companies(id) on delete set null, category_id uuid references public.one_financial_categories(id) on delete set null,
  supplier_name text, description text not null, cost_center text, due_date date not null,
  original_amount numeric(14,2) not null default 0 check(original_amount>=0), status public.one_payable_status not null default 'aberto',
  recurring_rule text, notes text, created_by uuid not null default auth.uid() references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists idx_one_payables_ws_due on public.one_payables(workspace_id,due_date,status);

create table if not exists public.one_payable_payments (
  id uuid primary key default gen_random_uuid(), workspace_id uuid not null references public.workspaces(id) on delete cascade,
  payable_id uuid not null references public.one_payables(id) on delete restrict, account_id uuid references public.one_financial_accounts(id) on delete set null,
  amount numeric(14,2) not null check(amount>0), paid_at timestamptz not null default now(), payment_method text, notes text,
  reversed boolean not null default false, reversed_at timestamptz, reversed_reason text,
  created_by uuid not null default auth.uid() references auth.users(id), created_at timestamptz not null default now()
);
create index if not exists idx_one_payable_payments_ws_date on public.one_payable_payments(workspace_id,paid_at desc);

create table if not exists public.one_tasks (
  id uuid primary key default gen_random_uuid(), workspace_id uuid not null references public.workspaces(id) on delete cascade,
  title text not null, description text, due_at timestamptz not null, priority public.one_task_priority not null default 'normal',
  status public.one_task_status not null default 'pendente', category text, assigned_to uuid references auth.users(id) on delete set null,
  entity_type text, entity_id uuid, reminder_minutes integer check(reminder_minutes is null or reminder_minutes>=0), recurring_rule text,
  completed_at timestamptz, created_by uuid not null default auth.uid() references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists idx_one_tasks_ws_due on public.one_tasks(workspace_id,status,due_at);
create index if not exists idx_one_tasks_assigned on public.one_tasks(assigned_to,status,due_at);

create table if not exists public.one_documents (
  id uuid primary key default gen_random_uuid(), workspace_id uuid not null references public.workspaces(id) on delete cascade,
  title text not null, document_type text, entity_type text, entity_id uuid, drive_url text, storage_path text, notes text,
  created_by uuid not null default auth.uid() references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists idx_one_documents_ws_entity on public.one_documents(workspace_id,entity_type,entity_id);

create table if not exists public.one_backup_log (
  id uuid primary key default gen_random_uuid(), workspace_id uuid not null references public.workspaces(id) on delete cascade,
  file_name text not null, destination text not null default 'local', record_count integer not null default 0, app_version text,
  created_by uuid not null default auth.uid() references auth.users(id), created_at timestamptz not null default now()
);

create or replace function public.one_add_existing_user_by_email(target_workspace uuid,target_email text,target_role public.app_role default 'viewer') returns uuid
language plpgsql security definer set search_path=public,auth,private as $$
declare target_user uuid;
begin
  if not private.is_workspace_admin(target_workspace) then raise exception 'Sem permissão para gerenciar usuários.'; end if;
  select id into target_user from auth.users where lower(email)=lower(btrim(target_email)) limit 1;
  if target_user is null then raise exception 'Usuário não encontrado no Authentication. Crie o usuário no Supabase Auth primeiro.'; end if;
  insert into public.profiles(id,full_name,email)
  select id,coalesce(raw_user_meta_data->>'full_name',split_part(email,'@',1)),email from auth.users where id=target_user
  on conflict(id) do update set email=excluded.email;
  insert into public.workspace_members(workspace_id,user_id,role,active) values(target_workspace,target_user,target_role,true)
  on conflict(workspace_id,user_id) do update set role=excluded.role,active=true,updated_at=now();
  return target_user;
end;$$;
revoke all on function public.one_add_existing_user_by_email(uuid,text,public.app_role) from public,anon;
grant execute on function public.one_add_existing_user_by_email(uuid,text,public.app_role) to authenticated;

create or replace function public.one_generate_contract_receivables(target_contract uuid) returns integer
language plpgsql security definer set search_path=public,private as $$
declare c public.one_contracts%rowtype; base_date date; n integer; amount_value numeric(14,2); created_count integer:=0;
begin
  select * into c from public.one_contracts where id=target_contract;
  if c.id is null then raise exception 'Contrato não encontrado.'; end if;
  if not private.can_write_workspace(c.workspace_id) then raise exception 'Sem permissão.'; end if;
  base_date:=coalesce(c.first_due_date,c.start_date,c.contract_date,current_date);
  if c.enrollment_fee>0 then
    insert into public.one_receivables(workspace_id,contract_id,student_id,guardian_id,company_id,entry_kind,description,installment_number,installment_total,due_date,original_amount)
    values(c.workspace_id,c.id,c.student_id,c.guardian_id,c.company_id,'matricula','Taxa de matrícula',0,c.installments,base_date,c.enrollment_fee) on conflict do nothing;
    if found then created_count:=created_count+1; end if;
  end if;
  amount_value:=case when c.installment_value>0 then c.installment_value when c.installments>0 then round(c.contract_value/c.installments,2) else c.contract_value end;
  for n in 1..greatest(c.installments,1) loop
    insert into public.one_receivables(workspace_id,contract_id,student_id,guardian_id,company_id,entry_kind,description,installment_number,installment_total,due_date,original_amount)
    values(c.workspace_id,c.id,c.student_id,c.guardian_id,c.company_id,'parcela',format('Parcela %s/%s - Contrato %s',n,c.installments,c.contract_number),n,c.installments,(base_date+make_interval(months=>n-1))::date,amount_value) on conflict do nothing;
    if found then created_count:=created_count+1; end if;
  end loop;
  return created_count;
end;$$;
revoke all on function public.one_generate_contract_receivables(uuid) from public,anon;
grant execute on function public.one_generate_contract_receivables(uuid) to authenticated;

create or replace function public.one_refresh_receivable_status() returns trigger language plpgsql security definer set search_path=public as $$
declare rid uuid; paid numeric(14,2); due numeric(14,2); current_status public.one_receivable_status;
begin
  rid:=case when tg_op='DELETE' then old.receivable_id else new.receivable_id end;
  select (original_amount-discount_amount+fine_amount+interest_amount),status into due,current_status from public.one_receivables where id=rid;
  if current_status in ('cancelado','renegociado','estornado') then return coalesce(new,old); end if;
  select coalesce(sum(amount),0) into paid from public.one_receipts where receivable_id=rid and reversed=false;
  update public.one_receivables set status=case when paid<=0 then 'aberto'::public.one_receivable_status when paid+0.005>=due then 'pago'::public.one_receivable_status else 'parcial'::public.one_receivable_status end,updated_at=now() where id=rid;
  return coalesce(new,old);
end;$$;
drop trigger if exists trg_one_receipts_refresh on public.one_receipts;
create trigger trg_one_receipts_refresh after insert or update or delete on public.one_receipts for each row execute function public.one_refresh_receivable_status();

create or replace function public.one_refresh_payable_status() returns trigger language plpgsql security definer set search_path=public as $$
declare pid uuid; paid numeric(14,2); due numeric(14,2); current_status public.one_payable_status;
begin
  pid:=case when tg_op='DELETE' then old.payable_id else new.payable_id end;
  select original_amount,status into due,current_status from public.one_payables where id=pid;
  if current_status='cancelado' then return coalesce(new,old); end if;
  select coalesce(sum(amount),0) into paid from public.one_payable_payments where payable_id=pid and reversed=false;
  update public.one_payables set status=case when paid<=0 then 'aberto'::public.one_payable_status when paid+0.005>=due then 'pago'::public.one_payable_status else 'parcial'::public.one_payable_status end,updated_at=now() where id=pid;
  return coalesce(new,old);
end;$$;
drop trigger if exists trg_one_payable_payments_refresh on public.one_payable_payments;
create trigger trg_one_payable_payments_refresh after insert or update or delete on public.one_payable_payments for each row execute function public.one_refresh_payable_status();

do $$ declare t text; begin
  foreach t in array array['one_financial_accounts','one_financial_categories','one_receivables','one_payables','one_tasks','one_documents'] loop
    execute format('drop trigger if exists trg_%I_updated_at on public.%I',t,t);
    execute format('create trigger trg_%I_updated_at before update on public.%I for each row execute function public.set_updated_at()',t,t);
  end loop;
end $$;

do $$ declare t text; begin
  foreach t in array array['one_financial_accounts','one_financial_categories','one_receivables','one_receipts','one_payables','one_payable_payments','one_tasks','one_documents','one_backup_log'] loop
    execute format('drop trigger if exists trg_%I_audit on public.%I',t,t);
    execute format('create trigger trg_%I_audit after insert or update or delete on public.%I for each row execute function public.one_write_audit()',t,t);
    execute format('alter table public.%I enable row level security',t);
    execute format('drop policy if exists one_select on public.%I',t);
    execute format('create policy one_select on public.%I for select to authenticated using (private.is_workspace_member(workspace_id))',t);
    execute format('drop policy if exists one_insert on public.%I',t);
    execute format('create policy one_insert on public.%I for insert to authenticated with check (private.can_write_workspace(workspace_id))',t);
    execute format('drop policy if exists one_update on public.%I',t);
    execute format('create policy one_update on public.%I for update to authenticated using (private.can_write_workspace(workspace_id)) with check (private.can_write_workspace(workspace_id))',t);
    execute format('drop policy if exists one_delete on public.%I',t);
    execute format('create policy one_delete on public.%I for delete to authenticated using (private.is_workspace_admin(workspace_id))',t);
  end loop;
end $$;

update storage.buckets set allowed_mime_types=array['image/jpeg','image/png','image/webp','image/heic','image/heif','application/pdf','text/plain','text/csv','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'] where id='evolua-one';

commit;
-- Resultado esperado: Success. No rows returned
