# Evolua One v0.3.0

## Arquitetura Integrada
- Secretaria substitui o antigo módulo genérico de Cadastros.
- Matrícula virou uma entidade própria e independente do contrato.
- Fluxo principal: Aluno → Matrícula → Contrato → Financeiro.
- Contrato herda aluno e produto da matrícula, reduzindo duplicidade e inconsistência.
- Parcelas geradas pelo contrato ficam vinculadas à matrícula.
- Contratos existentes são migrados automaticamente para matrículas na migração SQL V0.3.

## Prontuário Único
- Resumo do aluno.
- Matrículas.
- Contratos.
- Financeiro.
- Atendimentos.
- Responsáveis vinculados.
- Documentos.
- Linha do tempo da jornada.

## Navegação
- Secretaria, Comercial, Contratos, Financeiro, Agenda, Relatórios e Administração como módulos principais.
- Documentos continuam disponíveis dentro do sistema, mas deixam de ocupar um atalho principal do desktop.

## Compatibilidade
- Preserva V0.1 e V0.2.
- Não apaga dados existentes.
- CRM atual continua abrindo no módulo Comercial até a migração controlada da base comercial.
