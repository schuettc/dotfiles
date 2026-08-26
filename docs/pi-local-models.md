# Pi with local llama.cpp models

The `pi` dotfiles package configures Pi's built-in `llama.cpp` provider and a
persistent llama.cpp router on `127.0.0.1:42137`. Pi remains the application;
llama.cpp is only the local inference runtime. The current default model is
Unsloth's Q8 GGUF conversion of Qwen3.8 27B. No Unsloth software or service is
installed or run.

This entire component is opt-in. The standard `install.sh` does not install Pi,
llama.cpp, the router LaunchAgent, or any model configuration.

## Choose how much to install

| Choice | What it installs or changes | Command |
|---|---|---|
| Skip Pi | Nothing; this is what the standard dotfiles install does | `./install.sh` |
| Pi CLI only | Pi, with no llama.cpp runtime, LaunchAgent, or local provider defaults | `npm install -g @earendil-works/pi-coding-agent` |
| Managed local stack | Pi, llama.cpp, local provider configuration, router launcher, and LaunchAgent | `~/dotfiles/packages/run.sh pi` |
| Managed local stack when `core` is not installed | The required `core` package plus everything above; Homebrew must already be available | `~/dotfiles/packages/run.sh core pi` |

The CLI-only path is useful when Pi will use hosted providers or when you want
to manage every provider yourself. The managed path is the reproducible option:
the files in this repository describe the endpoint, model metadata, runtime
tuning, and defaults for another Mac.

## Install the managed local stack

```bash
~/dotfiles/packages/run.sh pi
```

The package is safe to rerun. It installs llama.cpp with Homebrew,
installs/updates Pi with npm,
additively merges the local provider into Pi's normal configuration, and starts
the router as a macOS LaunchAgent. It does not download large model weights.
If the `core` package has not already been installed, use
`~/dotfiles/packages/run.sh core pi` instead.

## Optional configuration

The tracked configuration is split by responsibility:

| File | Change it when… |
|---|---|
| `config/pi/local.json` | You want a different loopback host, port, or local coordination key |
| `config/pi/settings.json` | You want a different default provider, model, thinking level, or compaction limits |
| `config/pi/models.json` | You want to add persistent Pi model metadata, sampling, context, or compatibility settings |
| `config/pi/models.ini` | You want to add a model or tune llama.cpp loading, Metal offload, KV cache, batching, or draft decoding |
| `config/pi/dev.pi.llama-router.plist` | You need to change launchd startup or persistence behavior |

After changing any of these, rerun `~/dotfiles/packages/run.sh pi`. The package
merges only its owned Pi keys and reloads the router; unrelated Pi providers,
credentials, and settings remain intact.

If npm is not available yet, install Node/NVM and rerun the command.

## Download and select models

Run Pi normally:

```bash
pi
```

Inside Pi, use:

```text
/llama
```

Pi's native llama.cpp browser can search Hugging Face, download a quantization,
and load or unload models. Only loaded or explicitly configured models appear
under `/model`.

The configured Qwen model is:

```text
unsloth/Qwen3.8-27B-GGUF:Q8_0
```

The first request can also make the router download and autoload it. Expect a
roughly 28–30 GB download. Model data lives in
`~/.local/share/llama.cpp/`, outside the dotfiles repository.

## Normal Pi commands

No wrapper or Makefile is involved:

```bash
pi
pi --continue
pi --resume
pi --session 01a015c4-4306-71d1-a30c-87de43695e83
```

Sessions live in Pi's normal `~/.pi/agent/sessions/` directory.

## Choose how models are managed

For an occasional model, use `/llama`; no dotfiles change is necessary. Pi
discovers loaded models from the router and exposes them through `/model`.
This is the quickest option for trying a different quantization or model family.

For a model that should be reproducible across machines or needs tuned
reasoning, context, sampling, or compatibility metadata:

1. Add its Pi model entry to `config/pi/models.json`.
2. Add a matching section to `config/pi/models.ini` for llama.cpp runtime
   options.
3. Run `~/dotfiles/packages/run.sh pi` to merge and reload the configuration.

The `llama.cpp` provider is model-neutral and can contain Qwen, Gemma, Llama,
or any other compatible GGUF.

## Service management

```bash
# Inspect the router
launchctl print gui/$(id -u)/dev.pi.llama-router
curl -H 'Authorization: Bearer local-pi' http://127.0.0.1:42137/health

# Restart after changing model presets
launchctl kickstart -k gui/$(id -u)/dev.pi.llama-router

# Follow logs
tail -f ~/Library/Logs/pi-llama-router.log
```

The router stays lightweight until a model is loaded. It binds only to
`127.0.0.1`, so it is not reachable from other machines.

## Configuration ownership

The installer owns only these portions of Pi's configuration:

- provider `llama.cpp` in `~/.pi/agent/models.json`
- credential `llama.cpp` in `~/.pi/agent/auth.json`
- the local default-model and compaction keys in `~/.pi/agent/settings.json`

All unrelated providers, credentials, and settings are preserved by additive
`jq` merges. The literal `local-pi` API key is only a coordination value for a
loopback-only server; it is not an external secret.
