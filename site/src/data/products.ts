/** Verde House product portfolio. */
export type Product = {
  name: string; status: string; body: string; stack: string; needsCopy?: boolean;
};

export const products: Product[] = [
  {
    name: 'StrideMap',
    status: 'iOS · shipping',
    body: 'Every run you have ever taken, woven into one living map. StrideMap reads your whole running history out of Apple Health — Apple Workouts, Nike Run Club, Garmin, COROS, Polar, Strava, anything that writes a workout — and draws it as one accumulating web across the cities you have explored. Recent runs glow; older ones fade into the pattern. The point is not analytics. The point is <em>where have I run.</em>',
    stack: 'SwiftUI · MapKit · SwiftData · HealthKit',
  },
  {
    name: 'NestEgg',
    status: 'Web · in development',
    body: 'One line on what NestEgg does goes here.',
    stack: 'Next.js · Clerk · Railway',
    needsCopy: true,
  },
  {
    name: 'Etch',
    status: 'In development',
    body: 'One line on what Etch does goes here.',
    stack: 'Stack to confirm',
    needsCopy: true,
  },
];
