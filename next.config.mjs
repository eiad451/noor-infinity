import path from 'path';
const config = {
  outputFileTracingRoot: path.join(process.cwd()),
  eslint: { ignoreDuringBuilds: true },
  typescript: { ignoreBuildErrors: true },
  webpack: (cfg) => {
    cfg.optimization.minimize = false;
    return cfg;
  }
};
export default config;
