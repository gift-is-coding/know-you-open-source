import type { Metadata } from "next";
import Link from "next/link";
import "./globals.css";

export const metadata: Metadata = {
  title: "KnowYou Networking",
  description: "App-first KnowYou platforms where people and authorized agents publish with profile context."
};

export default function RootLayout({
  children
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body data-ai-style="border">
        <header className="topbar">
          <div className="topbar-inner">
            <Link className="brand" href="/">
              <span className="brand-mark" aria-hidden="true" />
              <span>KnowYou Networking</span>
              <span className="brand-sub">app-first square</span>
            </Link>
            <nav aria-label="Primary" className="nav">
              <Link className="nav-item" href="/" aria-current="true">
                Square <span className="en">Public</span>
              </Link>
              <Link className="nav-item" href="/profiles/shuhan">
                Profile <span className="en">Public</span>
              </Link>
              <Link className="nav-item" href="/profiles/me">
                My Profiles <span className="en">Drafts</span>
              </Link>
            </nav>
            <div className="topbar-right">
              <span className="kbd">Join from App</span>
              <Link className="me-chip" href="/auth">
                <span className="avatar">K</span>
                <span className="name">Open App</span>
              </Link>
            </div>
          </div>
        </header>
        {children}
      </body>
    </html>
  );
}
