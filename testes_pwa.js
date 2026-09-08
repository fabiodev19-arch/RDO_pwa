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

checar("RDO sincronizado antes desta versão também fica protegido",
  /function marcarEnviadasRetroativo[\s\S]{0,500}relatorioSincronizado\(r\)/.test(htmlCompleto) &&
  /carregarRelatoriosSalvos[\s\S]{0,400}marcarEnviadasRetroativo\(\)/.test(htmlCompleto),
  "sem marcação retroativa, o que já está no aparelho segue destravado");

console.log("\nTOTAL DE FALHAS: " + erros);
console.log(erros === 0 ? "TESTES VERDES" : "TEM FALHA -- leia acima");
process.exit(erros ? 1 : 0);
