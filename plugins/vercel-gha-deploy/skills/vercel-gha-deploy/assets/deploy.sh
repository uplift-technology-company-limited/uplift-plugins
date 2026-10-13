#!/usr/bin/env bash
# DEPRECATED — do not copy this into repos.
#
# The wrapper-script style (workflow → scripts/deploy.sh) was retired: all
# deploy steps now live INLINE in the workflow yml (explicit-steps style).
# Use assets/deploy.yml — it contains the full pipeline: compute version →
# vercel pull/build/deploy → tag push → GitHub Release publish → smoke test.
#
# This stub is kept only so old references don't 404. Safe to delete.
echo "DEPRECATED: use the inline workflow (assets/deploy.yml) — no deploy.sh wrapper." >&2
exit 1
