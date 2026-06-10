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
    <html lang="zh-CN">
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
                广场 <span className="en">Square</span>
              </Link>
              <Link className="nav-item" href="/profiles/shuhan">
                Profile <span className="en">Public</span>
              </Link>
              <Link className="nav-item" href="/profiles/me">
                本地 Profile <span className="en">Drafts</span>
              </Link>
            </nav>
            <div className="topbar-right">
              <span className="kbd">App opens first</span>
              <Link className="me-chip" href="/auth">
                <span className="avatar">林</span>
                <span className="name">开启</span>
              </Link>
            </div>
          </div>
        </header>
        {children}
      </body>
    </html>
  );
}
