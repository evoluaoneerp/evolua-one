# Evolua One v0.2.0

Sistema integrado de gestão da Evolua.

## O que já funciona
- Desktop com janelas e wallpaper institucional.
- Cadastros de alunos, responsáveis, empresas, cursos, pacotes, planos e serviços.
- Comercial integrado ao CRM atual.
- Gestão do aluno com contratos, status e histórico de atendimento.
- Geração de ficha contratual para impressão/PDF.
- Geração automática das parcelas do contrato.
- Financeiro com contas a receber, recebimentos, contas a pagar, pagamentos e contas/caixas.
- Agenda e tarefas, prioridades, responsáveis e aniversariantes.
- Central de documentos com links do Google Drive.
- Relatórios executivos, CSV e impressão.
- Usuários e níveis de acesso para usuários já existentes no Supabase Auth.
- Backup JSON do sistema com seletor do Windows.

## Atualização do banco
Execute antes de publicar esta versão:

`database/EVOLUA_ONE_V0.2_MIGRACAO.sql`

A migração é incremental e não apaga cadastros existentes.

## Backup recomendado
`D:\Documentos Marcos\EvoluaOne\01_Backups_do_Sistema`

A pasta já sincronizada pelo Google Drive mantém uma cópia no HD e outra na nuvem.
