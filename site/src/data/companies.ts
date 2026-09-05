/** Northwest Ag Technologies operating companies.
 *  Add a third entry and the grid takes it with no layout change. */
export type Company = {
  name: string; office: string; primary?: boolean;
  mark: 'verde' | 'nwat'; body: string; href: string; cta: string;
};

export const companies: Company[] = [
  {
    name: 'Verde House',
    office: 'Gilbert, Arizona',
    primary: true,
    mark: 'verde',
    body: 'Our software studio. Verde House builds its own products and takes founders and businesses from research through design, build, launch and into operation.',
    href: '/verde-house',
    cta: 'Visit the studio',
  },
  {
    name: 'Contract Soil Sampling',
    office: 'Paullina, Iowa',
    mark: 'nwat',
    body: 'Independent sampling crews for ag businesses across the Midwest. Labor only — you keep the protocol, the lab and the recommendations.',
    href: '#sampling',
    cta: 'What we do',
  },
];
