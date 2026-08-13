import { supabase } from './supabase.js';
import { one } from './services.js';
import { DesktopManager } from './desktop.js';
import { APP_NAME, CRM_URL, VERSION } from './config.js';

const $ = selector => document.querySelector(selector);
const $$ = selector => [...document.querySelectorAll(selector)];
const state = {
  user: null,
  profile: null,
  role: null,
  workspaceId: null,
  students: [], guardians: [], companies: [], products: [], contracts: [], members: [],
  editing: { students: null, guardians: null, companies: null, products: null, contracts: null },
  desktop: null
};

const roleLabels = { owner: 'Proprietário', admin: 'Administrador', seller: 'Comercial', viewer: 'Consulta' };
const statusLabels = { ativo: 'Ativo', inativo: 'Inativo', trancado: 'Trancado', cancelado: 'Cancelado', concluido: 'Concluído' };
const productTypes = { curso: 'Curso avulso', pacote: 'Pacote', plano: 'Plano / assinatura', servico: 'Serviço' };
const contractStatus = { rascunho:'Rascunho', aguardando_assinatura:'Aguardando assinatura', ativo:'Ativo', trancado:'Trancado', cancelado:'Cancelado', concluido:'Concluído', substituido:'Substituído' };

function toast(message, type = 'success') {
  const node = document.createElement('div');
  node.className = `toast ${type}`;
  node.textContent = message;
  $('#toast-container').appendChild(node);
  setTimeout(() => node.remove(), 4200);
}

function escapeHTML(value = '') {
  return String(value).replace(/[&<>'"]/g, char => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', "'":'&#39;', '"':'&quot;' }[char]));
}
function digits(value = '') { return String(value).replace(/\D/g, ''); }
function formatCPF(value = '') {
  const v = digits(value).slice(0,11);
  return v.replace(/(\d{3})(\d)/, '$1.$2').replace(/(\d{3})(\d)/, '$1.$2').replace(/(\d{3})(\d{1,2})$/, '$1-$2');
}
function formatCNPJ(value = '') {
  const v = digits(value).slice(0,14);
  return v.replace(/(\d{2})(\d)/, '$1.$2').replace(/(\d{3})(\d)/, '$1.$2').replace(/(\d{3})(\d)/, '$1/$2').replace(/(\d{4})(\d{1,2})$/, '$1-$2');
}
function formatCEP(value = '') { const v = digits(value).slice(0,8); return v.replace(/(\d{5})(\d)/, '$1-$2'); }
function formatPhone(value = '') {
  const v = digits(value).slice(0,11);
  if (v.length <= 10) return v.replace(/(\d{2})(\d)/, '($1) $2').replace(/(\d{4})(\d)/, '$1-$2');
  return v.replace(/(\d{2})(\d)/, '($1) $2').replace(/(\d{5})(\d)/, '$1-$2');
}
function money(value) { return Number(value || 0).toLocaleString('pt-BR', { style:'currency', currency:'BRL' }); }
function fmtDate(value) { if (!value) return '—'; return new Date(`${value}T12:00:00`).toLocaleDateString('pt-BR'); }
function isAdmin() { return ['owner','admin'].includes(state.role); }

function validCPF(value) {
  const cpf = digits(value);
  if (cpf.length !== 11 || /^(\d)\1{10}$/.test(cpf)) return false;
  let sum = 0;
  for (let i=0;i<9;i++) sum += Number(cpf[i]) * (10-i);
  let d1 = (sum * 10) % 11; if (d1 === 10) d1 = 0;
  if (d1 !== Number(cpf[9])) return false;
  sum = 0;
  for (let i=0;i<10;i++) sum += Number(cpf[i]) * (11-i);
  let d2 = (sum * 10) % 11; if (d2 === 10) d2 = 0;
  return d2 === Number(cpf[10]);
}
function validCNPJ(value) {
  const cnpj = digits(value);
  if (cnpj.length !== 14 || /^(\d)\1{13}$/.test(cnpj)) return false;
  const calc = len => {
    let size = len - 7, sum = 0;
    for (let i=0;i<len;i++) { sum += Number(cnpj[i]) * size--; if (size < 2) size = 9; }
    const result = sum % 11; return result < 2 ? 0 : 11 - result;
  };
  return calc(12) === Number(cnpj[12]) && calc(13) === Number(cnpj[13]);
}

async function fetchCEP(input, cityTarget, stateTarget) {
  const cep = digits(input.value);
  if (cep.length !== 8) return;
  try {
    const response = await fetch(`https://viacep.com.br/ws/${cep}/json/`);
    if (!response.ok) throw new Error('CEP indisponível');
    const data = await response.json();
    if (data.erro) throw new Error('CEP não encontrado');
    $(cityTarget).value = data.localidade || '';
    $(stateTarget).value = data.uf || '';
    toast(`Cidade localizada: ${data.localidade || ''}/${data.uf || ''}`);
  } catch (error) {
    toast('Não consegui localizar esse CEP agora. Preencha cidade e estado manualmente.', 'warning');
  }
}

function showLogin() {
  $('#login-view').classList.remove('hidden');
  $('#desktop-view').classList.add('hidden');
}
function showDesktop() {
  $('#login-view').classList.add('hidden');
  $('#desktop-view').classList.remove('hidden');
}

async function enterApp(user) {
  state.user = user;
  try {
    const boot = await one.bootstrap(user);
    state.workspaceId = boot.workspaceId;
    state.profile = boot.profile;
    state.role = boot.membership?.role || 'viewer';
    $('#top-user-name').textContent = state.profile?.full_name || user.email?.split('@')[0] || 'Usuário';
    $('#top-user-role').textContent = roleLabels[state.role] || state.role;
    $('#version-label').textContent = `v${VERSION}`;
    showDesktop();
    await refreshAll();
  } catch (error) {
    console.error(error);
    toast(`Falha ao abrir o Evolua One: ${error.message}`, 'error');
  }
}

async function refreshAll() {
  const [students, guardians, companies, products, contracts, members] = await Promise.all([
    one.list('one_students', 'full_name', true),
    one.list('one_guardians', 'full_name', true),
    one.list('one_companies', 'legal_name', true),
    one.list('one_products', 'name', true),
    one.contractsExpanded(),
    one.listMembers()
  ]);
  const hydrate = async items => Promise.all(items.map(async item => ({ ...item, photo_url: item.photo_path ? await one.signedPhoto(item.photo_path) : null })));
  const [studentsWithPhotos, guardiansWithPhotos, companiesWithPhotos] = await Promise.all([hydrate(students), hydrate(guardians), hydrate(companies)]);
  Object.assign(state, { students: studentsWithPhotos, guardians: guardiansWithPhotos, companies: companiesWithPhotos, products, contracts, members });
  renderEverything();
}

function renderEverything() {
  renderHome(); renderStudents(); renderGuardians(); renderCompanies(); renderProducts(); renderContracts(); renderMembers(); updateSelects();
  if (!state.editing.contracts && $('#contract-number')) $('#contract-number').value = nextContractNumber();
}

function upcomingBirthdays() {
  const today = new Date(); today.setHours(0,0,0,0);
  const items = [
    ...state.students.filter(x => x.birth_date).map(x => ({ type:'Aluno', name:x.full_name, date:x.birth_date })),
    ...state.guardians.filter(x => x.birth_date).map(x => ({ type:'Responsável', name:x.full_name, date:x.birth_date }))
  ];
  return items.map(item => {
    const [y,m,d] = item.date.split('-').map(Number);
    let next = new Date(today.getFullYear(), m-1, d);
    if (next < today) next = new Date(today.getFullYear()+1, m-1, d);
    return { ...item, next, days: Math.round((next-today)/86400000), age: today.getFullYear()-y + (next.getFullYear()>today.getFullYear() ? -1 : 0) };
  }).filter(item => item.days <= 30).sort((a,b) => a.days-b.days);
}

function renderHome() {
  const birthdays = upcomingBirthdays();
  const today = birthdays.filter(item => item.days === 0);
  $('#home-kpis').innerHTML = [
    ['👨‍🎓','Alunos', state.students.filter(x=>x.status==='ativo').length, `${state.students.length} cadastrados`],
    ['👨‍👩‍👧','Responsáveis', state.guardians.length, 'cadastros vinculáveis'],
    ['🏢','Empresas', state.companies.filter(x=>x.active).length, `${state.companies.length} cadastradas`],
    ['📄','Contratos ativos', state.contracts.filter(x=>x.status==='ativo').length, `${state.contracts.length} contratos`],
    ['🎂','Aniversários hoje', today.length, birthdays.length ? `${birthdays.length} nos próximos 30 dias` : 'nenhum próximo']
  ].map(([icon,label,value,sub]) => `<article class="home-kpi"><span>${icon}</span><div><small>${label}</small><strong>${value}</strong><em>${sub}</em></div></article>`).join('');

  $('#birthday-list').innerHTML = birthdays.length ? birthdays.slice(0,8).map(item => `<div class="birthday-row"><span class="birthday-icon">🎂</span><div><strong>${escapeHTML(item.name)}</strong><small>${item.type} • ${item.days===0?'Hoje':item.days===1?'Amanhã':`em ${item.days} dias`}</small></div></div>`).join('') : '<div class="empty-state">Nenhum aniversário nos próximos 30 dias.</div>';
  $('#notification-count').textContent = String(today.length);
  $('#notification-count').classList.toggle('hidden', today.length === 0);
}

function entityTable({ rows, columns, table, empty = 'Nenhum cadastro encontrado.' }) {
  if (!rows.length) return `<div class="empty-state">${empty}</div>`;
  return `<div class="data-table-wrap"><table class="data-table"><thead><tr>${columns.map(c=>`<th>${c.label}</th>`).join('')}<th>Ações</th></tr></thead><tbody>${rows.map(row => `<tr>${columns.map(c=>`<td>${c.render ? c.render(row) : escapeHTML(row[c.key] ?? '—')}</td>`).join('')}<td class="row-actions"><button class="mini-btn" data-edit-${table}="${row.id}">Editar</button><button class="mini-btn danger" data-delete-${table}="${row.id}">Excluir</button></td></tr>`).join('')}</tbody></table></div>`;
}

function renderStudents() {
  $('#students-list').innerHTML = entityTable({ table:'students', rows:state.students, columns:[
    { label:'Aluno', render:r=>`<div class="entity-cell">${r.photo_url?`<img src="${escapeHTML(r.photo_url)}" alt="">`:'<span class="entity-avatar">👨‍🎓</span>'}<div><strong>${escapeHTML(r.full_name)}</strong><small>${escapeHTML(r.email||r.whatsapp||'Sem contato')}</small></div></div>` },
    { label:'CPF', render:r=>escapeHTML(formatCPF(r.cpf||'')) || '—' },
    { label:'Cidade', render:r=>escapeHTML([r.city,r.state].filter(Boolean).join('/')) || '—' },
    { label:'Status', render:r=>`<span class="status-pill ${r.status}">${statusLabels[r.status]||r.status}</span>` }
  ]});
  bindEntityActions('students');
}
function renderGuardians() {
  $('#guardians-list').innerHTML = entityTable({ table:'guardians', rows:state.guardians, columns:[
    { label:'Responsável', render:r=>`<div class="entity-cell">${r.photo_url?`<img src="${escapeHTML(r.photo_url)}" alt="">`:'<span class="entity-avatar">👨‍👩‍👧</span>'}<div><strong>${escapeHTML(r.full_name)}</strong><small>${escapeHTML(r.email||r.whatsapp||'Sem contato')}</small></div></div>` },
    { label:'CPF', render:r=>escapeHTML(formatCPF(r.cpf||'')) || '—' },
    { label:'Cidade', render:r=>escapeHTML([r.city,r.state].filter(Boolean).join('/')) || '—' },
    { label:'Status', render:r=>`<span class="status-pill ${r.active?'ativo':'inativo'}">${r.active?'Ativo':'Inativo'}</span>` }
  ]});
  bindEntityActions('guardians');
}
function renderCompanies() {
  $('#companies-list').innerHTML = entityTable({ table:'companies', rows:state.companies, columns:[
    { label:'Empresa', render:r=>`<div class="entity-cell">${r.photo_url?`<img src="${escapeHTML(r.photo_url)}" alt="">`:'<span class="entity-avatar">🏢</span>'}<div><strong>${escapeHTML(r.trade_name||r.legal_name)}</strong><small>${escapeHTML(r.legal_name)}</small></div></div>` },
    { label:'CNPJ', render:r=>escapeHTML(formatCNPJ(r.cnpj||'')) || '—' },
    { label:'Contato', render:r=>escapeHTML(r.whatsapp||r.phone||r.email||'—') },
    { label:'Status', render:r=>`<span class="status-pill ${r.active?'ativo':'inativo'}">${r.active?'Ativa':'Inativa'}</span>` }
  ]});
  bindEntityActions('companies');
}
function renderProducts() {
  $('#products-list').innerHTML = entityTable({ table:'products', rows:state.products, columns:[
    { label:'Produto', render:r=>`<div><strong>${escapeHTML(r.name)}</strong><small class="block">${productTypes[r.product_type]||r.product_type}</small></div>` },
    { label:'Categoria', key:'category' },
    { label:'Modalidade', key:'modality' },
    { label:'Valor padrão', render:r=>money(r.list_price) },
    { label:'Status', render:r=>`<span class="status-pill ${r.active?'ativo':'inativo'}">${r.active?'Ativo':'Inativo'}</span>` }
  ]});
  bindEntityActions('products');
}
function renderContracts() {
  $('#contracts-list').innerHTML = entityTable({ table:'contracts', rows:state.contracts, columns:[
    { label:'Contrato', render:r=>`<div><strong>${escapeHTML(r.contract_number)}</strong><small class="block">${fmtDate(r.contract_date)}</small></div>` },
    { label:'Contratado', render:r=>escapeHTML(r.student?.full_name || r.company?.trade_name || r.company?.legal_name || '—') },
    { label:'Produto', render:r=>escapeHTML(r.product?.name || '—') },
    { label:'Valor', render:r=>money(r.contract_value) },
    { label:'Status', render:r=>`<span class="status-pill ${r.status}">${contractStatus[r.status]||r.status}</span>` }
  ], empty:'Nenhum contrato cadastrado ainda.'});
  bindEntityActions('contracts');
}

function renderMembers() {
  $('#users-list').innerHTML = state.members.length ? state.members.map(member => `<div class="member-row"><div class="entity-cell"><span class="entity-avatar">👤</span><div><strong>${escapeHTML(member.profile?.full_name || member.profile?.email || 'Usuário')}</strong><small>${escapeHTML(member.profile?.email || '')}</small></div></div><select data-member-role="${member.user_id}" ${(!isAdmin() || member.role==='owner')?'disabled':''}>${Object.entries(roleLabels).map(([value,label])=>`<option value="${value}" ${member.role===value?'selected':''}>${label}</option>`).join('')}</select><label class="switch-label"><input type="checkbox" data-member-active="${member.user_id}" ${member.active?'checked':''} ${(!isAdmin() || member.role==='owner')?'disabled':''}><span>Ativo</span></label></div>`).join('') : '<div class="empty-state">Nenhum usuário encontrado.</div>';
  $$('[data-member-role]').forEach(select => select.addEventListener('change', async () => {
    try { await one.updateMember(select.dataset.memberRole, { role: select.value }); toast('Nível de acesso atualizado.'); await refreshAll(); }
    catch (error) { toast(error.message, 'error'); await refreshAll(); }
  }));
  $$('[data-member-active]').forEach(input => input.addEventListener('change', async () => {
    try { await one.updateMember(input.dataset.memberActive, { active: input.checked }); toast('Status do usuário atualizado.'); await refreshAll(); }
    catch (error) { toast(error.message, 'error'); await refreshAll(); }
  }));
}

function bindEntityActions(table) {
  $$(`[data-edit-${table}]`).forEach(button => button.addEventListener('click', () => editEntity(table, button.getAttribute(`data-edit-${table}`))));
  $$(`[data-delete-${table}]`).forEach(button => button.addEventListener('click', () => deleteEntity(table, button.getAttribute(`data-delete-${table}`))));
}

function tableName(kind) { return `one_${kind}`; }
async function deleteEntity(kind, id) {
  if (!isAdmin()) { toast('Somente proprietário ou administrador pode excluir cadastros.', 'warning'); return; }
  const labels = { students:'aluno', guardians:'responsável', companies:'empresa', products:'produto', contracts:'contrato' };
  if (!confirm(`Excluir este ${labels[kind] || 'registro'}? O sistema bloqueará a exclusão se houver vínculos importantes.`)) return;
  try { await one.remove(tableName(kind), id); toast('Registro excluído.'); await refreshAll(); }
  catch (error) { toast(`Não foi possível excluir: ${error.message}`, 'error'); }
}

function editEntity(kind, id) {
  const item = state[kind].find(x=>x.id===id);
  if (!item) return;
  state.editing[kind] = id;
  const form = $(`#${kind}-form`);
  if (!form) return;
  Object.entries(item).forEach(([key,value]) => {
    const input = form.elements.namedItem(key);
    if (!input || ['file'].includes(input.type)) return;
    if (input.type === 'checkbox') input.checked = Boolean(value);
    else input.value = value ?? '';
  });
  $(`#${kind}-form-title`).textContent = kind==='students'?'Editar aluno':kind==='guardians'?'Editar responsável':kind==='companies'?'Editar empresa':kind==='products'?'Editar produto':'Editar contrato';
  state.desktop.open(kind);
  form.querySelector('input,select,textarea')?.focus();
}

function updateSelects() {
  const options = (items, valueKey, label) => `<option value="">Selecione...</option>${items.map(x=>`<option value="${x[valueKey]}">${escapeHTML(label(x))}</option>`).join('')}`;
  $('#contract-student-id').innerHTML = options(state.students.filter(x=>x.status!=='cancelado'), 'id', x=>x.full_name);
  $('#contract-guardian-id').innerHTML = options(state.guardians.filter(x=>x.active), 'id', x=>x.full_name);
  $('#contract-company-id').innerHTML = options(state.companies.filter(x=>x.active), 'id', x=>x.trade_name||x.legal_name);
  $('#contract-product-id').innerHTML = options(state.products.filter(x=>x.active), 'id', x=>`${x.name} • ${money(x.list_price)}`);
}

function formPayload(form) {
  const data = Object.fromEntries(new FormData(form).entries());
  Object.keys(data).forEach(key => { if (data[key] === '') data[key] = null; });
  form.querySelectorAll('input[type=checkbox]').forEach(input => data[input.name] = input.checked);
  return data;
}

async function saveStudent(event) {
  event.preventDefault();
  const form = event.currentTarget;
  const payload = formPayload(form);
  payload.cpf = digits(payload.cpf || '') || null;
  payload.cep = digits(payload.cep || '') || null;
  if (payload.cpf && !validCPF(payload.cpf)) return toast('CPF inválido. Confira os números.', 'warning');
  const duplicate = state.students.find(x=>x.cpf && x.cpf===payload.cpf && x.id!==state.editing.students);
  if (duplicate) return toast(`CPF já cadastrado para ${duplicate.full_name}.`, 'warning');
  try {
    const saved = await one.save('one_students', payload, state.editing.students);
    const file = $('#student-photo').files[0];
    if (file) {
      const photoPath = await one.uploadPhoto(file, 'students', saved.id);
      await one.save('one_students', { photo_path: photoPath }, saved.id);
    }
    toast(state.editing.students ? 'Aluno atualizado.' : 'Aluno cadastrado.');
    const advance = form.dataset.advance === 'contract';
    resetForm('students'); await refreshAll();
    if (advance) { state.desktop.open('contracts'); $('#contract-student-id').value = saved.id; $('#contract-product-id').focus(); }
  } catch (error) { toast(error.message, 'error'); }
  finally { delete form.dataset.advance; }
}

async function saveGuardian(event) {
  event.preventDefault(); const form=event.currentTarget; const payload=formPayload(form);
  payload.cpf=digits(payload.cpf||'')||null; payload.cep=digits(payload.cep||'')||null;
  if (payload.cpf && !validCPF(payload.cpf)) return toast('CPF inválido.', 'warning');
  const duplicate=state.guardians.find(x=>x.cpf&&x.cpf===payload.cpf&&x.id!==state.editing.guardians);
  if (duplicate) return toast(`CPF já cadastrado para ${duplicate.full_name}.`, 'warning');
  try { const saved=await one.save('one_guardians',payload,state.editing.guardians); const file=$('#guardian-photo').files[0]; if(file){ const photoPath=await one.uploadPhoto(file,'guardians',saved.id); await one.save('one_guardians',{photo_path:photoPath},saved.id); } toast(state.editing.guardians?'Responsável atualizado.':'Responsável cadastrado.'); resetForm('guardians'); await refreshAll(); }
  catch(error){ toast(error.message,'error'); }
}

async function saveCompany(event) {
  event.preventDefault(); const form=event.currentTarget; const payload=formPayload(form);
  payload.cnpj=digits(payload.cnpj||'')||null; payload.cep=digits(payload.cep||'')||null;
  if(payload.cnpj&&!validCNPJ(payload.cnpj)) return toast('CNPJ inválido.', 'warning');
  const duplicate=state.companies.find(x=>x.cnpj&&x.cnpj===payload.cnpj&&x.id!==state.editing.companies);
  if(duplicate) return toast(`CNPJ já cadastrado para ${duplicate.trade_name||duplicate.legal_name}.`,'warning');
  try { const saved=await one.save('one_companies',payload,state.editing.companies); const file=$('#company-photo').files[0]; if(file){ const photoPath=await one.uploadPhoto(file,'companies',saved.id); await one.save('one_companies',{photo_path:photoPath},saved.id); } toast(state.editing.companies?'Empresa atualizada.':'Empresa cadastrada.'); resetForm('companies'); await refreshAll(); }
  catch(error){ toast(error.message,'error'); }
}

async function saveProduct(event) {
  event.preventDefault(); const payload=formPayload(event.currentTarget);
  ['list_price','enrollment_fee'].forEach(k=>payload[k]=Number(payload[k]||0));
  payload.max_installments=Number(payload.max_installments||1);
  try { await one.save('one_products',payload,state.editing.products); toast(state.editing.products?'Produto atualizado.':'Produto cadastrado.'); resetForm('products'); await refreshAll(); }
  catch(error){ toast(error.message,'error'); }
}

function nextContractNumber() {
  const year = new Date().getFullYear();
  const seqs = state.contracts.map(c => String(c.contract_number||'')).filter(n => n.startsWith(`${year}-`)).map(n => Number(n.split('-').pop())).filter(Number.isFinite);
  const seq = (seqs.length ? Math.max(...seqs) : 0) + 1;
  return `${year}-${String(seq).padStart(5,'0')}`;
}
async function saveContract(event) {
  event.preventDefault(); const payload=formPayload(event.currentTarget);
  if(!payload.contract_number) payload.contract_number=nextContractNumber();
  ['contract_value','enrollment_fee','installment_value'].forEach(k=>payload[k]=Number(payload[k]||0));
  payload.installments=Number(payload.installments||1); payload.due_day=payload.due_day?Number(payload.due_day):null;
  if(!payload.student_id&&!payload.company_id) return toast('Selecione um aluno ou empresa contratante.','warning');
  try { await one.save('one_contracts',payload,state.editing.contracts); toast(state.editing.contracts?'Contrato atualizado.':'Contrato registrado.'); resetForm('contracts'); await refreshAll(); }
  catch(error){ toast(error.message,'error'); }
}

function resetForm(kind) {
  state.editing[kind]=null; const form=$(`#${kind}-form`); form?.reset();
  const titles={students:'Novo aluno',guardians:'Novo responsável',companies:'Nova empresa',products:'Novo produto ou plano',contracts:'Novo contrato'};
  const title=$(`#${kind}-form-title`); if(title) title.textContent=titles[kind];
  if(kind==='contracts') { $('#contract-number').value=nextContractNumber(); $('#contract-date').value=new Date().toISOString().slice(0,10); }
}

function bindFormControls() {
  $('#students-form').addEventListener('submit', saveStudent);
  $('#guardians-form').addEventListener('submit', saveGuardian);
  $('#companies-form').addEventListener('submit', saveCompany);
  $('#products-form').addEventListener('submit', saveProduct);
  $('#contracts-form').addEventListener('submit', saveContract);
  $('#student-save-contract').addEventListener('click', () => { $('#students-form').dataset.advance='contract'; $('#students-form').requestSubmit(); });
  $$('[data-reset-form]').forEach(btn=>btn.addEventListener('click',()=>resetForm(btn.dataset.resetForm)));
  $$('[data-mask="cpf"]').forEach(input=>input.addEventListener('input',()=>input.value=formatCPF(input.value)));
  $$('[data-mask="cnpj"]').forEach(input=>input.addEventListener('input',()=>input.value=formatCNPJ(input.value)));
  $$('[data-mask="cep"]').forEach(input=>input.addEventListener('input',()=>input.value=formatCEP(input.value)));
  $$('[data-mask="phone"]').forEach(input=>input.addEventListener('input',()=>input.value=formatPhone(input.value)));
  $('#student-cep').addEventListener('change',()=>fetchCEP($('#student-cep'),'#student-city','#student-state'));
  $('#guardian-cep').addEventListener('change',()=>fetchCEP($('#guardian-cep'),'#guardian-city','#guardian-state'));
  $('#company-cep').addEventListener('change',()=>fetchCEP($('#company-cep'),'#company-city','#company-state'));
  $('#contract-product-id').addEventListener('change',()=>{
    const product=state.products.find(x=>x.id===$('#contract-product-id').value); if(!product)return;
    $('#contract-value').value=Number(product.list_price||0).toFixed(2); $('#contract-enrollment-fee').value=Number(product.enrollment_fee||0).toFixed(2); $('#contract-installments').value=product.max_installments||1;
    const installments=Number(product.max_installments||1); $('#contract-installment-value').value=(Number(product.list_price||0)/installments).toFixed(2);
  });
}

function bindDesktop() {
  const desktop = new DesktopManager({ desktop:$('#desktop-canvas'), taskbarApps:$('#taskbar-apps'), startMenu:$('#start-menu') });
  state.desktop = desktop;
  [
    ['cadastros','Cadastros','🗂️'],['students','Alunos','👨‍🎓'],['guardians','Responsáveis','👨‍👩‍👧'],['companies','Empresas','🏢'],['products','Produtos e Planos','📦'],['contracts','Gestão do Aluno e Contratos','📄'],['commercial','Comercial','🎯'],['finance','Financeiro','💰'],['agenda','Agenda e Tarefas','🗓️'],['documents','Documentos','🗃️'],['reports','Relatórios','📊'],['admin','Administração','⚙️']
  ].forEach(([id,title,icon])=>desktop.register(id,{title,icon}));
  $$('[data-open-window]').forEach(button=>button.addEventListener('click',()=>desktop.open(button.dataset.openWindow)));
  $('#start-button').addEventListener('click',event=>{ event.stopPropagation(); $('#start-menu').classList.toggle('hidden'); });
  document.addEventListener('click',event=>{ if(!event.target.closest('#start-menu')&&!event.target.closest('#start-button')) $('#start-menu').classList.add('hidden'); });
  $('#commercial-frame').src=CRM_URL;
  $('#open-crm-new-tab').href=CRM_URL;
}

function bindClock() {
  const tick=()=>{ const now=new Date(); $('#clock-time').textContent=now.toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'}); $('#clock-date').textContent=now.toLocaleDateString('pt-BR',{day:'2-digit',month:'2-digit',year:'numeric'}); };
  tick(); setInterval(tick,30000);
}

async function init() {
  document.title=APP_NAME;
  bindDesktop(); bindFormControls(); bindClock(); resetForm('contracts');
  $('#login-form').addEventListener('submit', async event=>{
    event.preventDefault(); const button=$('#login-button'); button.disabled=true; button.textContent='Entrando...';
    const email=$('#login-email').value.trim(); const password=$('#login-password').value;
    const { data,error }=await supabase.auth.signInWithPassword({email,password});
    button.disabled=false; button.textContent='Entrar no Evolua One';
    if(error) return toast('E-mail ou senha inválidos.','error'); if(data.user) await enterApp(data.user);
  });
  $('#logout-button').addEventListener('click',async()=>{ await supabase.auth.signOut(); showLogin(); });
  $('#refresh-button').addEventListener('click',async()=>{ try{await refreshAll();toast('Dados atualizados.');}catch(error){toast(error.message,'error');} });
  $('#new-user-invite').addEventListener('click',()=>toast('O convite seguro de novos usuários será ativado na próxima etapa via função protegida do Supabase.','warning'));
  const {data:{session}}=await supabase.auth.getSession(); if(session?.user) await enterApp(session.user); else showLogin();
  supabase.auth.onAuthStateChange(async(event,sessionState)=>{ if(event==='SIGNED_OUT')showLogin(); if(event==='SIGNED_IN'&&sessionState?.user&&state.user?.id!==sessionState.user.id)await enterApp(sessionState.user); });
}

init();
