/** Corporate structure. This file is the source for the org chart, the operating
 *  table and the former-operations table on the parent-company page. */

export type Status = 'Operating' | 'In evaluation' | 'Discontinued';

export type Entity = {
  name: string;
  sector: string;
  office: string;
  status: Status;
  href?: string;
  note?: string;
};

export const subsidiaries: Entity[] = [
  {
    name: 'Verde House',
    sector: 'Software development and venture studio',
    office: 'Gilbert, Arizona',
    status: 'Operating',
    href: '/verde-house',
  },
  {
    name: 'Contract Soil Sampling',
    sector: 'Agricultural services',
    office: 'Paullina, Iowa',
    status: 'Operating',
    href: '/soil-sampling',
  },
  {
    name: 'Undisclosed',
    sector: 'Under evaluation',
    office: '—',
    status: 'In evaluation',
    note: 'A fourth line of business is being assessed. It will be named here once it is formed.',
  },
];

/** Kept on the record deliberately. A holding company that shows only its
 *  successes is harder to diligence, not easier. */
export const former: Entity[] = [
  {
    name: 'Grain transport',
    sector: 'Logistics — trucking and hauling',
    office: 'Paullina, Iowa',
    status: 'Discontinued',
  },
  {
    name: 'Precision agriculture software',
    sector: 'Authorised reseller and account management',
    office: 'Paullina, Iowa',
    status: 'Discontinued',
    note: 'Distribution of a third-party platform. The relationship has ended.',
  },
];

export const corporate = {
  legalName: 'Northwest Ag Technologies, L.L.C.',
  shortName: 'Northwest Ag Technologies',
  entityType: 'Limited liability company',
  offices: ['Paullina, Iowa', 'Gilbert, Arizona'],
  general: 'info@nwagtech.com',
  software: 'software@nwagtech.com',
  /** Not published until confirmed — rendered as a marked slot. */
  jurisdiction: null as string | null,
  formed: null as string | null,
};
