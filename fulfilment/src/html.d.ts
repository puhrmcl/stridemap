/// Wrangler bundles *.html as text (wrangler.toml [rules]); this tells tsc the same story.
declare module "*.html" {
  const content: string;
  export default content;
}
