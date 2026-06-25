# Audiobook Tagger (self-hosted fork)

AI-powered audiobook metadata manager for [AudiobookShelf](https://www.audiobookshelf.org/).
Connects to your ABS server and uses AI to enrich book metadata — genres, tags,
descriptions, ISBN, ASIN, year, publisher, narrator, and DNA fingerprints.

This is a **fork of [philipvox/audiobook-tagger-web](https://github.com/philipvox/audiobook-tagger-web)**
with a focus on **fully self-hostable, LAN-friendly deployment** — works behind
Caddy/nginx with a sub-path, integrates with a local LiteLLM for free local AI,
and doesn't depend on third-party CORS proxies.

The upstream repo is the canonical project; this fork just adds patches needed
for an environment where you own the whole stack (ABS on `localhost`,
LiteLLM on `localhost`, Caddy as the only public ingress).

---

## What this fork adds

| Patch | Why |
|---|---|
| **`--ignore-scripts` on `npm ci`** | `package-lock.json` pins `rollup@4.53.0` whose postinstall calls `patch-package` (not declared as a dep). Build fails without this. Safe — vite doesn't need that hook. |
| **Inline `nginx.conf`** | Extracted the SPA's nginx config out of the Dockerfile so it can be version-controlled. Adds same-origin reverse proxies for `/api/litellm/`, `/api/audible/`, `/api/openlibrary/` so the browser never makes cross-origin requests. |
| **`VITE_BASE_PATH` build arg** | Lets you serve the SPA at a sub-path (e.g. `/tagger/`) behind Caddy without 404s on static assets. |
| **`LITELLM_UPSTREAM` build arg** | Portability — instead of hard-coding the LiteLLM address into the image, you pass it at build time. |
| **`lookup_book_isbn` extended** | The original only fetched ISBN + ASIN. This fork pulls publisher, year, and narrator from Audible + Open Library in the same call. Saves them to the book's metadata when "Lookup ISBN/ASIN" runs. |
| **Custom API Base URL field** | Settings → AI Provider now has a text input for a custom base URL. When filled, the tagger routes AI calls there instead of `api.openai.com` / `api.anthropic.com`. |
| **`minimax-m3` + `deepseek/deepseek-v4-flash` in the model dropdown** | Pre-listed options for local-via-LiteLLM usage. |
| **`validateAbsUrl` allows HTTP for private IPs** | The original rejected `http://10.0.0.12/...` because the web version "requires HTTPS" — but for self-hosted behind Caddy that's not a real restriction. |

---

## Quick start (root hosting)

The simplest deployment — SPA at `http://your-host:8082/`, direct port access.

```bash
git clone https://github.com/a3igner/audiobook-tagger-web.git
cd audiobook-tagger-web
docker compose up -d
open http://localhost:8082
```

Then in the web UI:
1. Click **Setup Wizard**
2. Enter your ABS URL (e.g. `http://your-abs-host:13378`) and API token
3. Pick an AI model from the dropdown — for cloud OpenAI/Anthropic, paste your key
4. For local AI: see [LiteLLM integration](#litellm-integration) below

---

## Behind a reverse proxy at a sub-path (Caddy/nginx)

If you're hosting the tagger at `https://your-host/tagger/` behind Caddy, you
need a few extra steps so the SPA loads correctly and stays same-origin with
your AI proxy.

### 1. Build with the right base path

```bash
docker build --build-arg VITE_BASE_PATH=/tagger/ -t audiobook-tagger .
```

This rewrites every asset URL in the HTML to `/tagger/assets/...` so the
browser resolves them against the proxied path.

### 2. Configure your reverse proxy

Example Caddyfile for the tagger + LiteLLM + ABS (adjust hosts and upstreams):

```caddyfile
http://your-host {
    # Serve the tagger SPA at /tagger/ (prefix is stripped before forwarding)
    handle_path /tagger* {
        reverse_proxy localhost:8082
    }

    # Same-origin proxy to your LiteLLM server — browser sees
    # http://your-host/api/litellm/... which Caddy forwards to LiteLLM.
    # The tagger's Custom API Base URL is set to /api/litellm.
    handle_path /api/litellm/* {
        reverse_proxy localhost:4000
    }

    # Optional: if you also proxy your ABS through Caddy, add this so
    # cover images and ABS API calls are same-origin to the tagger.
    # handle_path /abs/* {
    #     reverse_proxy https://your-abs-domain.example.com {
    #         header_up Host your-abs-domain.example.com
    #     }
    # }
}
```

### 3. In the tagger Settings page

Set:
- **Custom API Base URL** = `/api/litellm`
- **OpenAI API Key** = your LiteLLM master key (or a virtual key — see below)

---

## LiteLLM integration

The upstream web version only supports cloud AI (OpenAI, Anthropic) because
those APIs work from a browser. This fork adds a `Custom API Base URL` field
that lets you point the tagger at any OpenAI-compatible endpoint — including
your own LiteLLM proxy.

### One-time LiteLLM setup

1. Make sure LiteLLM is running and accessible to the tagger's nginx (or to Caddy).
2. In `~/litellm/.env`, the admin UI is at `http://localhost:4000/ui`. Log in with your master key.
3. Add at least one model. The model `model_name` (LiteLLM side) **must exactly match** an entry in the tagger's AI Model dropdown. If you want to use DeepSeek, register it as `deepseek/deepseek-v4-flash` (with the slash — the slash-prefixed names are the actual deployments; the un-prefixed ones are aliases with no deployments and will return HTTP 400).

### In the tagger

- **AI Model**: pick the matching entry (e.g. `deepseek/deepseek-v4-flash (via LiteLLM)`)
- **Custom API Base URL**: `/api/litellm` (when behind Caddy) or `http://localhost:4000` (direct)
- **OpenAI API Key**: your LiteLLM master key OR a virtual key scoped to the models you want

### Virtual keys (per-device or per-team)

Issue virtual keys in the LiteLLM admin UI and scope them to specific models
(e.g. one virtual key that can only call `minimax-m3`). This is how you get
rate-limiting and per-device isolation without exposing the master key.

---

## Build args

| Arg | Default | Purpose |
|---|---|---|
| `VITE_BASE_PATH` | `/` | URL prefix the SPA is served from. Set to `/tagger/` if behind a Caddy sub-path. |
| `LITELLM_UPSTREAM` | `http://localhost:4000` | URL the nginx `/api/litellm/` reverse proxy points to. |

Or via `.env` in the same dir as `docker-compose.yml`:

```bash
TAGGER_PORT=8082
LITELLM_UPSTREAM=http://my-litellm-server.lan:4000
VITE_BASE_PATH=/tagger/
```

---

## What's not in this fork (still requires the desktop app)

- **Local folder scanning** — the desktop Tauri app can scan an `M4B`/`MP3` directory directly. The web version reads from ABS only.
- **Local Ollama install/manage** — the desktop app bundles Ollama. In the web version, manage it yourself and register the model in LiteLLM.

For those, install the [desktop version](https://github.com/philipvox/audiobook-tagger-refactored/releases) alongside the web version and use whichever fits the task.

---

## Credits

- **Upstream**: [philipvox/audiobook-tagger-web](https://github.com/philipvox/audiobook-tagger-web) by [@philipvox](https://github.com/philipvox) — the actual project, go star it
- **Original desktop**: [philipvox/audiobook-tagger-refactored](https://github.com/philipvox/audiobook-tagger-refactored)
- This fork just adds the patches needed for a fully self-hosted LAN deployment

## License

Same as upstream — MIT.
