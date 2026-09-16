// ============================================================================
// GTM RDO — testes do lado JS do PWA
// ============================================================================
// COMO RODAR:   node testes_pwa.js
//
// Sem framework, sem package.json, sem dependência: só Node e o index.html.
// É de propósito -- o projeto não tem build step e não vai ganhar um por causa
// de teste (CLAUDE.md §4).
//
// POR QUE ESTE ARQUIVO EXISTE:
//
// Até 08/09 a permissão de notificação nunca era pedida. A função que pede
// (pedirPermissaoEInscreverPush) tinha um único chamador, que começava com
// `if (Notification.permission !== "granted") return;` -- ou seja, só agia se
// a permissão JÁ estivesse concedida. Como nada no app chegava a pedir pela
// primeira vez, ela ficava em "default" para sempre e push_subscriptions nunca
// recebia uma linha. O servidor inteiro estava pronto e o push não funcionava
// por falta de um botão.
//
// O erro passou despercebido porque não havia teste nenhum do lado JS. Este
// arquivo é o começo dessa rede -- cobre o convite, que é o gatilho de tudo.
//
// Ele lê o index.html e extrai a função, então não há cópia do código aqui
// para divergir com o tempo: se a função mudar de forma incompatível, o teste
// quebra, que é o objetivo.
// ============================================================================

const fs = require("fs");
const path = require("path");

const CAMINHO_HTML = path.join(__dirname, "index.html");

function extrairFuncao(nomeInicio, nomeFim) {
  const html = fs.readFileSync(CAMINHO_HTML, "utf8");
  const ini = html.indexOf(nomeInicio);
  const fim = html.indexOf(nomeFim);
  if (ini < 0 || fim < 0 || fim <= ini) {
    console.error("FALHA ESTRUTURAL: não achei " + nomeInicio + " em index.html.");
    console.error("Se a função foi renomeada, ajuste este teste -- não o apague.");
    process.exit(1);
  }
  return html.slice(ini, fim);
}

const fonteConvite = extrairFuncao("function renderConvitePush()", "function renderTelaLista()");

let erros = 0;
function checar(nome, ok, detalhe) {
  console.log((ok ? "ok     " : "FALHA  ") + nome + (ok ? "" : "\n         veio: " + detalhe));
  if (!ok) erros++;
}

// Executa a função com um ambiente de navegador simulado. Só os globais que
// ela realmente toca -- window, navigator e Notification.
function renderizarCom(amb) {
  const fn = new Function(
    "window", "navigator", "Notification",
    fonteConvite + "; return renderConvitePush();"
  );
  return fn(amb.window, amb.navigator, amb.Notification);
}

function ambienteAndroid(permissao) {
  return {
    window: {
      Notification: { permission: permissao },
      PushManager: function () {},
      matchMedia: function () { return { matches: false }; },
      navigator: {}
    },
    navigator: { userAgent: "Mozilla/5.0 (Linux; Android 13)", serviceWorker: {} },
    Notification: { permission: permissao }
  };
}

console.log("--- convite de notificação (renderConvitePush) ---\n");

// 1. O caminho que importa: ninguém decidiu ainda, o aparelho suporta.
//    Sem isto, a permissão nunca sai de "default" e o push nunca funciona.
let html = renderizarCom(ambienteAndroid("default"));
checar("permissão 'default' com suporte -> oferece o botão",
  html.indexOf("btn-push-ativar") !== -1, JSON.stringify(html));

// 2. Já concedida: o convite tem que sumir, senão fica pedindo o que já tem.
html = renderizarCom(ambienteAndroid("granted"));
checar("permissão já concedida -> convite some", html === "", JSON.stringify(html));

// 3. Negada: insistir é o caminho mais curto para o operador bloquear o site
//    de vez. E reabrir o pedido nem funciona -- o navegador devolve "denied"
//    sem perguntar nada.
html = renderizarCom(ambienteAndroid("denied"));
checar("permissão negada -> não insiste", html === "", JSON.stringify(html));

// 4. iPhone no Safari, fora da tela de início: o PushManager nem existe
//    (iOS 16.4+ só expõe em standalone). Mostrar um botão que não faria nada
//    seria pior que não mostrar -- então vai a orientação de instalar.
html = renderizarCom({
  window: {
    Notification: { permission: "default" },
    matchMedia: function () { return { matches: false }; },
    navigator: { standalone: false }
  },
  navigator: {
    userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)",
    serviceWorker: {}, standalone: false
  },
  Notification: { permission: "default" }
});
checar("iPhone fora da tela de início -> orienta instalar, sem botão inútil",
  html.indexOf("Tela de In") !== -1 && html.indexOf("btn-push-ativar") === -1,
  JSON.stringify(html));

// 5. iPhone JÁ instalado na tela de início: aí o PushManager existe e o botão
//    deve aparecer normalmente.
html = renderizarCom({
  window: {
    Notification: { permission: "default" },
    PushManager: function () {},
    matchMedia: function () { return { matches: true }; },
    navigator: { standalone: true }
  },
  navigator: {
    userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)",
    serviceWorker: {}, standalone: true
  },
  Notification: { permission: "default" }
});
checar("iPhone instalado na tela de início -> oferece o botão",
  html.indexOf("btn-push-ativar") !== -1, JSON.stringify(html));

// 6. Navegador antigo sem Notification: não pode quebrar a tela de lista.
html = renderizarCom({
  window: { matchMedia: function () { return { matches: false }; }, navigator: {} },
  navigator: { userAgent: "qualquer", serviceWorker: {} },
  Notification: undefined
});
checar("sem suporte a Notification -> não renderiza nada", html === "", JSON.stringify(html));

// 7. Regressão: garante que o botão continua ligado a um handler. Se alguém
//    renomear o id no HTML e esquecer do ligarEventosLista, o push volta a
//    ficar mudo do mesmo jeito que estava antes de 08/09.
const htmlCompleto = fs.readFileSync(CAMINHO_HTML, "utf8");
checar("o id do botão é o mesmo em quem renderiza e em quem liga o evento",
  htmlCompleto.indexOf('id="btn-push-ativar"') !== -1 &&
  htmlCompleto.indexOf('getElementById("btn-push-ativar")') !== -1,
  "id divergente entre render e wiring");

// 8. Regressão: quem realmente cria a inscrição é pedirPermissaoEInscreverPush.
//    O botão precisa chamá-la -- foi a ausência de qualquer chamador a partir
//    de um toque que deixou o push mudo.
checar("o clique do botão chama pedirPermissaoEInscreverPush",
  /btn-push-ativar[\s\S]{0,600}pedirPermissaoEInscreverPush\(\)/.test(htmlCompleto),
  "o handler do botão não chama a função que inscreve");

// ---------------------------------------------------------------------------
// Devolução aparecer sem o operador recarregar o app
// ---------------------------------------------------------------------------
// Relatado no primeiro teste real de push (08/09): a notificação chegou, o
// operador tocou nela, o app veio pra frente -- e a devolução não estava lá.
// Só aparecia recarregando na mão.
//
// A causa: o service worker chama focus() na janela existente, e focar não
// recarrega nem avisa a página. A checagem de devolvidas só rodava no login.
//
// Recarregar seria a correção errada: perderia rascunho de RDO não salvo. O
// certo é avisar a página, que só rebusca as devolvidas.
//
// Estes testes cobrem os dois lados do contrato, que moram em ARQUIVOS
// DIFERENTES -- é exatamente o tipo de ligação que se quebra em silêncio.
console.log("\n--- devolvida aparece sem recarregar ---\n");

const sw = fs.readFileSync(path.join(__dirname, "sw.js"), "utf8");

checar("sw.js avisa a página ao clicar na notificação",
  /notificationclick[\s\S]{0,1200}postMessage\(\s*\{\s*tipo:\s*["']notificacao-clicada["']/.test(sw),
  "o handler de notificationclick não faz postMessage");

checar("sw.js continua usando focus(), não reload (não perder rascunho)",
  /notificationclick[\s\S]{0,1500}\.focus\(\)/.test(sw) &&
  !/notificationclick[\s\S]{0,1500}location\.reload/.test(sw),
  "o handler recarrega a página em vez de focar");

checar("index.html escuta a mensagem do service worker",
  /serviceWorker\.addEventListener\(\s*["']message["']/.test(htmlCompleto) &&
  htmlCompleto.indexOf('"notificacao-clicada"') !== -1,
  "não há listener de message, ou o nome do evento diverge do sw.js");

checar("o nome do evento é o MESMO nos dois arquivos",
  sw.indexOf("notificacao-clicada") !== -1 &&
  htmlCompleto.indexOf("notificacao-clicada") !== -1,
  "sw.js e index.html usam nomes diferentes -- a mensagem nunca casaria");

checar("index.html revalida quando o app volta a ficar visível",
  /addEventListener\(\s*["']visibilitychange["']/.test(htmlCompleto) &&
  /visibilityState\s*===\s*["']visible["']/.test(htmlCompleto),
  "sem listener de visibilitychange: reabrir o app não revalidaria");

checar("a revalidação chama verificarAtividadesDevolvidas",
  /function revalidarDevolvidas\(\)[\s\S]{0,600}verificarAtividadesDevolvidas\(\)/.test(htmlCompleto),
  "revalidarDevolvidas não chama quem busca as devolvidas");

// ---------------------------------------------------------------------------
// "Enviou, acabou" — só a devolução reabre o apontamento
// ---------------------------------------------------------------------------
// Regra do Fábio (08/09). Quem garante é o servidor
// (trava_edicao_pos_envio.sql): ele congela o que já foi enviado e IGNORA a
// alteração, em vez de recusar a sincronização inteira -- o RDO do dia não
// pode ficar preso no aparelho por causa de um apontamento travado.
//
// Justamente por isso as checagens do app são indispensáveis: sem elas o
// operador editaria, o servidor ignoraria em silêncio, e o aparelho seguiria
// mostrando o valor novo enquanto o banco guarda o antigo. O pior tipo de bug
// é o que não aparece.
console.log("\n--- enviou, acabou: trava de edição ---\n");

checar("bloqueia reabrir relatório já enviado sem devolução",
  /function confirmarReabrir[\s\S]{0,400}relatorioJaEnviado\(r\)\s*&&\s*!relatorioTemDevolucao\(r\)/.test(htmlCompleto),
  "confirmarReabrir não checa o estado antes de reabrir");

// A checagem mudou de relatorioJaEnviado() para atividadeJaEnviada() em 08/09,
// depois que o Fábio achou o furo do "reabri, logo posso apagar" -- ver a
// seção no fim deste arquivo. O teste acompanha a correção.
checar("bloqueia remover apontamento já enviado sem devolução",
  /del-ativ[\s\S]{0,900}atividadeJaEnviada\(ativ\)\s*&&\s*!atividadeFoiDevolvida\(/.test(htmlCompleto),
  "o botão de remover não checa se o apontamento já foi enviado");

checar("relatório com devolução PODE ser reaberto (senão a correção fica impossível)",
  /function relatorioTemDevolucao\(r\)[\s\S]{0,400}relatorio_uuid_dispositivo === r\.id/.test(htmlCompleto),
  "relatorioTemDevolucao não casa o relatório com a lista de devolvidas");

checar("a trava só vale depois de sincronizar (rascunho continua livre)",
  /function relatorioJaEnviado\(r\)[\s\S]{0,200}relatorioSincronizado\(r\)/.test(htmlCompleto),
  "relatorioJaEnviado não considera o estado de sincronização");

checar("avisa o operador quando o servidor ignora alterações",
  /dados\.congeladas[\s\S]{0,300}remocoes_negadas[\s\S]{0,400}showToast/.test(htmlCompleto),
  "a resposta da sincronização não é lida, ou o aviso não aparece");

// ---------------------------------------------------------------------------
// O furo do "reabri, logo posso apagar tudo"
// ---------------------------------------------------------------------------
// Encontrado pelo Fábio testando, horas depois de a trava entrar (08/09): ele
// conseguiu excluir um apontamento que já estava no painel.
//
// A primeira versão da trava usava relatorioJaEnviado(), que exige
// `r.status === "concluido"`. Só que confirmarReabrir() faz
// `r.status = "rascunho"` -- então bastava reabrir para a trava sumir. E
// reabrir é o caminho LEGÍTIMO de atender a uma devolução: corrigir um
// apontamento destravava a exclusão de todos os outros.
//
// O estrago não era perder a alteração. O servidor recusa a remoção, então o
// apontamento continua no banco -- mas o app apagava localmente. O painel
// devolvia algo que não existia mais no aparelho, o banner aparecia, e o
// operador não tinha o que corrigir: fluxo travado, sem saída.
//
// A marca passou a ser por atividade (`enviadaEm`), que nada limpa.
console.log("\n--- exclusão depois de reabrir (furo de 08/09) ---\n");

checar("a trava de exclusão NÃO depende de relatorioJaEnviado (some ao reabrir)",
  !/del-ativ[\s\S]{0,900}relatorioJaEnviado\(r\)\s*&&\s*!atividadeFoiDevolvida/.test(htmlCompleto),
  "voltou a usar relatorioJaEnviado: reabrir destrava a exclusão de novo");

checar("exclusão checa a marca da própria atividade (enviadaEm)",
  /del-ativ[\s\S]{0,900}atividadeJaEnviada\(ativ\)\s*&&\s*!atividadeFoiDevolvida\(/.test(htmlCompleto),
  "o botão de remover não usa atividadeJaEnviada");

checar("edição checa a mesma marca (senão reabrir destrava alterar)",
  /atividadeJaEnviada\(ativCard\)\s*&&\s*!atividadeFoiDevolvida\(/.test(htmlCompleto),
  "abrir a atividade para edição não verifica se ela já foi enviada");

checar("enviadaEm é gravado quando a sincronização dá certo",
  /rpcSincronizado = true[\s\S]{0,300}marcarAtividadesComoEnviadas\(r\)/.test(htmlCompleto),
  "a marca não é gravada após sincronizar");

checar("reabrir NÃO limpa enviadaEm",
  !/r\.status = "rascunho"[\s\S]{0,200}enviadaEm\s*=\s*(null|undefined|"")/.test(htmlCompleto),
  "confirmarReabrir está limpando a marca -- o furo volta");

// Extrai a função inteira em vez de medir distância em caracteres: a primeira
// versão destes testes usava {0,900} e quebrou quando o comentário explicativo
// cresceu. Teste que falha por causa do tamanho de um comentário não é teste,
// é armadilha.
const fonteMigracao = extrairFuncao("function marcarEnviadasRetroativo", "function atividadeJaEnviada");

checar("RDO sincronizado antes desta versão também fica protegido",
  fonteMigracao.indexOf("enviadaEm") !== -1 &&
  /carregarRelatoriosSalvos[\s\S]{0,400}marcarEnviadasRetroativo\(\)/.test(htmlCompleto),
  "sem marcação retroativa, o que já está no aparelho segue destravado");

// SEGUNDA falha da mesma trava, achada pelo Fábio em 09/09: um RDO
// sincronizado numa versão antiga e depois REABERTO não era migrado, porque
// relatorioSincronizado() exige status "concluido" e rpcSincronizado true --
// e reabrir zera os dois. Ficava sem marca nenhuma, e o app oferecia excluir
// um apontamento que já estava com o revisor.
//
// sincronizadoEm é o que sobrevive: registra um fato do passado ("subiu em tal
// hora"), não o estado de agora.
checar("a migração usa sincronizadoEm, que sobrevive a reabrir",
  /!r\.sincronizadoEm\s*&&\s*!relatorioSincronizado\(r\)/.test(fonteMigracao),
  "voltou a depender só de relatorioSincronizado: RDO reaberto fica destravado");

checar("a migração roda uma vez por relatório (não marca atividade criada depois)",
  /if \(r\.migrouEnviadaEm\) return;/.test(fonteMigracao) &&
  /r\.migrouEnviadaEm = true/.test(fonteMigracao),
  "sem a flag, um rascunho novo seria marcado como enviado na carga seguinte");

// TERCEIRA falha da mesma trava (09/09). As duas anteriores foram no
// apontamento; esta era no RELATÓRIO INTEIRO -- o botão de excluir da lista
// não checava nada, e ele leva junto todos os apontamentos, inclusive os já
// revisados.
//
// O que torna isso sem volta: o PWA não baixa relatório do servidor. O RDO
// apagado some do aparelho e continua no banco; se um apontamento dele for
// devolvido depois, o operador não tem o que corrigir e a devolução fica
// pendente para sempre.
//
// Lição das três: a trava tem que perguntar "já subiu alguma vez?" e não
// "está sincronizado agora?".
// Extrai o handler inteiro em vez de medir distância: a primeira versão deste
// teste usava {0,900} e falhou porque o comentário explicativo passou disso.
const handlerExcluirRdo = extrairFuncao('querySelectorAll(".del")', 'function contarIdentRequerido');

checar("excluir o RELATÓRIO checa se ele já subiu",
  /relatorioJaSubiu\(rel\)/.test(handlerExcluirRdo),
  "o botão de excluir relatório não verifica nada -- o furo de 09/09 voltou");

checar("relatorioJaSubiu se apoia em sincronizadoEm, não no estado atual",
  /function relatorioJaSubiu\(r\)[\s\S]{0,400}r\.sincronizadoEm/.test(htmlCompleto),
  "relatorioJaSubiu voltou a depender só do estado volátil");

// As mensagens que o operador lê. O Fábio pediu "já subiu para revisão" no
// lugar de "já foi para o escritório" -- o RDO sobe para ser revisado, não
// muda de lugar físico.
// Sem o número, "peça a devolução" não diz O QUÊ pedir -- o revisor recebe
// "devolve aquele apontamento" e tem que adivinhar qual. Apontado pelo Fábio
// em 09/09, junto com a implantação do número.
// A mensagem precisa citar o número E continuar legível quando não há número
// (apontamento anterior a 09/09). A primeira versão concatenava uma referência
// genérica e produzia "peça a devolução do 'Limpeza de valeta' — cite esse
// número" e "Apontamento este apontamento já subiu". Os testes passavam; foi
// imprimir a saída real que mostrou o problema. Por isso o teste agora executa
// a função e olha o texto, em vez de conferir se o helper existe.
const fonteAviso = extrairFuncao("function avisoApontamentoTravado", '// "Já subiu alguma vez"');
const avisoDe = new Function(fonteAviso + "; return avisoApontamentoTravado;")();

let av = avisoDe({ numero: 12, tipo_atividade: "Construção de Aterro" }, "removido");
checar("com número: título e texto citam #12",
  av.titulo.indexOf("#12") !== -1 && av.texto.indexOf("#12") !== -1,
  JSON.stringify(av));

av = avisoDe({ tipo_atividade: "Limpeza de valeta" }, "removido");
checar("sem número: não fala em 'número' nem repete 'apontamento' no título",
  av.texto.indexOf("esse número") === -1 &&
  av.titulo.indexOf("este apontamento") === -1 &&
  av.texto.indexOf("Limpeza de valeta") !== -1,
  JSON.stringify(av));

av = avisoDe({}, "alterado");
checar("sem dado nenhum: frase continua inteira e sem lacuna",
  av.texto.indexOf("  ") === -1 && av.texto.indexOf(" ,") === -1 &&
  av.texto.indexOf("alterado") !== -1,
  JSON.stringify(av));

checar("os dois bloqueios de apontamento usam o helper",
  (htmlCompleto.match(/avisoApontamentoTravado\((ativ|ativCard), /g) || []).length === 2,
  "alguma mensagem de bloqueio ficou sem citar o apontamento");

checar("o bloqueio de reabrir o RDO lista os números disponíveis",
  /peça a devolução do apontamento pelo número/.test(htmlCompleto),
  "a mensagem do relatório não diz quais números pedir");

checar("as mensagens de bloqueio usam 'subiu para revisão'",
  htmlCompleto.indexOf("já subiu para revisão") !== -1 &&
  htmlCompleto.indexOf("já foi para o escritório") === -1,
  "sobrou 'já foi para o escritório' em alguma mensagem ao usuário");

// ---------------------------------------------------------------------------
// Rótulo não pode viver no placeholder
// ---------------------------------------------------------------------------
// Relatado pelo Fábio (08/09): ao reabrir um apontamento devolvido para
// corrigir, ele via os valores preenchidos e não sabia mais qual campo era
// qual -- porque o nome do campo estava no placeholder, e placeholder some
// quando há valor. Some justamente na hora de conferir o que foi digitado.
//
// Vale para os cards de equipamento e máquina, que não usam campoHtml() (o
// layout é em grade, vários campos por linha) e por isso não tinham rótulo.
console.log("\n--- rótulo fixo nos campos de equipamento e máquina ---\n");

checar("existe o helper que põe rótulo acima do campo",
  /function rotulado\(rotulo, htmlCampo\)[\s\S]{0,300}campo-rotulado/.test(htmlCompleto),
  "helper rotulado() não encontrado");

// Os três blocos que tinham o problema. Se algum voltar a montar o
// fake-select sem rótulo, o operador perde a referência de novo.
["data-eqidx", "data-maqidx", "data-mdidx"].forEach(function (attr) {
  const re = new RegExp('rotulado\\("Equipamento"[\\s\\S]{0,300}' + attr + '[\\s\\S]{0,400}rotulado\\("Operador"');
  checar("equipamento/operador rotulados no bloco " + attr,
    re.test(htmlCompleto),
    "o bloco " + attr + " voltou a depender do placeholder");
});

checar("os campos numéricos da máquina detalhada têm rótulo",
  /rotulado\(phDinamico\([^)]*"comprimento_m"[^)]*\)/.test(htmlCompleto) &&
  /rotulado\(phDinamico\([^)]*"largura_m"[^)]*\)/.test(htmlCompleto),
  "comprimento/largura seguem só com placeholder -- era o caso que confundiu");

// Envolver os campos num <div> quebraria qualquer seletor que dependesse de
// filho direto. Todos usam descendente; este teste cobra que continue assim.
checar("nenhum handler depende de filho direto (>) para achar os campos",
  !/querySelectorAll\('[^']*(maquina-card|maquina-detalhada-card|eq-pair)[^']*>\s*(input|textarea|\.fake-select)/.test(htmlCompleto),
  "um seletor passou a usar '>' e não encontraria o campo dentro do wrapper");

// ---------------------------------------------------------------------------
// Busca no seletor de tipo de atividade
// ---------------------------------------------------------------------------
// Pedido do Fábio (09/09): são 50+ tipos e rolar a lista em campo é lento.
//
// O componente já tinha filtro -- estava desligado justamente nessa chamada.
// E, ligado, ele ainda não serviria bem: comparava o texto cru, e o catálogo
// tem grafia inconsistente ("Construção de Aterro" com acento, "COMBATE A
// INCENDIO" sem). Quem digitasse "construcao" não acharia o primeiro; quem
// digitasse "incêndio", não acharia o segundo.
console.log("\n--- busca no seletor de tipo de atividade ---\n");

checar("o seletor de tipo de atividade abre COM busca",
  /openSheet\("Tipo de atividade"[\s\S]{0,400}\}, true\)/.test(htmlCompleto),
  "voltou a abrir com o filtro desligado");

const fonteNorm = extrairFuncao("function normalizarBusca", "function filtrarSheetList");
const norm = new Function(fonteNorm + "; return normalizarBusca;")();

[["construcao", "Construção de Aterro", "digitou sem acento, texto com acento"],
 ["incêndio", "COMBATE A INCENDIO", "digitou com acento, texto sem acento"],
 ["ROÇADA", "roçada mecanizada", "caixa alta e cedilha"]
].forEach(function (c) {
  checar("busca acha: " + c[2],
    norm(c[1]).indexOf(norm(c[0])) !== -1,
    '"' + c[0] + '" não encontrou "' + c[1] + '"');
});

checar("o texto de busca de cada opção também é normalizado",
  /data-busca="'\+escAttr\(normalizarBusca\(o\)\)/.test(htmlCompleto),
  "a opção guarda o texto cru: normalizar só a consulta não adianta");

// ---------------------------------------------------------------------------
// A caixa dos campos Equipamento/Operador dentro dos cards
// ---------------------------------------------------------------------------
// Achado medindo o layout em 360px (09/09): o padding/borda/fundo do campo vive
// em `.field .fake-select`, e os cards de equipamento e máquina não ficam dentro
// de um .field. Os dois campos apareciam como texto solto de 21px de altura, ao
// lado de campos de 46px com borda -- e 21px é alvo de toque curto para app de
// campo. Não era regressão dos rótulos: as regras de .fake-select eram idênticas
// antes deles. Estava assim em produção e ninguém tinha reparado.
//
// O teste é sobre o CSS porque é onde o defeito mora: dá para "ter rótulo" e
// mesmo assim o campo não parecer campo.
console.log("\n--- caixa dos campos de equipamento e máquina ---\n");

const cssCompleto = htmlCompleto.match(/<style>([\s\S]*?)<\/style>/)[1];

// Junta as regras que dão caixa (padding + borda), com os seletores de cada uma.
const regrasComCaixa = [];
cssCompleto.replace(/([^{}]+)\{([^}]*)\}/g, function (_, sel, corpo) {
  if (/padding\s*:/.test(corpo) && /border\s*:/.test(corpo)) {
    regrasComCaixa.push(sel.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\s+/g, " "));
  }
  return _;
});
function temCaixa(seletor) {
  return regrasComCaixa.some(function (r) { return r.indexOf(seletor) !== -1; });
}

[".eq-pair .fake-select",
 ".maquina-card .fake-select",
 ".maquina-detalhada-card .fake-select"
].forEach(function (sel) {
  checar("campo com caixa: " + sel,
    temCaixa(sel),
    sel + " não casa nenhuma regra com padding e borda -- o campo volta a 21px");
});

// Regressão: a correção acrescenta contextos, não mexe no campo que já
// funcionava. Se alguém "simplificar" trocando .field pelos novos seletores,
// todo o resto do formulário perde a caixa de uma vez.
checar("o campo de dentro de .field continua com a sua caixa",
  temCaixa(".field .fake-select"),
  "a regra original sumiu -- isso derruba a caixa do resto do formulário");

// ---------------------------------------------------------------------------
// Descrição de atividade (o item de tarifa)
// ---------------------------------------------------------------------------
// Campo novo, vindo da planilha de produtividade: é ele que define o código de
// tarifa e a unidade, e a unidade decide a fórmula da produção consolidada.
//
// O ponto delicado é ONDE a descrição mora. Depende do formulário:
//   padrão de obra      -> uma por apontamento (a.descricao_atividade)
//   máquinas detalhado  -> uma POR MÁQUINA (dados.descricao)
//   hora máquina        -> uma POR MÁQUINA (dados.descricao)
// Errar isso significa a escavadeira em M³ e o caminhão em HT dividirem a
// mesma tarifa -- que é o defeito que estes testes existem para pegar.
console.log("\n--- descrição de atividade (tarifa) ---\n");

checar("o catálogo mapeia a categoria descricao_atividade",
  /descricao_atividade:\s*"descricoesAtividade"/.test(htmlCompleto),
  "sem o mapa, listar_cadastros() traz a lista e o app a ignora em silêncio");

checar("o seletor de descrição abre COM busca",
  /openSheet\("Descrição \(tarifa\)"[\s\S]{0,200}?,\s*true\s*\)/.test(htmlCompleto),
  "108 itens sem busca é inviável em campo");

checar("o payload manda a descrição do apontamento (formulário padrão)",
  /descricao_atividade:\s*a\.descricao_atividade/.test(htmlCompleto),
  "o campo apareceria na tela e nunca chegaria ao banco");

// Um só teste por formulário não basta: o payload monta 'dados' em dois ramos
// separados, e é fácil lembrar de um e esquecer do outro.
//
// A âncora é `var maquinasPayload`, e não `formulario === "..."`: essa
// comparação aparece 5 vezes no arquivo, e a primeira fica em outra função,
// 1500 linhas antes. Ancorado nela, o teste lia o trecho errado e acusava um
// defeito que não existia -- foi o que aconteceu na primeira versão dele.
const iniPayload = htmlCompleto.indexOf("var maquinasPayload");
if (iniPayload === -1) {
  checar("achei o trecho do payload das máquinas", false,
    "a função de payload mudou de forma -- os dois testes abaixo não valem nada sem ela");
}
const trechoPayload = htmlCompleto.slice(iniPayload, iniPayload + 1200);

// INVERTIDO EM 14/09: a descrição saiu de dentro das máquinas.
//
// Ela era por máquina nos dois formulários; agora é UMA, do apontamento, e é
// ela quem escolhe o formulário -- não caberia dentro do formulário que ela
// mesma escolhe. Estes testes fixavam o comportamento antigo e passaram a
// fixar o novo, em vez de serem apagados: é o que impede a volta silenciosa.
["hora_maquina", "maquinas_detalhado"].forEach(function (form) {
  const ini = trechoPayload.indexOf('formulario === "' + form + '"');
  const ramo = trechoPayload.slice(ini, ini + 500);
  checar("o payload NÃO manda descrição por máquina em " + form,
    ini !== -1 && !/descricao:\s*m\.descricao/.test(ramo),
    "voltou a mandar tarifa por máquina -- a descrição do apontamento deixaria de mandar");
});

// Um seletor só, no apontamento, antes da bifurcação dos formulários.
// Conta CHAMADAS, não a definição da função -- contando as duas o teste
// acusava "2 seletores" com o código certo.
const chamadasSeletor = (htmlCompleto.match(/seletorDescricaoHtml\(/g) || []).length -
                        (htmlCompleto.match(/function seletorDescricaoHtml\(/g) || []).length;
checar("existe UM seletor de descrição, no apontamento",
  chamadasSeletor === 1,
  "há " + chamadasSeletor + " chamadas -- com mais de uma, a descrição volta a depender do formulário");

checar("o seletor do apontamento está ligado",
  /sel-descricao-ativ[\s\S]{0,300}?abrirSeletorDescricao/.test(htmlCompleto),
  "o campo abriria a lista e não gravaria, ou nem abriria");

// A descrição precisa ser desenhada ANTES de o formulário ser decidido,
// senão a regra fica circular. Esta é a ordem que garante isso.
const corpoTela = corpoDaFuncao("renderTelaAtividade");
checar("a descrição é desenhada antes de o formulário ser escolhido",
  corpoTela.indexOf("sel-descricao-ativ") < corpoTela.indexOf("formularioDaDescricao("),
  "o formulário é decidido antes do campo que o decide existir na tela");

// Nenhum handler pode continuar procurando o seletor que saiu dos cards --
// código morto que engana quem for ler depois.
checar("não sobrou handler do seletor por máquina",
  !/\.fake-select\[data-campo="descricao"\]/.test(htmlCompleto),
  "ficou fiação apontando para um campo que não existe mais");

// A lista real vem do banco. Uma cópia embutida aqui envelheceria sozinha
// quando a tarifa mudasse, e ninguém perceberia -- o app mostraria itens que
// já não existem.
checar("o catálogo local NÃO traz uma cópia das descrições",
  /descricoesAtividade:\s*\[\s*\]/.test(htmlCompleto),
  "há uma lista embutida: ela vira uma segunda verdade e envelhece sozinha");

// ---------------------------------------------------------------------------
// Ajustes de uso pedidos em 10/09
// ---------------------------------------------------------------------------
console.log("\n--- ajustes de uso (10/09) ---\n");

// A ordem da Identificação é a ordem na tela. O Fábio pediu Contrato depois de
// Tipo de estrada, não em segundo lugar.
const fonteIdent = extrairFuncao("var IDENT_CAMPOS", "// Campos \"comuns\"");
const ordemIdent = (fonteIdent.match(/k:"([a-z_]+)"/g) || []).map(function (s) {
  return s.replace(/k:"|"/g, "");
});
const ordemEsperada = ["cliente", "faena", "tipo_estrada", "contrato", "equipe_frente",
  "fazenda", "data", "encarregado", "supervisor", "tecnico_arauco", "supervisor_arauco"];
checar("os campos de Identificação estão na ordem pedida",
  ordemIdent.join(",") === ordemEsperada.join(","),
  "veio: " + ordemIdent.join(", "));

// O defeito da busca NÃO era o filtro (conferido: acha os 198 itens de todas as
// listas). Era a rolagem, que ficava onde estava enquanto a lista encolhia --
// o item aparecia no topo e a tela mostrava o vazio lá de baixo.
const fonteFiltro = extrairFuncao("function filtrarSheetList", "function closeSheet");
checar("filtrar volta a lista para o topo",
  /scrollTop\s*=\s*0/.test(fonteFiltro),
  "sem isto a busca acha o item e mostra área vazia -- parece que não achou");

// O seletor é ancorado no rodapé, e o teclado do celular ocupa justamente essa
// metade. vh não encolhe com o teclado aberto; visualViewport sabe o tamanho
// que sobrou.
checar("o seletor se ajusta ao teclado pelo visualViewport",
  /visualViewport/.test(htmlCompleto) && /function ajustarSheetAoTeclado/.test(htmlCompleto),
  "sem isto a lista fica atrás do teclado ao digitar na busca");

// O que faltou na primeira tentativa: encolher só o .sheet não adianta.
// Ele é ancorado no FUNDO do overlay (align-items:flex-end), e o overlay é
// inset:0 -- a tela toda, teclado incluído. O sheet ficava menor e no mesmo
// lugar. Quem precisa ser preso à área visível é o OVERLAY.
const fonteAjuste = corpoDaFuncao("ajustarSheetAoTeclado");
checar("é o OVERLAY que é preso à área visível, não só o sheet",
  /overlay\.style\.height\s*=/.test(fonteAjuste) && /overlay\.style\.top\s*=/.test(fonteAjuste),
  "só o sheet encolhe: ele fica menor e continua atrás do teclado");

checar("fechar devolve as medidas do overlay ao CSS",
  /ov\.style\.height\s*=\s*""/.test(fonteAjuste) && /ov\.style\.top\s*=\s*""/.test(fonteAjuste),
  "as medidas do teclado ficariam grudadas na próxima abertura");

// Aqui NÃO dá para usar extrairFuncao com marcador de fim: o texto que segue
// closeSheet (`document.getElementById("sheet-overlay")`) também aparece DENTRO
// dela e mais acima no arquivo, então o marcador casaria antes do começo. É o
// mesmo tipo de armadilha que já fez um teste meu acusar código certo -- aqui
// recorto pelo próprio corpo, contando as chaves.
function corpoDaFuncao(nome) {
  const ini = htmlCompleto.indexOf("function " + nome + "(");
  if (ini === -1) return "";
  let i = htmlCompleto.indexOf("{", ini), nivel = 0;
  for (let j = i; j < htmlCompleto.length; j++) {
    if (htmlCompleto[j] === "{") nivel++;
    else if (htmlCompleto[j] === "}") { nivel--; if (nivel === 0) return htmlCompleto.slice(ini, j + 1); }
  }
  return "";
}

[["openSheet", "o ajuste ao teclado nunca começa"],
 ["closeSheet", "sem soltar no fechamento, a altura calculada com o teclado aberto gruda na próxima abertura"]
].forEach(function (par) {
  checar(par[0] + " aciona o ajuste ao teclado",
    /ajustarSheetAoTeclado\(/.test(corpoDaFuncao(par[0])),
    par[1]);
});

// O aviso de sucesso saiu do rodapé para o canto superior direito, e ganhou cor.
const cssPwa = htmlCompleto.match(/<style>([\s\S]*?)<\/style>/)[1];
const regraToast = (cssPwa.match(/\.toast\{[^}]*\}/) || [""])[0];
checar("o toast fica no topo, à direita",
  /top:/.test(regraToast) && /right:/.test(regraToast) && !/bottom:/.test(regraToast),
  "continua ancorado no rodapé: " + regraToast.slice(0, 90));

const regraToastOk = (cssPwa.match(/\.toast\.ok\{[^}]*\}/) || [""])[0];
checar("existe a variante de sucesso",
  regraToastOk.length > 0,
  "sem a variante, sucesso e erro têm a mesma cara");

// O aviso NÃO pode usar --success-bg: essa variável é rgba(...,.15), pensada
// para o fundo de uma pastilha pequena. Num aviso flutuante ela fica 15%
// pintada e some no que está atrás -- foi exatamente o que aconteceu, e o
// Fábio devolveu na hora ("transparente e praticamente invisível").
checar("o fundo do aviso é sólido, não a cor translúcida do badge",
  !/--success-bg/.test(regraToastOk) && !/rgba\([^)]*0?\.\d+\s*\)/.test(regraToastOk.replace(/box-shadow:[^;]*;/g, "")),
  "voltou a usar cor com transparência: " + regraToastOk.slice(0, 120));

// Contraste medido em ferramentas/medir_toast.js: 5:1 no claro, 8,7:1 no
// escuro. O tema escuro precisa da sua própria regra -- verde escuro sobre
// tela escura destaca pouco, então lá o verde é claro e o texto é escuro.
checar("o tema escuro tem cor própria para o aviso",
  /html\[data-theme="dark"\]\s*\.toast\.ok\{/.test(cssPwa),
  "sem regra própria, o escuro herda a do claro e o contraste cai");

const fonteToast = extrairFuncao("function showToast", "function checkToastIcon");
checar("showToast aceita o tipo sem quebrar quem já chamava com um argumento",
  /function showToast\(msg,\s*tipo\)/.test(fonteToast) && /tipo === "ok"/.test(fonteToast),
  "a assinatura mudou de um jeito que obriga a revisar todas as chamadas");

checar("a sincronização só fica verde quando TUDO subiu",
  /tudoOk\s*\?\s*"ok"\s*:\s*undefined/.test(htmlCompleto),
  "pintar de verde um envio parcial faz o operador achar que acabou");

// ---------------------------------------------------------------------------
// A busca tem que achar o que o TECLADO consegue digitar
// ---------------------------------------------------------------------------
// Defeito real de 10/09: a busca funcionava em "Tipo de atividade" e não em
// "Descrição (tarifa)". A diferença não era a lista nem o filtro -- era o
// CONTEÚDO. O catálogo de tarifas tem "M³" e "M²", e quem procura no celular
// digita "M3": não há ³ no teclado. E tem "SAÍDAS D’ÁGUA" com apóstrofo curvo
// (o Office troca sozinho ao salvar a planilha), enquanto o teclado dá o reto.
console.log("\n--- a busca acha o que o teclado digita ---\n");

// corpoDaFuncao, e NÃO extrairFuncao com marcador de fim: openSheet aparece
// ANTES de normalizarBusca no arquivo, então o marcador casaria antes do
// começo. Terceira vez que essa armadilha aparece nesta suíte -- daqui em
// diante, para recortar função, usar sempre a contagem de chaves.
const buscar = new Function(corpoDaFuncao("normalizarBusca") + "; return normalizarBusca;")();
function achaNaBusca(item, digitado) {
  return buscar(item).indexOf(buscar(String(digitado).trim())) !== -1;
}

[["CONSTRUÇÃO DE ATERRO - M³", "aterro - m3", "M³ procurado como M3"],
 ["AGULHAMENTO - M²", "agulhamento - m2", "M² procurado como M2"],
 ["CONSTRUÇÃO DE SAÍDAS D’ÁGUA - UN", "saidas d'agua", "apóstrofo curvo procurado com o reto"],
 ["TRANSPORTE – DIÁRIA", "transporte - diaria", "travessão procurado como hífen"],
 ["CAMINHÃO CAÇAMBA - HT", "cacamba", "sem cedilha e sem til"],
 ["CONSTRUÇÃO DE ATERRO - M³", "CONSTRUCAO", "maiúscula sem acento"]
].forEach(function (c) {
  checar("busca acha: " + c[2], achaNaBusca(c[0], c[1]),
    JSON.stringify(c[1]) + " não encontrou " + JSON.stringify(c[0]));
});

// NFKD é o que faz ³ virar 3. Com NFD (a versão anterior) o teste acima falha.
checar("a normalização usa NFKD, não NFD",
  /normalize\("NFKD"\)/.test(htmlCompleto),
  "NFD não desfaz ³ nem ² -- foi exatamente o defeito de 10/09");

// Antecipação pedida pelo Fábio: nenhum seletor pode ficar sem filtro, senão
// no dia em que a lista crescer ninguém lembra de voltar aqui.
const semFiltro = [];
let posSheet = 0;
while ((posSheet = htmlCompleto.indexOf("openSheet(", posSheet)) !== -1) {
  if (/function\s+$/.test(htmlCompleto.slice(Math.max(0, posSheet - 12), posSheet))) { posSheet += 10; continue; }
  const abre = htmlCompleto.indexOf("(", posSheet);
  let nivel = 0, fimCh = -1;
  for (let k = abre; k < htmlCompleto.length; k++) {
    if (htmlCompleto[k] === "(") nivel++;
    else if (htmlCompleto[k] === ")") { nivel--; if (nivel === 0) { fimCh = k; break; } }
  }
  if (fimCh === -1) break;
  const ch = htmlCompleto.slice(posSheet, fimCh + 1);
  if (!/,\s*true\s*$/.test(ch.slice(0, -1).trim())) {
    const t = ch.match(/openSheet\(\s*"([^"]*)"/);
    semFiltro.push(t ? t[1] : "(dinâmico)");
  }
  posSheet = fimCh;
}
checar("todo seletor pede filtro, para a busca nascer sozinha se a lista crescer",
  semFiltro.length === 0,
  "sem filtro: " + semFiltro.join(", "));

// ---------------------------------------------------------------------------
// DMT: vem da descrição, não do teclado
// ---------------------------------------------------------------------------
// O campo DMT existia e NUNCA aparecia: estava condicionado a
// `tipo === "Transporte de Material"` e o catálogo entrega "TRANSPORTE DE
// MATERIAL" em maiúsculas. Foi removido em vez de consertado -- o DMT já está
// escrito na descrição da tarifa ("TRANSPORTE DE BRITA (DMT 35 - 40 km) - M³"),
// e cada faixa é uma tarifa com código próprio. Digitar um DMT à parte criaria
// dois números para a mesma distância, com chance de divergirem.
console.log("\n--- DMT derivado da descrição ---\n");

const extrairDmt = new Function(corpoDaFuncao("dmtDaDescricao") + "; return dmtDaDescricao;")();

[["TRANSPORTE DE BRITA (DMT 35 - 40 km) - M³", "35 - 40 km"],
 ["TRANSPORTE DE SOLOS (DMT 0 - 2,5 km) - M³", "0 - 2,5 km"],
 ["TRANSPORTE DE BRITA (DMT 100 - 125 km) - M³", "100 - 125 km"],
 ["TRANSPORTE DE SOLOS (DMT 12,5 - 15 km) - M³", "12,5 - 15 km"]
].forEach(function (c) {
  checar("extrai a faixa de " + JSON.stringify(c[1]),
    extrairDmt(c[0]) === c[1],
    "veio " + JSON.stringify(extrairDmt(c[0])));
});

// Descrição sem DMT não pode inventar um campo vazio na tela.
[["CONSTRUÇÃO DE ATERRO - M³"], ["CAMINHÃO CAÇAMBA - HT"], [""], [null]].forEach(function (c) {
  checar("descrição sem DMT não produz campo: " + JSON.stringify(c[0]),
    extrairDmt(c[0]) === null,
    "inventou " + JSON.stringify(extrairDmt(c[0])));
});

// Olha DENTRO da função, não num raio de caracteres a partir do nome dela.
// A primeira versão fazia isso e acusava "voltou a ser digitável" -- porque
// logo depois da CHAMADA vem o campo UP, que tem <input>. Nada a ver com o DMT.
const corpoDmt = corpoDaFuncao("camposDerivadosHtml");
checar("o campo de DMT é de leitura, sem input",
  /campo-derivado/.test(corpoDmt) && !/<input/.test(corpoDmt),
  "voltou a ser digitável -- aí passam a existir dois DMT para a mesma distância");

// Antes havia uma segunda função só para os cards de máquina, porque lá a
// descrição era por máquina. Com uma descrição só, por apontamento, ela virou
// código morto e foi removida (14/09). Os derivados agora saem uma vez, junto
// da descrição, valendo para os três formulários.
checar("os derivados são desenhados junto da descrição do apontamento",
  /sel-descricao-ativ[\s\S]{0,300}?camposDerivadosHtml\(a\.descricao_atividade\)/.test(htmlCompleto),
  "os parâmetros da descrição sumiram da tela");

checar("a função morta dos cards não voltou",
  !/camposDerivadosCardHtml/.test(htmlCompleto.replace(/\/\/[^\n]*/g, "")),
  "camposDerivadosCardHtml voltou a ser usada -- ela pressupõe descrição por máquina");

// --- os outros parâmetros embutidos na descrição ---------------------------
// Mapeados nas 108 do catálogo: DMT (35), Nível (21), Espessura (4),
// Classificação (2). A unidade não é extraída do texto -- vem do de-para.
const extrairParams = new Function(
  "REGRAS",
  corpoDaFuncao("dmtDaDescricao") +
  htmlCompleto.slice(htmlCompleto.indexOf("var PARAMETROS_DESCRICAO"),
                     htmlCompleto.indexOf("function parametrosDaDescricao")) +
  corpoDaFuncao("parametrosDaDescricao") +
  "; return parametrosDaDescricao;")({});

function paramsDe(desc, unidade) {
  const lista = extrairParams(desc, unidade);
  const m = {};
  lista.forEach(function (p) { m[p.rotulo] = p.valor; });
  return m;
}

[["CONSTRUÇÃO DE MINI CURVA - NÍVEL 3 - UN", "Nível", "3"],
 ["DERRUBADA DE ARVORE - NIVEL 1 - M²", "Nível", "1"],              // sem acento
 ["RECUPERAÇÃO DE JAZIDA – NÍVEL 1 - M³", "Nível", "1"],            // travessão
 ["PREPARO DE LEITO COM SOLO NÍVEL 1 (25cm) - M³", "Espessura", "25 cm"],
 ["CONSTRUÇÃO DE CAMALHÃO/MURCHÃO - NÍVEL 1 (SECUNDÁRIA) - UN", "Classificação", "SECUNDÁRIA"]
].forEach(function (c) {
  const v = paramsDe(c[0])[c[1]];
  checar("extrai " + c[1] + " = " + JSON.stringify(c[2]), v === c[2], "veio " + JSON.stringify(v));
});

// A armadilha que só apareceu ao varrer o catálogo: MOTONIVELADORA contém
// "NIVEL". Um regex ingênuo daria a três descrições um campo "Nível" que não
// existe -- e ninguém desconfiaria de um campo que parece plausível.
["MOTONIVELADORA - DIÁRIA", "MOTONIVELADORA - HT", "MOTONIVELADORA - HD"].forEach(function (d) {
  checar("MOTONIVELADORA não vira Nível: " + d,
    paramsDe(d)["Nível"] === undefined,
    "inventou Nível = " + paramsDe(d)["Nível"]);
});

// Uma descrição com vários parâmetros mostra todos, na ordem.
const varios = extrairParams("PREPARO DE LEITO COM SOLO NÍVEL 1 (25cm) - M³", "M³");
checar("uma descrição com vários parâmetros devolve todos",
  varios.length === 4 &&
  varios.map(function (p) { return p.rotulo; }).join(",") === "Nível,Espessura,Unidade" ||
  varios.map(function (p) { return p.rotulo; }).join(",") === "Nível,Espessura,Unidade",
  "veio: " + varios.map(function (p) { return p.rotulo + "=" + p.valor; }).join(" | "));

// A unidade tem que vir do de-para, não do sufixo do nome. São a mesma coisa
// em 108 de 108 hoje -- e é por isso que só uma pode ser a fonte: se um dia
// divergirem, quem manda é a tarifa.
checar("a unidade vem do de-para, não do texto da descrição",
  /REGRAS\.tarifa_descricao/.test(corpoDaFuncao("unidadeDaDescricao")) &&
  !/match|slice|split/.test(corpoDaFuncao("unidadeDaDescricao")),
  "está extraindo a unidade do nome: vira um segundo caminho para o mesmo dado");

checar("o campo DMT digitável foi mesmo removido",
  !/k:"dmt_km_inicial"/.test(htmlCompleto) && !/k:"dmt_km_final"/.test(htmlCompleto),
  "o campo antigo voltou: ele nunca aparecia, e agora duplicaria o derivado");

// ---------------------------------------------------------------------------
// A regra de formulário é achada mesmo se a grafia do nome mudou
// ---------------------------------------------------------------------------
// Defeito que estava EM PRODUÇÃO, achado em 10/09 a partir de uma pergunta do
// Fábio sobre o campo DMT. O painel grava a regra usando o NOME da atividade
// como chave, com o nome que ela tinha naquele dia. Quatro regras foram feitas
// em 02/09, quando o cadastro usava grafia mista; depois o catálogo foi
// recadastrado em maiúsculas e as regras ficaram órfãs.
//
// Três atividades caíam no formulário PADRÃO: quem escolhia "Hora Máquina
// Trabalhada" recebia comprimento/largura/profundidade em vez de máquinas com
// horas. Sem erro nenhum na tela -- só o formulário errado.
console.log("\n--- formulário achado apesar da grafia ---\n");

function formularioCom(regras, tipo) {
  return new Function("REGRAS",
    corpoDaFuncao("normalizarBusca") + corpoDaFuncao("valorTolerante") + corpoDaFuncao("formularioDaAtividade") +
    "; return formularioDaAtividade;")({ formulario_atividade: regras })(tipo);
}

// Os três casos reais que estavam quebrados.
[["Hora Máquina Trabalhada", "hora_maquina", "HORA MAQUINA TRABALHADA", "caixa + acento"],
 ["Abertura de Estrada", "maquinas_detalhado", "ABERTURA DE ESTRADA", "só caixa"],
 ["Patrolamento", "maquinas_detalhado", "PATROLAMENTO", "só caixa"]
].forEach(function (c) {
  const regras = {}; regras[c[0]] = c[1];
  checar("acha a regra de " + JSON.stringify(c[2]) + " (" + c[3] + ")",
    formularioCom(regras, c[2]) === c[1],
    "veio " + formularioCom(regras, c[2]) + " -- o operador receberia o formulário errado");
});

// Sem regra nenhuma continua caindo no padrão, que é o comportamento de sempre
// para as atividades de obra.
checar("atividade sem regra continua no padrão",
  formularioCom({ "OUTRA COISA": "hora_maquina" }, "CONSTRUCAO DE ATERRO") === "padrao",
  "inventou um formulário para quem não tem regra");

// O EXATO tem que ganhar do aproximado. Se um dia existirem duas atividades que
// só diferem por acento, cada uma com sua regra, a correspondência exata é a
// que vale -- senão a ordem das chaves decidiria, o que é aleatório.
checar("correspondência exata vence a aproximada",
  formularioCom({ "PATROLAMENTO": "padrao", "Patrolamento": "hora_maquina" }, "PATROLAMENTO") === "padrao",
  "o aproximado ganhou do exato: aí quem decide é a ordem das chaves");

// ---------------------------------------------------------------------------
// Texto de ajuda dentro de um campo não pode subir por cima dele
// ---------------------------------------------------------------------------
// .helper-text tem margin-top:-6px, que existe para colar a ajuda a um bloco
// que JÁ tem margem inferior. Dentro de um .field ela vem logo depois do
// campo, que não tem margem -- e o texto subia 6px por cima do seletor.
// Medido no arquivo real: seletor terminando em 82px, texto começando em 76px.
// Apareceu nos campos de Descrição (tarifa) e nos derivados, os primeiros a
// pôr ajuda dentro de um .field.
console.log("\n--- ajuda dentro do campo ---\n");

const regraAjudaNoField = (cssPwa.match(/\.field\s*>\s*\.helper-text\{[^}]*\}/) || [""])[0];
checar("existe regra própria para ajuda dentro de .field",
  regraAjudaNoField.length > 0,
  "sem ela vale o margin-top:-6px do .helper-text, que sobrepõe o campo");

checar("essa regra anula a margem negativa",
  /margin-top:\s*[0-9]/.test(regraAjudaNoField) && !/margin-top:\s*-/.test(regraAjudaNoField),
  "a margem continua negativa: " + regraAjudaNoField);

// O -6px do .helper-text geral continua valendo -- ele está certo onde a ajuda
// vem depois de um bloco com margem. Mexer nele consertaria um caso e
// estragaria os outros.
checar("o .helper-text geral segue com a margem negativa",
  /\.helper-text\{[^}]*margin:\s*-6px/.test(cssPwa),
  "mudaram a regra geral: isso desloca todas as outras ajudas do app");

// ---------------------------------------------------------------------------
// Trecho é texto livre, e continua obedecendo às Configurações
// ---------------------------------------------------------------------------
// Não existe cadastro de trechos -- o catálogo tem duas entradas de exemplo.
// Uma lista com duas opções obriga o operador a escolher uma que não é a dele.
// Aqui roda camposAtividade DE VERDADE, com stubs, em vez de conferir a grafia
// da linha: o que importa é o campo que sai, não como ele foi escrito.
console.log("\n--- Trecho como texto livre ---\n");

const montarCampos = new Function(
  // As quatro reais: camposAtividade decide pela descrição desde 14/09,
  // formularioDaDescricao cai em formularioDaAtividade como reserva, e desde
  // 16/09 camposAtividade filtra por campoVisivelParaDescricao no fim.
  corpoDaFuncao("normalizarBusca") + corpoDaFuncao("valorTolerante") +
  corpoDaFuncao("formularioDaAtividade") + corpoDaFuncao("formularioDaDescricao") +
  blocoVar("NOME_REGRA_CAMPO") + corpoDaFuncao("campoVisivelParaDescricao") +
  "; var REGRAS = { formulario_atividade: {}, formulario_descricao: {}, campos_ocultos_descricao: {} };" +
  // reqDinamico é o que a tela de Configurações alimenta; o stub devolve o que
  // mandarem, para dar pra provar que a configuração continua chegando ao campo
  "; var obrigatorio = false;" +
  "; function reqDinamico(){ return obrigatorio; }" +
  "; var CATALOGO = { trechos: ['CAP-05','106'] };" +
  corpoDaFuncao("camposAtividade") +
  "; return function(req){ obrigatorio = req; return camposAtividade('PATROLAMENTO',''); };"
)();

const trechoOpcional = montarCampos(false).filter(function (c) { return c.k === "trecho"; })[0];
const trechoObrigatorio = montarCampos(true).filter(function (c) { return c.k === "trecho"; })[0];

checar("o campo Trecho continua existindo no formulário padrão",
  !!trechoOpcional, "sumiu do formulário");

checar("Trecho é campo de digitar, não lista",
  trechoOpcional && trechoOpcional.t === "text",
  "veio como " + (trechoOpcional && trechoOpcional.t));

checar("Trecho não carrega mais a lista de opções",
  trechoOpcional && !trechoOpcional.opts,
  "ainda tem opts -- o seletor voltaria a abrir");

// A queixa do Fábio foi explícita: muda o jeito de preencher, NÃO a regra.
checar("a configuração de obrigatoriedade continua chegando ao Trecho",
  trechoOpcional && trechoOpcional.req === false && trechoObrigatorio && trechoObrigatorio.req === true,
  "req deixou de vir de reqDinamico: opcional=" +
    (trechoOpcional && trechoOpcional.req) + ", obrigatório=" + (trechoObrigatorio && trechoObrigatorio.req));

// campoHtml só desenha input de digitar para t:"text", e o fio que salva o que
// foi digitado procura input.campo-texto[data-k] -- sem essa classe, o operador
// digita e nada é gravado.
checar("campoHtml desenha input.campo-texto para t:\"text\"",
  /campo\.t === "text"[\s\S]{0,240}?class="campo-texto"/.test(corpoDaFuncao("campoHtml")),
  "o ramo de texto não produz a classe que o wireCampoTexto procura");

// ---------------------------------------------------------------------------
// Dimensão (m): campo novo que NÃO pode nascer obrigatório
// ---------------------------------------------------------------------------
// Este sistema torna obrigatório todo campo sem regra gravada. Um campo novo
// não tem regra -- então nasceria exigido em todo apontamento, e travaria o
// envio de quem está na estrada por causa de algo que ninguém decidiu ainda
// para que serve. É a mesma armadilha do NOT NULL do arquivo 1.
console.log("\n--- Dimensão (m) ---\n");

// Recorta `var NOME = {...};` contando chaves -- pelo mesmo motivo de
// corpoDaFuncao: marcador de fim casa no lugar errado.
// Serve para objeto ({...}) e para lista ([...]): IDENT_CAMPOS é um array, e a
// primeira versão só reconhecia objeto -- devolvia "" e o teste estourava com
// "IDENT_CAMPOS is not defined", que não diz nada sobre a causa.
function blocoVar(nome) {
  const ini = htmlCompleto.indexOf("var " + nome + " = ");
  if (ini === -1) return "";
  const abre = htmlCompleto[htmlCompleto.indexOf("=", ini) + 2] === "[" ? "[" : "{";
  const fecha = abre === "[" ? "]" : "}";
  let i = htmlCompleto.indexOf(abre, ini), nivel = 0;
  for (let j = i; j < htmlCompleto.length; j++) {
    if (htmlCompleto[j] === abre) nivel++;
    else if (htmlCompleto[j] === fecha) { nivel--; if (nivel === 0) return htmlCompleto.slice(ini, j + 1) + ";"; }
  }
  return "";
}

// Harness com as funções REAIS de obrigatoriedade, e REGRAS trocável -- é a
// interação entre elas que importa, não o texto de cada uma.
const obrigatoriedade = new Function(
  "var REGRAS = {};" +
  blocoVar("PADRAO_OBRIGATORIEDADE") +
  corpoDaFuncao("campoObrigatorioPara") +
  blocoVar("NOME_REGRA_CAMPO") +
  corpoDaFuncao("reqDinamico") +
  "; return function(regras, cliente, atividade, campo){ REGRAS = regras; return reqDinamico(cliente, atividade, campo); };"
);
const req = obrigatoriedade();

checar("sem regra nenhuma, Dimensão nasce OPCIONAL",
  req({}, "ARAUCO", "PATROLAMENTO", "dimensao_m") === false,
  "nasceu obrigatória -- todo apontamento em campo travaria nela");

// O padrão dos outros campos não pode ter mudado junto.
checar("os campos antigos seguem obrigatórios por padrão",
  req({}, "ARAUCO", "PATROLAMENTO", "comprimento_m") === true &&
  req({}, "ARAUCO", "PATROLAMENTO", "up") === true,
  "o padrão geral virou opcional -- isso afrouxa o app inteiro");

// A flag do painel manda, e manda nos DOIS sentidos: é o pedido do Fábio
// ("o campo deve receber configuração com a flag nos campos obrigatórios por
// cliente"). Padrão só decide quando não há regra.
checar("marcar a flag por cliente torna Dimensão obrigatória",
  req({ campo_obrigatorio: { "ARAUCO:Dimensão": true } }, "ARAUCO", "PATROLAMENTO", "dimensao_m") === true,
  "a regra do painel foi ignorada -- a flag não serviria para nada");

checar("a regra por atividade vence a regra geral do cliente",
  req({ campo_obrigatorio: { "ARAUCO:Dimensão": true, "ARAUCO:PATROLAMENTO:Dimensão": false } },
      "ARAUCO", "PATROLAMENTO", "dimensao_m") === false,
  "a específica não venceu a geral");

checar("desmarcar a flag em outro cliente não afeta este",
  req({ campo_obrigatorio: { "SUZANO:Dimensão": true } }, "ARAUCO", "PATROLAMENTO", "dimensao_m") === false,
  "regra de um cliente vazou para outro");

// O campo em si, no formulário padrão, na posição pedida.
const camposPadrao = montarCampos(false);
const iDim = camposPadrao.map(function (c) { return c.k; }).indexOf("dimensao_m");

checar("Dimensão existe no formulário Padrão (obra)",
  iDim !== -1, "o campo não aparece em camposAtividade");

// O UP é desenhado ANTES desta lista, então "primeiro da lista" é o mesmo que
// "logo abaixo do UP" na tela -- que foi o pedido.
checar("Dimensão vem logo depois do UP (é o primeiro da lista)",
  iDim === 0,
  "está na posição " + iDim + ", depois de " + camposPadrao.slice(0, iDim).map(function (c) { return c.l; }).join(", "));

// "Primeiro da lista" só significa "logo abaixo do UP" enquanto o UP for
// desenhado ANTES da lista. Esse elo mora em renderTelaAtividade, não em
// camposAtividade -- e sem checá-lo os testes acima aprovariam um campo que
// aparece no lugar errado na tela.
const corpoRender = corpoDaFuncao("renderTelaAtividade");
const posUp = corpoRender.indexOf('data-k="up"');
const posLista = corpoRender.indexOf("campos.forEach");
checar("o UP é desenhado antes da lista de campos",
  posUp !== -1 && posLista !== -1 && posUp < posLista,
  "UP em " + posUp + ", lista em " + posLista + " -- a ordem na tela não é a da lista");

checar("Dimensão é numérica, com o rótulo em metros",
  iDim !== -1 && camposPadrao[iDim].t === "number" && /\(m\)/.test(camposPadrao[iDim].l),
  "veio como t=" + (camposPadrao[iDim] || {}).t + ", rótulo " + (camposPadrao[iDim] || {}).l);

// Sem isto o operador digita, o app guarda no aparelho, e o número nunca sai
// de lá -- a pior das três situações, porque parece que funcionou.
checar("a dimensão vai no payload da sincronização",
  /dimensao_m:\s*a\.dimensao_m/.test(htmlCompleto),
  "o campo não é enviado ao servidor");

// Os dois lados precisam concordar sobre o padrão, senão o painel mostra
// marcado e o aparelho trata como opcional.
const htmlPainel = fs.readFileSync(
  path.join(__dirname, "..", "..", "..", "Painel", "index.html"), "utf8");

// A segunda metade deste teste olhava CAMPOS_POR_FORMULARIO, que saiu em
// 14/09 junto com "formulário por atividade": a matriz não filtra mais por
// formulário, porque a atividade deixou de ter um.
checar("o Painel oferece a flag de Dimensão por cliente",
  /CAMPOS_CONFIGURAVEIS\s*=\s*\[[^\]]*"Dimensão"/.test(htmlPainel),
  "o campo não aparece na matriz de Configurações");

// Procura DECLARAÇÃO e USO, não a palavra: o comentário que explica a remoção
// cita o nome, e um teste pela palavra solta acusaria o próprio comentário.
checar("a matriz de obrigatoriedade não filtra por formulário",
  !/var\s+CAMPOS_POR_FORMULARIO/.test(htmlPainel) && !/CAMPOS_POR_FORMULARIO\s*\[/.test(htmlPainel),
  "voltou a filtrar: atividade sem regra esconderia Hora Inicial/Final da configuração");

checar("o Painel usa o MESMO padrão do PWA (desmarcada)",
  /PADRAO_OBRIGATORIEDADE\s*=\s*\{[^}]*"Dimensão":\s*false/.test(htmlPainel),
  "os dois lados discordam do padrão -- tela e aparelho vão divergir");

// Procurar só por "a.dimensao_m" não serve: desligando a condição que decide
// se o bloco aparece, a string continua no arquivo e o teste passava com o
// campo invisível na tela. Descoberto sabotando -- é para isso que a sabotagem
// existe. O que amarra de verdade é o rótulo colado ao valor.
checar("o Painel mostra a dimensão no detalhe do apontamento",
  /a\.dimensao_m\s*!=\s*null\s*\?[\s\S]{0,160}?<label>Dimensão<\/label>[\s\S]{0,120}?a\.dimensao_m/.test(htmlPainel),
  "o número chegaria ao banco e ninguém o veria");

// ---------------------------------------------------------------------------
// Fazenda também é texto livre
// ---------------------------------------------------------------------------
// Mesmo motivo do Trecho: o cadastro tem duas fazendas de exemplo e a Arauco
// tem muito mais. Lista curta demais obriga o encarregado a escolher a fazenda
// errada -- e fazenda errada contamina o relatório inteiro, não um campo só.
console.log("\n--- Fazenda como texto livre ---\n");

const identCampos = new Function(
  "var CATALOGO = { clientes:[], tiposEstrada:[], contratos:[], equipesFrente:[], fazendas:['ELO DOURADO 2'], encarregados:[], supervisores:[], tecnicosArauco:[], supervisoresArauco:[] };" +
  blocoVar("IDENT_CAMPOS") + "; return IDENT_CAMPOS;"
)();
const campoFazenda = identCampos.filter(function (c) { return c.k === "fazenda"; })[0];

checar("Fazenda continua na Identificação",
  !!campoFazenda, "o campo sumiu de IDENT_CAMPOS");

checar("Fazenda é campo de digitar, não lista",
  campoFazenda && campoFazenda.t === "text",
  "veio como " + (campoFazenda && campoFazenda.t));

checar("Fazenda não carrega mais a lista de opções",
  campoFazenda && !campoFazenda.opts,
  "ainda tem opts -- o seletor voltaria a abrir");

// Fazenda é o que identifica o RDO na lista e no painel. Continua obrigatória:
// virar texto livre muda COMO se preenche, não SE é preciso preencher.
checar("Fazenda segue obrigatória",
  campoFazenda && campoFazenda.req === true,
  "deixou de ser obrigatória -- daria para enviar RDO sem fazenda");

// O fio que salva o que foi digitado na Identificação procura esta classe.
// Sem ele o encarregado digita a fazenda e o RDO é enviado sem ela.
checar("a Identificação fia os campos de texto",
  /#main input\.campo-texto\[data-k\]/.test(corpoDaFuncao("ligarEventosSecao")),
  "ligarEventosSecao não liga input.campo-texto -- o que for digitado não é guardado");

// Os dois campos que o Fábio pediu como texto livre, juntos: se alguém
// reverter um deles, esta linha acusa sem depender dos blocos acima.
const trechoPadrao = montarCampos(false).filter(function (c) { return c.k === "trecho"; })[0];
checar("Trecho e Fazenda são os dois texto livre",
  trechoPadrao && trechoPadrao.t === "text" && campoFazenda && campoFazenda.t === "text",
  "trecho=" + (trechoPadrao && trechoPadrao.t) + ", fazenda=" + (campoFazenda && campoFazenda.t));

// ---------------------------------------------------------------------------
// O formulário vem da DESCRIÇÃO, não do tipo de atividade (14/09)
// ---------------------------------------------------------------------------
// Medido nas 2.126 linhas da planilha: um tipo reúne descrições que pedem
// formulários diferentes. Em DRENAGENS IMPLANTAÇÃO convivem CONSTRUÇÃO DE
// MINI CURVA (quantidade e área, 560 linhas) e PÁ CARREGADEIRA - HT (só
// horas, 46 linhas). Um seletor por tipo não cobria os dois.
console.log("\n--- formulário pela descrição ---\n");

const decidirFormulario = new Function(
  "var REGRAS = {};" +
  corpoDaFuncao("normalizarBusca") + corpoDaFuncao("valorTolerante") +
  corpoDaFuncao("formularioDaAtividade") + corpoDaFuncao("formularioDaDescricao") +
  "; return function(regras, descricao, tipo){ REGRAS = regras; return formularioDaDescricao(descricao, tipo); };"
)();

const REGRAS_REAIS = {
  formulario_descricao: {
    "PÁ CARREGADEIRA - HT": "hora_maquina",
    "CONSTRUÇÃO DE MINI CURVA - NÍVEL 2 - UN": "padrao",
    "CONSTRUÇÃO DE ATERRO - M³": "maquinas_detalhado"
  },
  formulario_atividade: { "DRENAGENS IMPLANTACAO": "maquinas_detalhado" }
};

// O caso que motivou a mudança: MESMO tipo, formulários diferentes.
checar("mesmo tipo, descrições diferentes -> formulários diferentes",
  decidirFormulario(REGRAS_REAIS, "PÁ CARREGADEIRA - HT", "DRENAGENS IMPLANTACAO") === "hora_maquina" &&
  decidirFormulario(REGRAS_REAIS, "CONSTRUÇÃO DE MINI CURVA - NÍVEL 2 - UN", "DRENAGENS IMPLANTACAO") === "padrao",
  "o tipo ainda está mandando -- era exatamente isso que não cobria a planilha");

// A descrição vence o tipo. Sem isso a mudança não teria efeito nenhum.
checar("a descrição vence a regra do tipo",
  decidirFormulario(REGRAS_REAIS, "PÁ CARREGADEIRA - HT", "DRENAGENS IMPLANTACAO") === "hora_maquina",
  "o tipo dizia maquinas_detalhado e prevaleceu");

// Reserva: os apontamentos gravados antes de 14/09 não têm descrição. Sem
// isso, todos cairiam no padrão -- inclusive os de hora-máquina, que
// perderiam a lista de máquinas na tela.
checar("sem descrição, vale a regra antiga do tipo",
  decidirFormulario(REGRAS_REAIS, "", "DRENAGENS IMPLANTACAO") === "maquinas_detalhado",
  "apontamento antigo perderia o formulário dele");

checar("sem descrição e sem regra de tipo, é o padrão",
  decidirFormulario(REGRAS_REAIS, "", "ATIVIDADE QUE NINGUÉM CONFIGUROU") === "padrao",
  "nada pode travar por falta de configuração");

// Descrição com regra ausente também cai na reserva, não em erro.
checar("descrição sem regra cai na reserva do tipo",
  decidirFormulario(REGRAS_REAIS, "DESCRIÇÃO QUE NÃO EXISTE", "DRENAGENS IMPLANTACAO") === "maquinas_detalhado",
  "descrição desconhecida deveria cair na reserva");

// A tolerância a grafia vale para o mapa novo também -- foi por grafia que
// três atividades entregaram o formulário errado em produção.
checar("acha a regra da descrição apesar de caixa e acento",
  decidirFormulario({ formulario_descricao: { "PÁ CARREGADEIRA - HT": "hora_maquina" } },
                    "pa carregadeira - ht", "") === "hora_maquina",
  "a busca tolerante não está sendo aplicada ao mapa de descrições");

// M³ digitado como M3 -- o mesmo defeito que já apareceu na busca do seletor.
checar("acha a regra mesmo com M3 no lugar de M³",
  decidirFormulario({ formulario_descricao: { "CONSTRUÇÃO DE ATERRO - M³": "maquinas_detalhado" } },
                    "CONSTRUCAO DE ATERRO - M3", "") === "maquinas_detalhado",
  "NFKD não está sendo aplicado -- M³ e M3 seriam chaves diferentes");

// --- o mapeamento opcional atividade -> descrições foi REMOVIDO (16/09) ----
// Existiu de 14/09 a 16/09: "para o dia em que o Fábio quisesse amarrar".
// Ele decidiu que não faz sentido na aplicação e pediu a remoção -- ninguém
// tinha configurado nenhuma linha. Estes testes fixavam o comportamento
// antigo; agora confirmam que ele NÃO VOLTOU, no PWA e no Painel.
console.log("\n--- mapeamento atividade -> descrições (removido em 16/09) ---\n");

checar("descricoesDisponiveis() não existe mais no PWA",
  !/function descricoesDisponiveis/.test(htmlCompleto),
  "a função voltou -- o mapeamento foi religado sem pedido");

checar("abrirSeletorDescricao() sempre abre a lista inteira do catálogo",
  /openSheet\("Descrição \(tarifa\)",\s*CATALOGO\.descricoesAtividade,/.test(htmlCompleto),
  "não está usando CATALOGO.descricoesAtividade direto -- pode ter voltado a filtrar");

checar("REGRAS.descricoes_da_atividade não é mais lido em lugar nenhum",
  !/REGRAS\.descricoes_da_atividade/.test(htmlCompleto),
  "algum trecho ainda lê a regra removida");

checar("o Painel não grava mais o mapeamento",
  !/salvarRegra\("descricoes_da_atividade"/.test(htmlPainel),
  "a tela ainda grava a regra removida");

// Busca o TÍTULO renderizado, não qualquer menção -- o comentário que explica
// a remoção cita o nome antigo, e pegar texto solto acusaria o próprio
// comentário (só apareceu ao rodar: a primeira versão deste teste falhava
// assim, com o código já certo).
checar("a seção 'Descrições por atividade' saiu da tela de Configurações",
  !/>Descrições por atividade/.test(htmlPainel) && !/config-mapa-atividade/.test(htmlPainel),
  "o título ou o seletor da seção removida ainda está no HTML");

// --- o Painel, que não tem suíte própria ------------------------------------
checar("o Painel configura o formulário por descrição",
  /salvarRegra\("formulario_descricao"/.test(htmlPainel) &&
  /valorRegra\("formulario_descricao"/.test(htmlPainel),
  "a tela de Configurações não grava nem lê a regra nova");

checar("o seletor de formulário por atividade saiu do Painel",
  !/salvarRegra\("formulario_atividade"/.test(htmlPainel),
  "ainda dá para configurar por atividade -- duas fontes de verdade para a mesma decisão");

// 108 linhas sem busca é uma tabela que ninguém usa.
checar("a tabela de descrições tem busca",
  /config-busca-descricao/.test(htmlPainel) && /normalizarBuscaPainel/.test(htmlPainel),
  "108 descrições sem filtro");

// ---------------------------------------------------------------------------
// Campos visíveis por descrição (16/09)
// ---------------------------------------------------------------------------
// Eixo diferente de obrigatoriedade: aqui a configuração decide se o campo
// APARECE, não se ele trava vazio. O risco central, e por isso o teste mais
// importante deste bloco: um campo ESCONDIDO nunca pode continuar sendo
// cobrado como obrigatório -- seria a mesma armadilha do NOT NULL do
// arquivo 1 (08/09), um requisito sem caminho de atender.
console.log("\n--- campos visíveis por descrição ---\n");

const visivel = new Function(
  "var REGRAS = {};" +
  corpoDaFuncao("normalizarBusca") + corpoDaFuncao("valorTolerante") +
  blocoVar("NOME_REGRA_CAMPO") + corpoDaFuncao("campoVisivelParaDescricao") +
  "; return function(regras, descricao, chaveInterna){ REGRAS = regras; return campoVisivelParaDescricao(descricao, chaveInterna); };"
)();

checar("sem regra nenhuma, o campo aparece",
  visivel({}, "CONSTRUÇÃO DE ATERRO - M³", "profundidade_cm") === true,
  "escondeu sem ninguém configurar nada");

checar("regra com o campo na lista esconde",
  visivel({ campos_ocultos_descricao: { "CONSTRUÇÃO DE ATERRO - M³": ["Profundidade"] } },
          "CONSTRUÇÃO DE ATERRO - M³", "profundidade_cm") === false,
  "o campo continuou aparecendo apesar da regra");

checar("regra vazia não esconde nada (mesmo princípio de descricoes_da_atividade)",
  visivel({ campos_ocultos_descricao: { "CONSTRUÇÃO DE ATERRO - M³": [] } },
          "CONSTRUÇÃO DE ATERRO - M³", "profundidade_cm") === true,
  "lista vazia escondeu o campo -- deveria ser o mesmo que não configurar");

checar("esconder um campo não esconde os outros da mesma descrição",
  visivel({ campos_ocultos_descricao: { "CONSTRUÇÃO DE ATERRO - M³": ["Profundidade"] } },
          "CONSTRUÇÃO DE ATERRO - M³", "comprimento_m") === true,
  "Comprimento sumiu junto -- o filtro não é por campo");

checar("a regra de uma descrição não vaza para outra",
  visivel({ campos_ocultos_descricao: { "OUTRA DESCRIÇÃO": ["Profundidade"] } },
          "CONSTRUÇÃO DE ATERRO - M³", "profundidade_cm") === true,
  "regra de outra descrição escondeu aqui");

checar("busca tolerante também vale aqui (mesmo defeito de grafia já corrigido antes)",
  visivel({ campos_ocultos_descricao: { "construcao de aterro - m3": ["Profundidade"] } },
          "CONSTRUÇÃO DE ATERRO - M³", "profundidade_cm") === false,
  "NFKD não aplicado -- M³ e M3/maiúscula deveriam casar");

checar("campo sem nome de negócio (equipamento, operador) nunca é escondível",
  visivel({ campos_ocultos_descricao: { X: ["Equipamento"] } }, "X", "equipamento") === true,
  "um campo estrutural virou escondível");

// camposAtividade() de verdade: confirma que o filtro chega ao array que a
// tela desenha E que valida o formulário, não só à função isolada.
const camposComOcultos = new Function(
  "var REGRAS = {};" +
  corpoDaFuncao("normalizarBusca") + corpoDaFuncao("valorTolerante") +
  corpoDaFuncao("formularioDaAtividade") + corpoDaFuncao("formularioDaDescricao") +
  blocoVar("NOME_REGRA_CAMPO") + corpoDaFuncao("campoVisivelParaDescricao") +
  "; function reqDinamico(){ return false; }" +
  "; var CATALOGO = {};" +
  corpoDaFuncao("camposAtividade") +
  "; return function(regras, descricao){ REGRAS = regras; return camposAtividade('PATROLAMENTO','',descricao); };"
)();

const camposComTudoOculto = camposComOcultos(
  { campos_ocultos_descricao: { X: ["Profundidade", "Comprimento", "Largura", "Trecho", "Dimensão"] } }, "X"
).map(function (c) { return c.k; });
checar("camposAtividade() de fato remove os campos escondidos do array",
  camposComTudoOculto.length === 1 && camposComTudoOculto[0] === "observacao",
  "sobrou: " + JSON.stringify(camposComTudoOculto) + " -- só Observação deveria restar");

// O ponto que mais importa: escondido + marcado obrigatório = nunca cobrado.
const harnessValidar = new Function(
  "var REGRAS = {};" +
  corpoDaFuncao("normalizarBusca") + corpoDaFuncao("valorTolerante") +
  corpoDaFuncao("formularioDaAtividade") + corpoDaFuncao("formularioDaDescricao") +
  blocoVar("NOME_REGRA_CAMPO") + corpoDaFuncao("campoVisivelParaDescricao") +
  blocoVar("PADRAO_OBRIGATORIEDADE") + corpoDaFuncao("campoObrigatorioPara") + corpoDaFuncao("reqDinamico") +
  corpoDaFuncao("campoVazio") + corpoDaFuncao("nomesFaltando") +
  "; var CATALOGO = {};" +
  corpoDaFuncao("camposAtividade") + corpoDaFuncao("validarAtividade") +
  "; return function(regras, a, r){ REGRAS = regras; return validarAtividade(a, r); };"
)();

// UP obrigatório para o cliente, E escondido para a descrição escolhida --
// o caso exato que travaria o envio se o filtro não alcançasse a validação.
const faltandoComUpOculto = harnessValidar(
  {
    campo_obrigatorio: { "Colheita:UP": true },
    campos_ocultos_descricao: { "SERVIÇO SEM UP": ["UP"] }
  },
  { tipo_atividade: "PATROLAMENTO", descricao_atividade: "SERVIÇO SEM UP", up: "", equipamentos: [{ equipamento: "MN-006", operador: "JOSE" }] },
  { cliente: "Colheita" }
);
checar("UP obrigatório MAS escondido não trava o envio",
  faltandoComUpOculto.indexOf("UP") === -1,
  "faltando: " + JSON.stringify(faltandoComUpOculto) + " -- um campo invisível travaria o operador sem saída");

// Contraprova: sem a regra de ocultar, o mesmo UP obrigatório TEM que travar
// -- prova que o teste acima testa o esconder, não um validarAtividade quebrado.
const faltandoSemOcultar = harnessValidar(
  { campo_obrigatorio: { "Colheita:UP": true } },
  { tipo_atividade: "PATROLAMENTO", descricao_atividade: "", up: "", equipamentos: [{ equipamento: "MN-006", operador: "JOSE" }] },
  { cliente: "Colheita" }
);
checar("contraprova: sem esconder, UP obrigatório vazio TEM que travar",
  faltandoSemOcultar.indexOf("UP") !== -1,
  "não travou -- o teste anterior não provaria nada se este também passasse escondendo por acidente");

// O mesmo, no formulário Máquinas Detalhado -- lista fixa (camposPorMaquina),
// não passa pelo array que camposAtividade() filtra sozinha.
const camposComTudoOcultoDetalhado = camposComOcultos(
  { formulario_descricao: { "OBRA DETALHADA": "maquinas_detalhado" },
    campos_ocultos_descricao: { "OBRA DETALHADA": ["UP"] } },
  "OBRA DETALHADA"
);
checar("no Máquinas Detalhado, camposAtividade() nem chega a ver os campos por máquina",
  camposComTudoOcultoDetalhado.length === 1 && camposComTudoOcultoDetalhado[0].k === "data_execucao",
  "formulário mudou de forma inesperada -- não é este ponto que filtra os campos da máquina");

const faltandoDetalhadoComUpOculto = harnessValidar(
  {
    formulario_descricao: { "OBRA DETALHADA": "maquinas_detalhado" },
    campo_obrigatorio: { "Colheita:UP": true },
    campos_ocultos_descricao: { "OBRA DETALHADA": ["UP"] }
  },
  { tipo_atividade: "PATROLAMENTO", descricao_atividade: "OBRA DETALHADA", data_execucao: "2026-09-16",
    maquinas: [{ equipamento: "MN-006", operador: "JOSE", up: "" }] },
  { cliente: "Colheita" }
);
checar("Máquinas Detalhado: UP obrigatório MAS escondido não trava (camposPorMaquina filtrado)",
  faltandoDetalhadoComUpOculto.join(" ").indexOf("UP") === -1,
  "faltando: " + JSON.stringify(faltandoDetalhadoComUpOculto));

// A tela: o campo tem que sumir de onde é DESENHADO, não só de onde é
// validado -- as duas coisas moram em lugares diferentes do código.
checar("renderTelaAtividade consulta a visibilidade antes de desenhar o UP do padrão",
  /campoVisivelParaDescricao\(a\.descricao_atividade,\s*"up"\)/.test(corpoDaFuncao("renderTelaAtividade")),
  "o UP do formulário padrão é desenhado sem checar visibilidade");

checar("os campos do card de Máquinas Detalhado passam por campoSeVisivel",
  (corpoDaFuncao("renderTelaAtividade").match(/campoSeVisivel\(/g) || []).length >= 5,
  "poucos campos do card estão protegidos -- algum ficaria sempre visível");

// Hora Inicial/Final nunca podem sumir: são o núcleo do registro de tempo.
checar("Hora Inicial e Hora Final NÃO são escondíveis no card detalhado",
  !/campoSeVisivel\([^)]*"hora_inicial"/.test(corpoDaFuncao("renderTelaAtividade")) &&
  !/campoSeVisivel\([^)]*"hora_final"/.test(corpoDaFuncao("renderTelaAtividade")),
  "hora inicial/final viraram escondíveis -- isso esvaziaria o próprio sentido do formulário");

// --- o lado do Painel --------------------------------------------------------
// "Formulário por descrição" e "Campos visíveis por descrição" viraram UMA
// seção só (16/09, pedido do Fábio: as duas giravam em torno da mesma
// descrição e ficaram "espalhadas pela tela como se a função tivesse sido
// criada e só jogada"). A coluna "Campos" expande DENTRO da linha -- não há
// mais um segundo seletor de descrição.
checar("existe uma seção única 'Descrição (tarifa)', não duas espalhadas",
  /<h2>Descrição \(tarifa\)<\/h2>/.test(htmlPainel) &&
  !/Formulário por descrição \(tarifa\)/.test(htmlPainel) &&
  !/>Campos visíveis por descrição</.test(htmlPainel),
  "voltaram os dois títulos separados, ou nenhum título novo apareceu");

// --- guias internas de Configurações (17/09) --------------------------------
// Pedido do Fábio: "Campos obrigatórios por cliente" não estava num "padrão
// vendável/profissional" dividindo a tela com "Descrição (tarifa)". As duas
// ganharam guia própria, reaproveitando a MESMA fórmula visual das abas
// principais do app (.abas) -- "profissional" aqui é "consistente com o
// resto do app", não um terceiro estilo inventado.
console.log("\n--- guias internas de Configurações ---\n");

// O id vem de CONFIG_GUIAS iterado (data-config-guia="'+g.id+'"), então
// procurar a string literal no CÓDIGO-FONTE não bate -- é o array que
// precisa ter os dois ids certos.
checar("existem as duas guias, com os ids certos",
  /id:"descricao"/.test(htmlPainel) && /id:"obrigatoriedade"/.test(htmlPainel) &&
  /data-config-guia="'\s*\+\s*g\.id\s*\+\s*'"/.test(htmlPainel),
  "faltou uma das duas guias no array CONFIG_GUIAS, ou o botão não usa g.id");

checar("o clique na guia troca App.configGuia e re-renderiza",
  /App\.configGuia\s*=\s*btn\.getAttribute\("data-config-guia"\)/.test(htmlPainel),
  "o wiring não está trocando a guia ativa");

checar("as guias reaproveitam a classe 'active' das abas principais (mesmo padrão visual)",
  /guiaAtual===g\.id\?"active":""/.test(htmlPainel),
  "as guias não marcam a ativa do mesmo jeito que .abas button.active");

checar("as duas telas de configuração viraram funções próprias (não uma só gigante)",
  /function renderConfigDescricao/.test(htmlPainel) && /function renderConfigObrigatoriedade/.test(htmlPainel),
  "renderTelaConfiguracoes voltou a fazer tudo numa função só");

// --- largura total, não mais dividida lado a lado ---------------------------
checar("as tabelas usam o cartão em largura total (mesmo padrão do Histórico)",
  /class="card-config"/.test(htmlPainel) && /class="tabela-config"/.test(htmlPainel),
  "não migrou para o padrão .card-hist/.tabela-hist reaproveitado");

checar("sumiu o max-width:820px que espremia a tabela de descrições",
  !/max-width:820px/.test(htmlPainel),
  "a tabela de descrição ainda está limitada em largura");

checar("as duas seções não dividem mais espaço lado a lado (.config-row/.config-section sumiram)",
  !/class="config-row"/.test(htmlPainel) && !/class="config-section"/.test(htmlPainel),
  "o layout flex-wrap lado a lado ainda existe");

// --- coluna "Campo" fixa ao rolar, para a matriz crescer sem perder contexto
checar("a coluna Campo da matriz de obrigatoriedade fica fixa ao rolar (col-campo, sticky)",
  /col-campo/.test(htmlPainel) && /position:sticky; left:0/.test(htmlPainel),
  "sem isso, muitos clientes tiram o nome do campo de vista ao rolar de lado");

checar("o segundo seletor de descrição (config-campo-descricao) não existe mais",
  !/config-campo-descricao/.test(htmlPainel),
  "sobrou o picker antigo -- duas formas de escolher a mesma descrição na tela");

checar("a coluna Campos expande dentro da própria linha da tabela",
  /btn-campos-visiveis/.test(htmlPainel) && /campos-visiveis-inline/.test(htmlPainel),
  "o botão de expandir ou o contêiner dos checkboxes não está na tela");

checar("o botão de expandir guarda a linha aberta no App (sobrevive ao render)",
  /App\.configLinhaExpandida/.test(htmlPainel),
  "sem estado guardado, expandir uma linha fecharia sozinho no próximo render");

// O que importa de verdade é o WIRING: o handler lê a descrição do próprio
// checkbox clicado, não de um estado de tela que poderia estar apontando
// para outra linha se duas fossem abertas ao mesmo tempo.
checar("o handler do checkbox lê a descrição do próprio elemento clicado",
  /chk\.getAttribute\("data-descricao"\)/.test(htmlPainel),
  "o checkbox pode ter voltado a depender de App.configCampoDescricao (estado de tela única)");

checar("o Painel grava campos_ocultos_descricao",
  /salvarRegra\("campos_ocultos_descricao"/.test(htmlPainel),
  "a tela não persiste a configuração");

checar("Hora Máquina não tem campo escondível no Painel (só Tipo/Observação, que são o núcleo)",
  /CAMPOS_ESCONDIVEIS_POR_FORMULARIO\s*=\s*\{[^}]*\}/.test(htmlPainel) &&
  !new RegExp("hora_maquina\\s*:\\s*\\[").test(
    (htmlPainel.match(/CAMPOS_ESCONDIVEIS_POR_FORMULARIO\s*=\s*\{[\s\S]*?\n  \};/) || [""])[0]),
  "hora_maquina ganhou uma lista de campos escondíveis sem ninguém pedir");

checar("Padrão e Máquinas Detalhado têm campos escondíveis no Painel",
  /padrao:\s*\[[^\]]*"Profundidade"/.test(htmlPainel) &&
  /maquinas_detalhado:\s*\[[^\]]*"Profundidade"/.test(htmlPainel),
  "a lista de campos escondíveis não cobre os dois formulários");

console.log("\nTOTAL DE FALHAS: " + erros);
console.log(erros === 0 ? "TESTES VERDES" : "TEM FALHA -- leia acima");
process.exit(erros ? 1 : 0);
