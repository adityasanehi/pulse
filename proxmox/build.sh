#!/usr/bin/env bash
# Builds Pulse in place for the Proxmox container, which runs it without Docker: the Dockerfile's steps, with the
# result in .next/standalone (run by pulse.service). The helper script calls it on install and on `update`.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0 NEXT_TELEMETRY_DISABLED=1 CI=true

out=.next/standalone
rm -rf "$out"
pnpm install --frozen-lockfile
pnpm build
cp -r .next/static "$out/.next/static"
# Migrations run at boot from process.cwd()/drizzle.
cp -r public drizzle "$out/"
# reset-password and seed-user run outside the Next server, so each gets its own bundle (as in the Dockerfile).
for s in reset-password.mjs:reset-password seed-demo-user.mts:seed-user; do
  pnpm exec esbuild "scripts/${s%%:*}" --bundle --platform=node --format=esm --target=node24 --external:pg-native \
    --banner:js="import{createRequire}from'module';const require=createRequire(import.meta.url);" \
    --outfile="$out/scripts/${s##*:}.mjs"
done
# The service user owns only Next's cache; the code stays root-owned so a compromised app can't rewrite itself.
mkdir -p "$out/.next/cache"
chown -R pulse: "$out/.next/cache"
