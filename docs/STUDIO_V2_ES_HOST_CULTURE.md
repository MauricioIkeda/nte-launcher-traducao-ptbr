# Releases do Studio V2 no slot espanhol

O NTE Localization Studio V2 gera a tradução PT-BR no slot físico `es` do
`Game.locres`. O inglês continua sendo a fonte canônica e os demais slots do
jogo não são alterados. A partir do contrato de manifesto schema 1, o launcher
aceita `installationCulture: "es"` além do slot francês legado (`fr`).

O campo `localization.hostLocresSha256` é o SHA-256 do LOCRES original do slot
que será substituído, nunca o hash de um `.pak`. O instalador usa esse valor
para confirmar que a instalação corresponde à mesma build do jogo antes de
escrever os cinco artefatos gerenciados.

Releases antigas em `fr` continuam válidas e podem ser removidas pelo mesmo
recibo. Releases novas do V2 devem preferir `es`; a cultura é lida do manifesto
e não fica hardcoded no fluxo de verificação.

## Migração de uma instalação V1

Uma atualização V1 → V2 não executa uma remoção destrutiva seguida de uma nova
instalação. Os cinco destinos do launcher são os mesmos, então o instalador
abre uma única transação: valida o pacote V2, preserva os arquivos originais já
registrados, substitui os payloads, troca somente a cultura textual de `fr`
para `es` e grava o novo recibo por último. Se alguma etapa falhar, os payloads
e a configuração de idioma voltam ao estado anterior.

Quando o recibo existente comprova que a instalação V1 é gerenciada pelo
launcher, a verificação classifica uma instalação francesa válida como
desatualizada diante de um manifesto V2 espanhol, mesmo que os hashes dos cinco
arquivos coincidam. Isso torna a troca explícita e evita que o launcher trate a
instalação antiga como atual.

O backup-base do idioma continua sendo o estado encontrado antes da primeira
instalação. Assim, remover depois a V2 restaura o idioma original do jogador —
não força `fr` — e preserva outras preferências. Se o usuário alterou o idioma
manualmente depois da instalação, a migração não sobrescreve essa escolha. Se
não houver recibo ou associação comprovável com a instalação antiga, o launcher
não adivinha nem apaga arquivos: a proteção existente bloqueia a operação e
solicita uma ação verificável.
