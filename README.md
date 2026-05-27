# lark-plug-hdeck

[larkline](https://github.com/TaylorFinklea/larkline) plugin that surfaces
[harness-deck](https://github.com/TaylorFinklea/harness-deck) reports as a
keyboard-driven picker — pending asks, every report, and in-flight
agents — without leaving the terminal or Neovim.

## What you get

Three larkline commands:

| command | what it shows | quickkey |
|---|---|---|
| `Inbox` | reports that need you (status `awaiting-review` or open asks) | `hd` |
| `All Reports` | every non-archived report, newest first | — |
| `In Flight` | reports with live telemetry updated in the last 60 seconds | — |

Each row's primary action opens the report in your default browser. The
alt action copies the URL.

## Install

```sh
# from a clone
git clone https://github.com/TaylorFinklea/lark-plug-hdeck \
  ~/.config/larkline/plugins/lark-plug-hdeck
```

Then point the plugin at your harness-deck server:

```sh
# ~/.config/larkline/.env
HARNESS_DECK_URL=https://scadrial.tailceb58.ts.net:7420
```

Restart larkline (`lark`); the **Harness Deck** plugin appears in the
launcher with three subcommands. The `Inbox` command is keyed to `hd`
by default — type `:hd` at the larkline prompt to jump straight in.

## Configuration

| env var | purpose | default |
|---|---|---|
| `HARNESS_DECK_URL` | Base URL of your harness-deck server. Must be reachable from the machine running larkline. | `http://127.0.0.1:7420` |

If you run harness-deck with TLS (recommended for iOS web push), use
the same hostname the cert is for — typically a Tailscale tailnet
name like `https://scadrial.tailceb58.ts.net:7420`. The TLS cert is
validated; localhost won't match a tailnet cert.

If you run harness-deck on the same machine with no TLS, the default
`http://127.0.0.1:7420` works as-is.

## Via Neovim

This plugin works through Neovim free via
[lark.nvim](https://github.com/TaylorFinklea/lark.nvim) — `:Lark` opens
larkline in a floating terminal, where the `Harness Deck` plugin is
available like any other. No additional Neovim setup needed.

## Why this exists

harness-deck is a "where the agents put their reports" tool;
larkline is a "how the user reaches anything" tool. Without a bridge,
each is a separate destination. With this plugin, larkline becomes a
remote control for harness-deck: triage pending asks from anywhere you
can launch larkline (terminal, Neovim, a herdr pane).

The bridge is intentionally one-directional: the plugin **reads** the
dashboard's JSON API and **opens** report URLs. It does not record
responses, edit reports, or call the MCP server — those happen in the
browser where the response UI lives.

## License

MIT. See [LICENSE](LICENSE).
