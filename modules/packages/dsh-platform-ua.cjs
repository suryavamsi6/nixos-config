// CloudFront in front of platform.deepseek.com rejects Node's default
// User-Agent (and any non-browser one) with a 403 HTML "Request blocked"
// page. dsh-deepseek-account-platform sets no User-Agent of its own, so its
// account calls (GET /auth-api/v0/users/current and friends) fail and get
// logged as errorCode "network". A full browser User-Agent passes the edge.
//
// Loaded via `node --require` from the dsh wrapper. Scoped to the platform
// host only: api.deepseek.com and every other request keep their original
// headers. DSH_PLATFORM_USER_AGENT overrides the string; set it empty to
// disable the rewrite.
"use strict";

const ua = process.env.DSH_PLATFORM_USER_AGENT;
if (!ua) return;

const PLATFORM_HOST = "platform.deepseek.com";

function isPlatform(input) {
  try {
    const href =
      typeof input === "string"
        ? input
        : input instanceof URL
          ? input.href
          : input && typeof input.url === "string"
            ? input.url
            : "";
    return new URL(href).hostname === PLATFORM_HOST;
  } catch {
    return false;
  }
}

function withUserAgent(init) {
  const headers = new Headers(init && init.headers);
  if (!headers.has("user-agent")) headers.set("user-agent", ua);
  return { ...init, headers };
}

const original = globalThis.fetch;
globalThis.fetch = function dshPlatformFetch(input, init) {
  if (!isPlatform(input)) return original.call(this, input, init);
  return original.call(this, input, withUserAgent(init));
};
