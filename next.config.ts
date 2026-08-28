import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  /* config options here */
  reactCompiler: true,
  experimental: {
    // proxy.ts runs for Server Action requests and Next buffers that cloned
    // body. 27 MB admits a 25 MiB PDF plus multipart framing, while the
    // reservation RPC remains the authoritative 25 MiB acceptance gate.
    proxyClientMaxBodySize: '27mb',
    serverActions: {
      bodySizeLimit: '27mb',
    },
  },
};

export default nextConfig;
