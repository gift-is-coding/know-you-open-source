"use client";

import { BriefcaseBusiness, MessageCircleMore } from "lucide-react";
import { Children, isValidElement, type ReactNode, useState } from "react";
import type { NetworkingPlatform } from "@/src/lib/networking/types";

type SquareTabsProps = {
  children: ReactNode;
  initialPlatformID: string;
  platforms: NetworkingPlatform[];
};

export function SquareTabs({
  children,
  initialPlatformID,
  platforms
}: SquareTabsProps) {
  const [activePlatformID, setActivePlatformID] = useState(initialPlatformID);

  function selectPlatform(platformID: string) {
    setActivePlatformID(platformID);
    const url = new URL(window.location.href);
    url.searchParams.set("platform", platformID);
    window.history.replaceState(null, "", `${url.pathname}?${url.searchParams.toString()}${url.hash}`);
    window.requestAnimationFrame(() => {
      const heading = document.querySelector<HTMLElement>(`[data-platform-panel="${platformID}"] h1`);
      heading?.focus();
    });
  }

  const panels = Children.toArray(children);

  return (
    <div className="networking-destinations" data-active-platform={activePlatformID}>
      <div className="destination-shell">
        <div className="destination-intro">
          <span>Choose your network</span>
          <strong>Two spaces. Two sides of you.</strong>
        </div>
        <nav className="destination-switcher" aria-label="Choose a KnowYou network">
        {platforms.map((platform) => (
          <a
            aria-current={platform.id === activePlatformID ? "page" : undefined}
            className={`destination-link destination-link-${platform.scenarioID}`}
            data-testid={`platform-tab-${platform.id}`}
            href={`/?platform=${platform.id}`}
            key={platform.id}
            onClick={(event) => {
              event.preventDefault();
              selectPlatform(platform.id);
            }}
          >
            <span className="destination-icon" aria-hidden="true">
              {platform.scenarioID === "jobs" ? <BriefcaseBusiness size={22} /> : <MessageCircleMore size={22} />}
            </span>
            <span className="destination-copy">
              <strong>{platform.scenarioID === "jobs" ? "Careers Network" : "Friends Network"}</strong>
              <small>
                {platform.scenarioID === "jobs" ? "Work, opportunities, collaborators" : "People, plans, shared interests"}
              </small>
            </span>
            <span className="destination-state">
              {platform.id === activePlatformID ? "You are here" : "Enter"}
            </span>
          </a>
        ))}
        </nav>
      </div>
      <span aria-live="polite" className="sr-only">
        {platforms.find((platform) => platform.id === activePlatformID)?.displayName} loaded
      </span>
      <div className="community-panels">
        {platforms.map((platform) => (
          <div
            className="community-panel-frame"
            hidden={platform.id !== activePlatformID}
            key={platform.id}
          >
            {panels.find((child) =>
              isValidElement<{ "data-platform-panel"?: string }>(child) &&
              child.props["data-platform-panel"] === platform.id
            )}
          </div>
        ))}
      </div>
    </div>
  );
}
