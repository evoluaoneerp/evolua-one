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
    return unwrap(
      await this.client.from(table).insert(data).select().single(),
      `cadastro em ${table}`
    );
  }

  async remove(table, id) {
    return unwrap(
      await this.client.from(table).delete().eq('id', id).eq('workspace_id', this.workspaceId),
      `exclusão em ${table}`
    );
  }

  async updateMember(userId, patch) {
    return unwrap(
      await this.client.from('workspace_members')
        .update(patch)
        .eq('workspace_id', this.workspaceId)
        .eq('user_id', userId)
        .select()
        .single(),
      'alteração de usuário'
    );
  }

  async listMembers() {
    const memberships = unwrap(
      await this.client.from('workspace_members')
        .select('*')
        .eq('workspace_id', this.workspaceId)
        .order('created_at', { ascending: true }),
      'leitura dos usuários'
    );
    const ids = memberships.map(item => item.user_id);
    if (!ids.length) return [];
    const profiles = unwrap(
      await this.client.from('profiles').select('*').in('id', ids),
      'leitura dos perfis'
    );
    const byId = new Map(profiles.map(profile => [profile.id, profile]));
    return memberships.map(member => ({ ...member, profile: byId.get(member.user_id) || null }));
  }

  async uploadPhoto(file, subjectType, subjectId) {
    if (!file) return null;
    const extension = (file.name.split('.').pop() || 'jpg').toLowerCase().replace(/[^a-z0-9]/g, '') || 'jpg';
    const path = `${this.workspaceId}/${subjectType}/${subjectId}-${Date.now()}.${extension}`;
    unwrap(
      await this.client.storage.from('evolua-one').upload(path, file, { upsert: true, cacheControl: '3600' }),
      'envio da foto'
    );
    return path;
  }

  async signedPhoto(path) {
    if (!path) return null;
    const result = await this.client.storage.from('evolua-one').createSignedUrl(path, 3600);
    if (result.error) return null;
    return result.data?.signedUrl || null;
  }

  async contractsExpanded() {
    return unwrap(
      await this.client.from('one_contracts').select(`
        *,
        student:one_students(id, full_name, cpf),
        guardian:one_guardians(id, full_name, cpf),
        company:one_companies(id, legal_name, trade_name, cnpj),
        product:one_products(id, name, product_type)
      `).eq('workspace_id', this.workspaceId).order('created_at', { ascending: false }),
      'leitura dos contratos'
    );
  }
}

export const one = new OneService();
