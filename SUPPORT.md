# Suporte

O suporte do NTE Launcher Tradução PT-BR é comunitário e acontece pelas
[issues do GitHub](https://github.com/MauricioIkeda/nte-launcher-traducao-ptbr/issues/new/choose).

O botão **Suporte** fica permanentemente visível na barra superior do launcher.
Na central, escolha entre bug do launcher, instalação, tradução ou sugestão.

Antes de abrir um relato:

1. atualize o launcher para a versão mais recente;
2. feche o jogo;
3. selecione a pasta principal do jogo ou a subpasta `NTEGlobal`;
4. abra **Configurações > Gerar diagnóstico completo**;
5. escolha o formulário correspondente e anexe o diagnóstico após revisá-lo.

Para erros ou sugestões de tradução, não é necessário exportar o diagnóstico.
Informe o texto atual, a sugestão, o contexto e, se possível, uma captura de
tela.

## Tradução de teste do Studio e instalação pública

Os dois gerenciadores usam os mesmos cinco destinos. Se instalar um build de
teste sobre uma tradução do launcher, desfaça **primeiro o teste no Studio**;
ele restaura a instalação pública anterior. Só depois repare, atualize ou remova
no launcher. Não remova pelo launcher enquanto o teste ainda estiver ativo.

O reparo não deve adivinhar a origem de um PAK/UTOC/UCAS diferente. Arquivos
sem propriedade comprovada continuam bloqueados para proteger o jogo. Um
contêiner já registrado que corresponda exatamente ao novo payload público
pode ser reconciliado com segurança; isso não libera arquivos desconhecidos.

A remoção agora confere o conjunto completo e os backups antes de escrever:
um conflito conhecido bloqueia sem apagar os outros arquivos nem reduzir o
recibo. Falhas de I/O ou alterações externas durante a execução ainda exigem
diagnóstico; não há promessa de atomicidade do filesystem entre gerenciadores.
O botão informa quando a remoção foi bloqueada antes de começar, em vez de
chamar todo conflito de “remoção parcial”.

## O launcher abriu, mas a janela não apareceu

O launcher não minimiza para a bandeja. A partir da versão 1.3.6, ele mostra
imediatamente uma tela de inicialização e informa quando a preparação de
certificados ou da pasta de dados falha. Em Wine/Proton, use **Tentar
novamente** e confira se o prefixo permite acesso à pasta de dados.

Se o problema continuar, informe também a versão do Wine/Proton, a distribuição
Linux, o ambiente gráfico e como o executável foi iniciado (Lutris, Bottles,
Steam ou terminal). Esses dados distinguem uma falha de inicialização do
launcher de uma janela ocultada pelo gerenciador de janelas.

O diagnóstico é um único `diagnostico.json` autocontido. Ele reúne versões,
sistema operacional, indicadores de Wine/Proton, origem Steam/Epic/oficial,
estado e recibo da tradução, executáveis, última tentativa, histórico e trechos
protegidos dos logs do launcher e do NTE. Os arquivos de log rotativos ficam
limitados e são apenas armazenamento interno; não precisam ser enviados.

O launcher não transmite o diagnóstico automaticamente. Segredos conhecidos
como tokens e chaves são suprimidos, mas caminhos locais podem identificar o
nome do usuário. Revise o arquivo antes de publicá-lo.

Não publique vulnerabilidades de segurança como uma issue comum. Use o canal
privado disponível na aba **Security** do repositório.
