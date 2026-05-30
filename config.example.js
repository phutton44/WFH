/**
 * Copy to `config.js` if you need a non-default API origin (e.g. static site on one port,
 * `vercel dev` API on another). On a normal Vercel deployment, `npm run build` writes
 * this file and same-origin `/api/*` is used when `apiBase` is empty.
 */
window.WFH_API = {
  apiBase: "",
  // Generated from GOOGLE_WEB_CLIENT_ID / WFH_GOOGLE_WEB_CLIENT_ID.
  googleClientId: "",
  // Generated from APPLE_WEB_CLIENT_ID / WFH_APPLE_WEB_CLIENT_ID.
  appleClientId: "",
  // Usually https://your-app.vercel.app/ for Apple web popup auth.
  appleRedirectURI: "",
};
