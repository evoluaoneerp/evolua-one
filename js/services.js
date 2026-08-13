import { supabase } from './supabase.js';

function unwrap(result, context = 'operação') {
  if (result.error) {
    const error = new Error(result.error.message || `Falha na ${context}.`);
    error.details = result.error;
    throw error;
  }
  return result.data;
}

export class OneService {
  constructor(client = supabase) {
    this.client = client;
    this.workspaceId = null;
    this.user = null;
    this.membership = null;
  }

  async bootstrap(user) {
    this.user = user;
    const workspaceId = unwrap(
      await this.client.rpc('bootstrap_current_user', { workspace_name: 'Evolua One' }),
      'configuração inicial'
    );
    this.workspaceId = workspaceId;

    const [profile, membership] = await Promise.all([
      this.client.from('profiles').select('*').eq('id', user.id).maybeSingle(),
      this.client.from('workspace_members').select('*').eq('workspace_id', workspaceId).eq('user_id', user.id).maybeSingle()
    ]);

    this.membership = unwrap(membership, 'leitura da permissão');
    return {
      workspaceId,
      profile: unwrap(profile, 'leitura do perfil'),
      membership: this.membership
    };
  }

  scope(query) {
    return query.eq('workspace_id', this.workspaceId);
  }

  async list(table, orderBy = 'created_at', ascending = false) {
    return unwrap(
      await this.scope(this.client.from(table).select('*')).order(orderBy, { ascending }),
      `leitura de ${table}`
    );
  }

  async save(table, payload, id = null) {
    const data = { ...payload, workspace_id: this.workspaceId };
    if (id) {
      return unwrap(
        await this.client.from(table).update(data).eq('id', id).eq('workspace_id', this.workspaceId).select().single(),
        `edição em ${table}`
      );
    }
    return unwrap(await this.client.from(table).insert(data).select().single(), `cadastro em ${table}`);
  }

  async remove(table, id) {
    return unwrap(
      await this.client.from(table).delete().eq('id', id).eq('workspace_id', this.workspaceId),
      `exclusão em ${table}`
    );
  }

  async updateMember(userId, patch) {
    return unwrap(
      await this.client.from('workspace_members').update(patch).eq('workspace_id', this.workspaceId).eq('user_id', userId).select().single(),
      'alteração de usuário'
    );
  }

  async addExistingMember(email, role) {
    return unwrap(
      await this.client.rpc('one_add_existing_user_by_email', {
        target_workspace: this.workspaceId,
        target_email: email,
        target_role: role
      }),
      'vínculo do usuário'
    );
  }

  async listMembers() {
    const memberships = unwrap(
      await this.client.from('workspace_members').select('*').eq('workspace_id', this.workspaceId).order('created_at', { ascending: true }),
      'leitura dos usuários'
    );
    const ids = memberships.map(item => item.user_id);
    if (!ids.length) return [];
    const profiles = unwrap(await this.client.from('profiles').select('*').in('id', ids), 'leitura dos perfis');
    const byId = new Map(profiles.map(profile => [profile.id, profile]));
    return memberships.map(item => ({ ...item, profile: byId.get(item.user_id) || null }));
  }

  async uploadPhoto(file, subjectType, subjectId) {
    if (!file) return null;
    const ext = (file.name.split('.').pop() || 'jpg').toLowerCase().replace(/[^a-z0-9]/g, '') || 'jpg';
    const path = `${this.workspaceId}/${subjectType}/${subjectId}-${Date.now()}.${ext}`;
    unwrap(
      await this.client.storage.from('evolua-one').upload(path, file, { upsert: true, cacheControl: '3600' }),
      'envio da foto'
    );
    return path;
  }

  async signedPhoto(path) {
    if (!path) return null;
    const result = await this.client.storage.from('evolua-one').createSignedUrl(path, 3600);
    return result.error ? null : result.data?.signedUrl || null;
  }

  async enrollmentsExpanded() {
    return unwrap(
      await this.client
        .from('one_enrollments')
        .select(`*,student:one_students(id,full_name,cpf,status),product:one_products(id,name,product_type,list_price,enrollment_fee,max_installments,active),company:one_companies(id,legal_name,trade_name,cnpj)`)
        .eq('workspace_id', this.workspaceId)
        .order('created_at', { ascending: false }),
      'leitura das matrículas'
    );
  }

  async studentGuardianLinks() {
    return unwrap(
      await this.client
        .from('one_student_guardians')
        .select(`*,student:one_students(id,full_name),guardian:one_guardians(id,full_name,cpf,phone,whatsapp,email,active)`)
        .eq('workspace_id', this.workspaceId)
        .order('created_at', { ascending: true }),
      'leitura dos vínculos de responsáveis'
    );
  }

  async contractsExpanded() {
    return unwrap(
      await this.client
        .from('one_contracts')
        .select(`*,student:one_students(id,full_name,cpf),guardian:one_guardians(id,full_name,cpf),company:one_companies(id,legal_name,trade_name,cnpj),product:one_products(id,name,product_type),enrollment:one_enrollments(id,enrollment_number,status,enrollment_date)`)
        .eq('workspace_id', this.workspaceId)
        .order('created_at', { ascending: false }),
      'leitura dos contratos'
    );
  }

  async receivablesExpanded() {
    return unwrap(
      await this.client
        .from('one_receivables')
        .select(`*,student:one_students(id,full_name),guardian:one_guardians(id,full_name),company:one_companies(id,legal_name,trade_name),contract:one_contracts(id,contract_number),enrollment:one_enrollments(id,enrollment_number),category:one_financial_categories(id,name)`)
        .eq('workspace_id', this.workspaceId)
        .order('due_date', { ascending: true }),
      'leitura das contas a receber'
    );
  }

  async payablesExpanded() {
    return unwrap(
      await this.client
        .from('one_payables')
        .select(`*,company:one_companies(id,legal_name,trade_name),category:one_financial_categories(id,name)`)
        .eq('workspace_id', this.workspaceId)
        .order('due_date', { ascending: true }),
      'leitura das contas a pagar'
    );
  }

  async listReceipts() {
    return this.list('one_receipts', 'paid_at', false);
  }

  async listPayablePayments() {
    return this.list('one_payable_payments', 'paid_at', false);
  }

  async generateContractReceivables(contractId) {
    return unwrap(
      await this.client.rpc('one_generate_contract_receivables', { target_contract: contractId }),
      'geração das parcelas'
    );
  }

  async backupData() {
    const tables = [
      'one_students',
      'one_guardians',
      'one_student_guardians',
      'one_companies',
      'one_products',
      'one_product_components',
      'one_enrollments',
      'one_contracts',
      'one_service_history',
      'one_financial_accounts',
      'one_financial_categories',
      'one_receivables',
      'one_receipts',
      'one_payables',
      'one_payable_payments',
      'one_tasks',
      'one_documents',
      'workspace_members'
    ];

    const entries = await Promise.all(
      tables.map(async table => [table, await this.list(table, 'created_at', true)])
    );
    const history = unwrap(
      await this.client.from('one_contract_status_history').select('*').eq('workspace_id', this.workspaceId).order('changed_at', { ascending: true }),
      'backup do histórico contratual'
    );
    return { ...Object.fromEntries(entries), one_contract_status_history: history };
  }
}

export const one = new OneService();
