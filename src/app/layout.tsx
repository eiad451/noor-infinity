import type { Metadata } from 'next';
export const metadata: Metadata = {
  title: 'NOOR ∞ — Islamic Knowledge Operating System',
  description: 'Explore. Understand. Reflect. A production-grade Islamic knowledge operating system built for accuracy, trust, and privacy.',
  metadataBase: new URL('https://noor.local'),
  openGraph: {
    title: 'NOOR ∞',
    description: 'Explore. Understand. Reflect.',
    url: 'https://noor.local',
    siteName: 'NOOR ∞',
    locale: 'en_US',
    type: 'website',
  },
  robots: { index: true, follow: true },
  alternates: { canonical: '/' },
};
export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" dir="ltr">
      <body style={{ margin: 0, fontFamily: 'system-ui, -apple-system, Segoe UI, Roboto, Noto Sans, Arial' }}>
        {children}
      </body>
    </html>
  );
}
