import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { IdentityChip } from "@/src/components/IdentityChip";
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
              <Image alt="" aria-hidden="true" className="brand-icon" height={28} priority src="/knowyou-app-icon.png" width={28} />
              <span>KnowYou Networking</span>
              <span className="brand-sub">app-first square</span>
            </Link>
            <nav aria-label="Primary" className="nav">
              <Link className="nav-item" href="/" aria-current="true">
                Square <span className="en">Public</span>
              </Link>
            </nav>
            <div className="topbar-right">
              <span className="kbd">Join from App</span>
              <IdentityChip />
            </div>
          </div>
        </header>
        {children}
      </body>
    </html>
  );
}
