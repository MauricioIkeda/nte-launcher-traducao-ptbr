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
