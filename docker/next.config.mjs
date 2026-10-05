// Replaces upstream's next.config.mjs during the image build. Upstream's file
// is renamed to next.config.upstream.mjs and extended here so that whatever
// upstream configures is kept, with standalone output added on top.
import upstream from "./next.config.upstream.mjs";

const withStandalone = (config) => ({ ...config, output: "standalone" });

export default typeof upstream === "function"
  ? async (...args) => withStandalone(await upstream(...args))
  : withStandalone(upstream);
