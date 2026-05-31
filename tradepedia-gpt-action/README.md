# Tradepedia GPT Action

This package lets a Custom GPT update Tradepedia from ChatGPT on mobile.

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
