# Publicação de conteúdo com runtime anterior pinado

O schema público continua em1, com os cinco destinos já suportados pelo cliente.
A extensão opcional runtimeReference contém version1, tag e manifestSha256.
Essa release distribui apenas pakchunk999-Windows_999_P.pak,
translation_manifest.json e build-manifest.json; os quatro outros descritores
continuam apontando à release completa anterior do mesmo repositório autorizado.

O sincronizador confere a referência pela API e pelo manifesto bruto pinado.
Auxiliares precisam coincidir integralmente em nome, destino, tamanho, hash e URL.
Uma referência só pode ser anterior, completa, publicada e final. Não há cadeia
de referências. Host localization/gameBuildId devem coincidir; mudança exige
uma nova referência completa com compatibilidade estabelecida.

As releases legadas de sete assets continuam aceitas. Três assets sem referência,
mistura dos dois contratos, PAK antigo ou referência adulterada são recusados.
Despatch e recuperação agendada usam o mesmo validador. Imutabilidade da versão,
UTC monotônica, URLs autorizadas e escrita atômica continuam aplicáveis.

O produtor V3 prepara os três assets a partir da materialização nativa verificada;
não copia, modifica ou executa os auxiliares anteriores. O cliente instalado
continua gerenciando os cinco arquivos e conserva seus recibos/backups.
Ensaio Dart em instalação fictícia verifica update, rollback e uninstall.

Antes de lançar, instalar este sincronizador na branch usada pela Action,
conferir PAK/LOCRES por leitor independente, backup/restore, hashes e contagens.
Criar/upload da draft precedem a publicação; conferir os três assets remotos
antes de torná-la pública. Depois, enviar translation-released com manifesto
pinado ou executar recovery; conferir manifesto publicado no main para a tag
exata. Preparação ou ensaio local não significam publicação concluída.
