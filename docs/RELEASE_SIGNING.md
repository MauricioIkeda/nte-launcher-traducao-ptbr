# Assinatura das releases Windows

O workflow de release assina o executável do launcher e o instalador quando os
segredos abaixo estão configurados no repositório:

- `WINDOWS_SIGNING_CERTIFICATE_BASE64`: conteúdo Base64 do certificado PFX;
- `WINDOWS_SIGNING_CERTIFICATE_PASSWORD`: senha do PFX.

A chave privada nunca deve ser adicionada ao Git. O workflow grava o PFX apenas
no diretório temporário do runner, usa SHA-256 e carimbo de tempo e verifica a
assinatura antes de publicar a release.

Sem esses segredos, o workflow continua produzindo uma release não assinada
para não interromper o desenvolvimento. Uma distribuição pública profissional
deve configurar um certificado Authenticode e exigir a etapa de assinatura.

Assinar o binário protege a identidade do editor. A etapa seguinte de
hardening é assinar também os manifestos JSON com uma chave Ed25519 offline e
embutir somente a chave pública no launcher.
