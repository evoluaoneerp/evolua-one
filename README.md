# Evolua One v0.1

Primeira fundação funcional do ERP da Evolua.

## O que já funciona

- Login pelo mesmo Supabase do CRM atual.
- Área de trabalho estilo Windows.
- Atalhos em cascata, janelas arrastáveis, redimensionáveis, minimizáveis e maximizáveis.
- Módulo Cadastros:
  - alunos;
  - pais/responsáveis;
  - empresas;
  - produtos, cursos, planos e serviços;
  - usuários já vinculados e níveis de acesso existentes.
- CPF/CNPJ com máscara, validação e prevenção de duplicidade no sistema.
- CEP localiza apenas cidade e UF.
- Foto armazenada em bucket privado do Supabase.
- Alerta de aniversariantes na área de trabalho.
- Fluxo "Salvar aluno e avançar para contrato".
- Base inicial de Gestão do Aluno e Contratos.
- Histórico automático de status contratual no banco.
- CRM Comercial atual aberto dentro de uma janela do Evolua One.

## O que está reservado para as próximas fases

- Modelos e geração final dos contratos em PDF.
- Histórico de atendimento na interface.
- Financeiro completo.
- Agenda e tarefas consolidadas.
- Documentos + Google Drive.
- Relatórios e indicadores.
- Convite seguro de novos usuários por Edge Function.
- Central de backup para D:\\Documentos Marcos\\EvoluaOne.

## Instalação

1. No Supabase, abra SQL Editor > New query.
2. Execute `database/EVOLUA_ONE_V0.1.sql` inteiro.
3. Crie um repositório GitHub novo, sugerido: `evolua-one`.
4. Envie todos os arquivos e pastas deste projeto para a raiz do repositório.
5. Ative GitHub Pages usando a branch principal e pasta `/root`.
6. Abra a URL publicada e entre com o mesmo usuário do CRM atual.

## Importante

A migração é incremental. Ela usa as tabelas `workspaces`, `workspace_members` e `profiles` já existentes, e não apaga o CRM Comercial nem seus dados.
