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

["hora_maquina", "maquinas_detalhado"].forEach(function (form) {
  const ini = trechoPayload.indexOf('formulario === "' + form + '"');
  const ramo = trechoPayload.slice(ini, ini + 500);
  checar("o payload manda a descrição por máquina em " + form,
    ini !== -1 && /descricao:\s*m\.descricao/.test(ramo),
    "as máquinas desse formulário iriam sem tarifa própria");
});

checar("os três formulários oferecem o campo na tela",
  (htmlCompleto.match(/seletorDescricaoHtml\(/g) || []).length >= 3,
  "algum formulário ficou sem o campo");

checar("cada campo de descrição tem quem o ligue",
  /\.fake-select\[data-campo="descricao"\][\s\S]{0,400}?abrirSeletorDescricao/.test(htmlCompleto) &&
  /sel-descricao-ativ[\s\S]{0,200}?abrirSeletorDescricao/.test(htmlCompleto),
  "o campo abriria a lista e não gravaria, ou nem abriria");

// A lista real vem do banco. Uma cópia embutida aqui envelheceria sozinha
// quando a tarifa mudasse, e ninguém perceberia -- o app mostraria itens que
// já não existem.
checar("o catálogo local NÃO traz uma cópia das descrições",
  /descricoesAtividade:\s*\[\s*\]/.test(htmlCompleto),
  "há uma lista embutida: ela vira uma segunda verdade e envelhece sozinha");

console.log("\nTOTAL DE FALHAS: " + erros);
console.log(erros === 0 ? "TESTES VERDES" : "TEM FALHA -- leia acima");
process.exit(erros ? 1 : 0);
