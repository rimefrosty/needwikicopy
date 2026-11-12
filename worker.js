// Need Utils wiki proxy (Cloudflare Worker).
//
// The NEED wiki server only serves plain HTTP and doesn't allow other websites to read it, so a
// browser on an https:// page can't load it directly. This worker fetches the wiki files from the
// server, adds the CORS header, and caches them at Cloudflare's edge.
//
// Only files under the wiki folder with the extensions below are passed through.
//
// Deploy: see README.md in this folder.

const UPSTREAM = "http://151.145.74.228/patch/wiki/";
const ALLOWED = /^[A-Za-z0-9_\-\/.]+\.(json|png|jpe?g|gif|webp)$/i;

export default {
  async fetch(request, env, ctx) {
    if (request.method !== "GET") {
      return new Response("Method not allowed", { status: 405 });
    }

    const url = new URL(request.url);
    const rel = decodeURIComponent(url.pathname.replace(/^\/wiki\//, ""));
    if (!ALLOWED.test(rel) || rel.includes("..")) {
      return new Response("Not found", { status: 404 });
    }

    const cache = caches.default;
    const hit = await cache.match(request);
    if (hit) return hit;

    const target = UPSTREAM + rel.split("/").map(encodeURIComponent).join("/");
    const upstream = await fetch(target, { cf: { cacheTtl: 3600, cacheEverything: true } });
    if (!upstream.ok) {
      return new Response("Upstream returned " + upstream.status, { status: 502 });
    }

    const response = new Response(upstream.body, {
      status: 200,
      headers: {
        "Content-Type": upstream.headers.get("content-type") || "application/octet-stream",
        "Access-Control-Allow-Origin": "*",
        "Cache-Control": "public, max-age=3600",
      },
    });

    ctx.waitUntil(cache.put(request, response.clone()));
    return response;
  },
};
