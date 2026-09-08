// ============================================================================
// GTM RDO — testes do convite de notificação (lado JS do PWA)
// ============================================================================
// COMO RODAR:   node testes_pwa_push.js
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

console.log("\nTOTAL DE FALHAS: " + erros);
console.log(erros === 0 ? "TESTES VERDES" : "TEM FALHA -- leia acima");
process.exit(erros ? 1 : 0);
