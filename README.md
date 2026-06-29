# Dashboards

Static HTML dashboards published to **GitHub Pages** and shareable via public links — no Claude account, no GitHub account, and no login required for viewers.

**Live index:** https://martintowers.github.io/dashboards/

## How it works

- Each dashboard lives in its own folder with an `index.html`.
- It's served at: `https://martintowers.github.io/dashboards/<dashboard-name>/`
- The root `index.html` lists and links to every dashboard. It is **regenerated automatically** on each deploy, so you never edit it by hand.

```
dashboards/
├── index.html        # auto-generated listing (do not edit by hand)
├── deploy.sh         # the deploy script
├── README.md
└── hello/
    └── index.html    # a dashboard
```

## Deploying a dashboard

```bash
./deploy.sh <dashboard-name> <path-to-html-file>
```

Example:

```bash
./deploy.sh sales-q3 ~/Downloads/sales-report.html
```

This will:

1. Copy your HTML file to `sales-q3/index.html`
2. Regenerate the root index page
3. Commit and push to `main`
4. Wait for GitHub Pages to publish
5. Print the live public URL: `https://martintowers.github.io/dashboards/sales-q3/`

Re-running with the same name **replaces** that dashboard. Dashboard names may contain only letters, numbers, dots, dashes, and underscores.

## Password-protecting a dashboard 🔒

Pass `-p <password>` (or `--encrypt`) and the dashboard is **encrypted with [StatiCrypt](https://github.com/robinmoisson/staticrypt) before it's committed**:

```bash
./deploy.sh -p 'your-passphrase' quarterly-numbers ~/Downloads/q3.html
```

Visitors hit a password prompt and the page decrypts in their own browser. Password-protected dashboards show a 🔒 next to their name on the index page.

**Why this is safe in a public repo:** only the AES-encrypted ciphertext is ever pushed — the plaintext HTML stays on your machine and is never copied into the repo. View-source and browsing the repo both show only scrambled data.

To avoid putting the password in your shell history, set it as an env var instead:

```bash
STATICRYPT_PASSWORD='your-passphrase' ./deploy.sh --encrypt quarterly-numbers ~/Downloads/q3.html
```

**Limits of this approach (be honest with yourself):**
- It's a single **shared** passphrase per dashboard, not per-person logins. Anyone you give it to can pass it on.
- A weak passphrase can be brute-forced offline since the ciphertext is public — **use a long, random one**.
- There's no way to revoke access from one person without re-encrypting with a new passphrase and re-sharing.
- If you need real per-user login (named people, revocable access), that means moving off GitHub Pages to something like Cloudflare Pages + Access.

## Removing a dashboard

```bash
rm -rf <dashboard-name>
git add -A && git commit -m "Remove <dashboard-name>" && git push
# then redeploy any other dashboard, or regenerate the index, to drop it from the listing
```

## ⚠️ This repo is PUBLIC

Everything you push here is visible to anyone on the internet, including the full source.

- **Only static HTML / CSS / JS.** No server-side code.
- **Never** put API keys, passwords, tokens, or sensitive/private data in the HTML.
- If a dashboard needs live data, fetch it client-side from an endpoint that is itself safe to be public, or bake in only data you're comfortable publishing.

## One-time setup (already done)

- Repo: `martintowers/dashboards` (public)
- GitHub Pages: deploy from the `main` branch, root (`/`) folder
- Requires the `gh` CLI authenticated (`gh auth status`) and git configured
