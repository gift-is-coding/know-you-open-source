import { expect, test } from "@playwright/test";

test("switches between visually distinct Careers and Friends destinations", async ({ page }) => {
  await page.goto("/?platform=knowyou-jobs");

  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Build the next chapter of your work");
  await expect(page.locator(".community-panels > div[hidden]")).toHaveCount(1);
  const careersTheme = await themeTokens(page);

  await page.getByRole("link", { name: /Friends Network/ }).click();

  await expect(page).toHaveURL(/platform=knowyou-friends/);
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Meet around what you enjoy");
  await expect(page.getByRole("heading", { level: 1 })).toBeFocused();
  await expect(page.getByRole("link", { name: /Friends Network/ })).toHaveAttribute("aria-current", "page");
  await expect(page.locator(".community-panels > div[hidden]")).toHaveCount(1);
  const friendsTheme = await themeTokens(page);

  expect(friendsTheme).not.toEqual(careersTheme);
});

test("keeps the destination and feed inside a narrow mobile viewport", async ({ page }) => {
  await page.setViewportSize({ width: 360, height: 800 });
  await page.goto("/?platform=knowyou-friends");

  await expect(page.getByRole("heading", { level: 1 })).toHaveCount(1);
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  expect(overflow).toBeLessThanOrEqual(0);
  await expect(page.getByRole("link", { name: /Careers Network/ })).toBeVisible();
});

test("renders the requested destination without JavaScript", async ({ browser, baseURL }) => {
  const context = await browser.newContext({ javaScriptEnabled: false });
  const page = await context.newPage();

  await page.goto(`${baseURL}/?platform=knowyou-friends`);

  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Meet around what you enjoy");
  await expect(page.getByRole("link", { name: /Careers Network/ })).toHaveAttribute("href", "/?platform=knowyou-jobs");
  await context.close();
});

async function themeTokens(page: import("@playwright/test").Page) {
  return page.locator(".networking-destinations").evaluate((element) => {
    const styles = getComputedStyle(element);
    return {
      accent: styles.getPropertyValue("--site-accent").trim(),
      canvas: styles.getPropertyValue("--site-canvas").trim(),
      radius: styles.getPropertyValue("--site-radius").trim()
    };
  });
}
