/** Corporate record. Source for the org chart, the current-operations table,
 *  the track record and the entity facts on the parent-company page. */

export type Status = 'Operating' | 'In evaluation' | 'Concluded';

export type Entity = {
  name: string;
  sector: string;
  /** Short form for the org chart, where SVG text cannot wrap. */
  short: string;
  office: string;
  status: Status;
  href?: string;
  note?: string;
};

/** What the company runs today. */
export const subsidiaries: Entity[] = [
  {
    name: 'Verde House',
    sector: 'Software development and venture studio',
    short: 'Software development',
    office: 'Gilbert, Arizona',
    status: 'Operating',
    href: '/verde-house',
  },
  {
    name: 'Contract Soil Sampling',
    sector: 'Agricultural services',
    short: 'Agricultural services',
    office: 'Paullina, Iowa',
    status: 'Operating',
    href: '/soil-sampling',
  },
  {
    name: 'Ascend Imagery',
    sector: 'Aerial photography and imaging',
    short: 'Aerial imaging',
    office: 'To be confirmed',
    status: 'Operating',
    note: 'No page yet — it needs a paragraph from you before it gets one.',
  },
];

export type Venture = {
  name: string;
  year: string | null;
  field: string;
  body: string;
  status: Status;
  href?: string;
};

/** The track record, oldest first. `year: null` renders as a marked slot —
 *  only 2013 and 2014 are confirmed. */
export const ventures: Venture[] = [
  {
    name: 'E4 Crop Intelligence',
    year: '2013',
    field: 'Precision agriculture software',
    body: 'The platform the company represented from the beginning — authorised reseller and account management, sold alongside our own soil testing rather than instead of it.',
    status: 'Concluded',
  },
  {
    name: 'Soil sampling and fertility services',
    year: '2013',
    field: 'Agricultural services',
    body: 'There from the first year. It began as soil testing with fertility recommendations attached; today it runs as independent contract sampling labor, where the client keeps the protocol, the lab and the recommendations.',
    status: 'Operating',
    href: '/soil-sampling',
  },
  {
    name: 'Pioneer Encirca',
    year: '2014',
    field: 'Precision agriculture services',
    body: 'Represented Pioneer\'s Encirca services in the year they reached the field — a second decision platform alongside E4, at a point when growers were still deciding whether software belonged in agronomy at all.',
    status: 'Concluded',
  },
  {
    name: 'AgAir',
    year: '2014',
    field: 'Aerial crop science',
    body: 'A drone imaging programme measuring plant photosynthesis and biomass from the air — flown years before aerial crop scouting became ordinary, and before most growers had seen a drone over a field at all.',
    status: 'Concluded',
  },
  {
    name: 'Top Line Trucking',
    year: '2016',
    field: 'Transportation',
    body: 'Feed ingredient and grain hauling.',
    status: 'Concluded',
  },
  {
    name: 'Slate Logistics',
    year: '2020',
    field: 'Transportation software',
    body: 'A transportation and logistics platform built in house — dispatch, load tracking and billing in one system. Written four years into running Top Line Trucking, because nothing on the market did what the freight operation actually needed.',
    status: 'Concluded',
  },
  {
    name: 'Ascend Imagery',
    year: '2021',
    field: 'Aerial photography',
    body: 'Drone photography and imaging for real estate. The second time the company has built a business around a camera in the air, seven years after the first.',
    status: 'Operating',
  },
  {
    name: 'Verde House',
    year: '2024',
    field: 'Software development',
    body: 'A software studio building its own products and taking founders and businesses from research through launch and into operation. The first software the company builds for itself rather than represents for someone else.',
    status: 'Operating',
    href: '/verde-house',
  },
];

export const corporate = {
  legalName: 'Northwest Ag Technologies, L.L.C.',
  shortName: 'Northwest Ag Technologies',
  entityType: 'Limited liability company',
  jurisdiction: 'Iowa',
  formed: '2013',
  formedAt: 'Paullina, Iowa',
  offices: ['Paullina, Iowa', 'Gilbert, Arizona'],
  general: 'info@nwagtech.com',
  software: 'software@nwagtech.com',
};
