# PT-BR hospedado no slot francês

Novas releases podem declarar no `translation_manifest.json`:

```json
{
  "localization": {
    "sourceCulture": "en",
    "installationCulture": "fr",
    "targetLanguage": "pt-BR",
    "hostCompatible": true,
    "hostLocresSha256": "..."
  }
}
```

O launcher mantém compatibilidade com manifests antigos sem `localization`. Nesses manifests, nenhuma preferência de idioma é alterada.

Para uma release explicitamente marcada como `en -> pt-BR` hospedada em `fr`, a instalação tenta localizar uma configuração textual já existente do NTE em `%LOCALAPPDATA%/HT/.../Config/...` e mudar somente uma chave reconhecida de idioma de texto/interface/cultura para `fr`.

Regras de segurança:

- nunca altera chaves contendo `voice`, `audio`, `dub` ou `speech`;
- nunca inventa uma chave se nenhuma configuração segura existir;
- se houver candidatos igualmente plausíveis, não altera nenhum;
- guarda no recibo apenas os metadados necessários para desfazer a alteração;
- a desinstalação restaura somente a linha do idioma, preservando gráficos/controles alterados depois;
- se o usuário mudar manualmente o idioma depois da instalação, a desinstalação preserva essa escolha;
- uma reinstalação mantém a preferência original registrada na primeira instalação.

A mudança automática é um conforto. A ausência de uma chave detectável não bloqueia a instalação da tradução; nesse caso o usuário pode selecionar francês manualmente.
