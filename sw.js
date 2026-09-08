// Service Worker — GTM RDO
// Este app guarda os relatórios no IndexedDB do próprio aparelho, então o
// Service Worker aqui tem um único trabalho: colocar o "app shell" (HTML,
// manifest, ícones) em cache para o app abrir mesmo sem nenhum sinal de
// internet — inclusive na primeira tela, sem precisar já ter sido aberto
// online antes de ir a campo.

var CACHE_NAME = "gtm-rdo-v27";
var APP_SHELL = [
  "./",
  "./index.html",
  "./manifest.webmanifest",
  "./icon-192.png",
  "./icon-512.png"
];

self.addEventListener("install", function (event) {
  event.waitUntil(
    caches.open(CACHE_NAME).then(function (cache) {
      return cache.addAll(APP_SHELL);
    }).then(function () {
      return self.skipWaiting();
    })
  );
});

self.addEventListener("activate", function (event) {
  event.waitUntil(
    caches.keys().then(function (nomes) {
      return Promise.all(
        nomes.filter(function (n) { return n !== CACHE_NAME; })
             .map(function (n) { return caches.delete(n); })
      );
    }).then(function () {
      return self.clients.claim();
    })
  );
});

// Cache-first para o app shell: sempre abre instantâneo e funciona offline.
// Qualquer coisa fora da lista (ex.: uma futura chamada de API) vai direto
// pra rede, sem passar por cache.
self.addEventListener("fetch", function (event) {
  if (event.request.method !== "GET") return;

  event.respondWith(
    caches.match(event.request).then(function (cached) {
      if (cached) return cached;
      return fetch(event.request).catch(function () {
        return caches.match("./index.html");
      });
    })
  );
});

// ------------------------------------------------------------------------
// Push: dispara quando o painel devolve uma atividade pra correção. O
// envio de verdade acontece numa função fora do banco (Edge Function),
// que usa a chave privada VAPID -- aqui só mostra a notificação que
// chegou, funciona mesmo com o app fechado (é o motivo de existir).
// ------------------------------------------------------------------------
self.addEventListener("push", function (event) {
  var dados = { titulo: "GTM RDO", corpo: "Você tem uma atualização." };
  if (event.data) {
    try { dados = event.data.json(); } catch (e) {
      dados.corpo = event.data.text() || dados.corpo;
    }
  }
  event.waitUntil(
    self.registration.showNotification(dados.titulo || "GTM RDO", {
      body: dados.corpo || "",
      icon: "./icon-192.png",
      badge: "./icon-192.png",
      tag: "gtm-rdo-devolucao", // uma notificação nova substitui a anterior, não empilha
      data: { url: "./" }
    })
  );
});

// Clique na notificação: foca uma aba já aberta do app, ou abre uma nova.
self.addEventListener("notificationclick", function (event) {
  event.notification.close();
  var url = (event.notification.data && event.notification.data.url) || "./";
  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then(function (lista) {
      for (var i = 0; i < lista.length; i++) {
        if (lista[i].url.indexOf(url.replace("./", "")) !== -1 && "focus" in lista[i]) {
          // Avisar é obrigatório aqui: focus() traz a janela pra frente mas não
          // recarrega nada, então o app continuava mostrando a tela de antes e
          // a devolução só aparecia se o operador atualizasse na mão.
          //
          // Recarregar seria pior -- perderia rascunho não salvo do RDO em
          // preenchimento. A mensagem faz a página só rebuscar as devolvidas.
          if (lista[i].postMessage) {
            lista[i].postMessage({ tipo: "notificacao-clicada" });
          }
          return lista[i].focus();
        }
      }
      // Nenhuma janela aberta: abrir do zero já busca as devolvidas no login.
      if (clients.openWindow) return clients.openWindow(url);
    })
  );
});
