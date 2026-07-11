"use client";

import type { CSSProperties, ReactNode } from "react";
import { useState } from "react";
import type { NetworkingPlatform } from "@/src/lib/networking/types";

type SquareTabsProps = {
  children: ReactNode;
  initialPlatformID: string;
  platforms: NetworkingPlatform[];
  switcherClassName?: string;
};

export function SquareTabs({
  children,
  initialPlatformID,
  platforms,
  switcherClassName = "community-switcher"
}: SquareTabsProps) {
  const [activePlatformID, setActivePlatformID] = useState(initialPlatformID);

  function selectPlatform(platformID: string) {
    setActivePlatformID(platformID);
    const url = new URL(window.location.href);
    url.searchParams.set("platform", platformID);
    window.history.replaceState(null, "", `${url.pathname}?${url.searchParams.toString()}${url.hash}`);
  }

  return (
    <>
      <nav className={switcherClassName} aria-label="Switch community">
        <span className="community-switcher-label">Community</span>
        {platforms.map((platform) => (
          <button
            aria-current={platform.id === activePlatformID ? "true" : undefined}
            className="community-option"
            data-testid={`platform-tab-${platform.id}`}
            key={platform.id}
            onClick={() => selectPlatform(platform.id)}
            style={{ "--platform-accent": platform.accent } as CSSProperties & Record<string, string>}
            type="button"
          >
            <span>{platform.displayName}</span>
            <small>{platform.shortName}</small>
          </button>
        ))}
      </nav>
      <div className="community-panels" data-active-platform={activePlatformID}>
        {children}
      </div>
    </>
  );
}
