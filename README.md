# Evolua One

Sistema integrado de gestão da Evolua.

## Versão
0.1.1 - fundação para banco Supabase novo.

## Nesta fase
- Desktop em janelas estilo Windows
- Login Supabase Auth
- Workspace e perfis
- Cadastros de alunos, responsáveis e empresas
- Cursos, pacotes, planos e serviços
- Fotos em Storage privado
- CPF/CNPJ com validação e prevenção de duplicidade
- CEP com cidade/UF
- Gestão inicial de contratos
- Histórico de status contratual
- Auditoria básica de alterações
- Aniversariantes
- CRM atual aberto como módulo Comercial integrado
- Estruturas reservadas para Financeiro, Agenda, Documentos, Relatórios e Backup

## Segurança
A chave publicada no frontend é a Publishable Key do Supabase. O acesso real aos dados é protegido por autenticação e RLS. Nunca coloque Secret Key ou service_role neste repositório.
