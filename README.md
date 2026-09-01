# RDO — GTM Prestadora de Serviços

PWA de campo para preenchimento offline do Relatório Diário de Obra (RDO) da GTM.

## Arquivos

- `index.html` — aplicativo completo (identificação do relatório, atividades, evidências fotográficas, GPS)
- `manifest.webmanifest` — manifesto do PWA (ícone, nome, cor do tema)
- `sw.js` — Service Worker (cache do app shell para funcionar offline)
- `icons/` — ícones do app

## Como publicar (GitHub Pages)

O Service Worker só funciona em HTTPS — abrir o `index.html` direto do disco (`file://`) não ativa o modo offline nem permite instalar o app.

1. Depois de dar `git push` neste repositório, vá em **Settings → Pages**
2. Em **Source**, selecione a branch `main` e a pasta `/ (root)`
3. Salve — em alguns minutos o app fica disponível em `https://<seu-usuário>.github.io/RDO/`

Esse link já pode ser instalado no celular ("Adicionar à tela inicial") e vai funcionar offline depois do primeiro carregamento.

## Dados

Os relatórios preenchidos ficam salvos no IndexedDB do próprio navegador do usuário — nada é enviado a um servidor ainda (não há backend conectado). Cada relatório concluído fica marcado como "aguardando sincronização" até essa integração existir.
