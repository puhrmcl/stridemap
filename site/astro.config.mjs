import { defineConfig } from 'astro/config';

// Static output. No auth, no database, no client JS — nothing here needs a server.
// Vercel serves the built files straight from its edge network.
export default defineConfig({
  site: 'https://www.nwagtech.com',
  output: 'static',
  build: { format: 'directory' },
});
