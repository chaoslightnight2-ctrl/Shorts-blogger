# Tradepedia GPT Action

This package lets a Custom GPT update Tradepedia from ChatGPT on mobile.

## Recommended free mobile setup

Use `openapi-github-free.yaml`. This does not need Cloudflare, Vercel, Netlify, or a paid server.

Flow:

1. ChatGPT calls GitHub's `repository_dispatch` API.
2. GitHub Actions runs `.github/workflows/tradepedia-gpt-dispatch.yml`.
3. The workflow updates `public/content.html` and `app/src/main/assets/fallback.html`.
4. The existing Pages workflow publishes the new `content.html`.

Custom GPT setup:

1. Create a fine-grained GitHub token for this repository.
2. Give it read/write repository contents access.
3. In the GPT editor, add an Action.
4. Paste `openapi-github-free.yaml`.
5. Set authentication to API key / Bearer and paste the GitHub token.
6. On mobile, use that Custom GPT and say what article to add.

Prompt example:

```text
Tradepedia'ya ICT Fair Value Gap maddesi ekle.
Tür: Kavram. Kategori: Price Action. Seviye: Orta.
Özet, kullanım, hatalı kullanım ve bot/backtest notu da yaz.
```

The GPT must call `addOrUpdateTradepediaEntry` with:

```json
{
  "event_type": "tradepedia-entry",
  "client_payload": {
    "title": "ICT Fair Value Gap",
    "kind": "Kavram",
    "category": "Price Action",
    "summary": "...",
    "body": "..."
  }
}
```

## Optional Worker setup

Flow:

1. The GPT calls the action endpoint.
2. The action endpoint updates `public/content.html`.
3. The same HTML is copied to `app/src/main/assets/fallback.html`.
4. GitHub Pages deploys `public/content.html`.
5. The APK keeps using the same remote URL.

## Deploy target

The bridge is written for Cloudflare Workers because it can keep secrets and call the GitHub API without exposing your GitHub token to ChatGPT.

Required Worker secrets:

```text
TRADEPEDIA_ACTION_SECRET
GITHUB_TOKEN
```

Required Worker variables:

```text
GITHUB_OWNER=chaoslightnight2-ctrl
GITHUB_REPO=Shorts-blogger
GITHUB_BRANCH=main
```

`GITHUB_TOKEN` needs permission to read and write repository contents.

## GPT Action setup

1. Deploy the Worker.
2. Open `openapi.yaml`.
3. Replace `https://YOUR-WORKER-DOMAIN.workers.dev` with the deployed Worker URL.
4. In the GPT editor, add a new Action.
5. Paste the OpenAPI schema.
6. Set authentication to API key / Bearer.
7. Use the same value as `TRADEPEDIA_ACTION_SECRET`.

Use the GPT with prompts like:

```text
Tradepedia'ya ICT Fair Value Gap maddesi ekle. Kategori: Kavram. Seviye: Orta.
```

The action accepts structured text fields. It does not ask the model to rewrite the entire 1.3 MB HTML file.
