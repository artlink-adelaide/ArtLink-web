import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "../lib/env";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Lightsquare",
  description: "Showcase and collaboration platform for South Australian independent artists.",
};

function SiteHeader() {
  return (
    <header className="border-b border-line bg-surface">
      <div className="mx-auto flex h-14 w-full max-w-5xl items-center justify-between px-4">
        <span className="text-lg font-semibold tracking-tight text-brand-700">
          Lightsquare
        </span>
        <nav aria-label="Primary" className="flex items-center gap-4 text-sm text-muted">
          <span>Discover</span>
          <span>Artists</span>
          <span>Events</span>
        </nav>
      </div>
    </header>
  );
}

function SiteFooter() {
  return (
    <footer className="border-t border-line bg-surface">
      <div className="mx-auto flex w-full max-w-5xl flex-col gap-1 px-4 py-6 text-sm text-muted sm:flex-row sm:items-center sm:justify-between">
        <span>Lightsquare — South Australian independent artists</span>
        <span>Foundation in progress (P0). No accounts, no uploads yet.</span>
      </div>
    </footer>
  );
}

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html
      lang="en"
      className={`${geistSans.variable} ${geistMono.variable} h-full antialiased`}
    >
      <body className="min-h-full flex flex-col bg-background text-foreground">
        <SiteHeader />
        <div className="flex flex-1 flex-col">{children}</div>
        <SiteFooter />
      </body>
    </html>
  );
}
