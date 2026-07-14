import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const initial = readFileSync(
  new URL("../supabase/migrations/202607130002_networking_atomic_device_authorization.sql", import.meta.url),
  "utf8",
).toLowerCase();
const rotation = readFileSync(
  new URL("../supabase/migrations/202607130004_networking_rotate_device_credentials.sql", import.meta.url),
  "utf8",
).toLowerCase();
const namespace = readFileSync(
  new URL("../supabase/migrations/202607130006_networking_device_lock_namespace.sql", import.meta.url),
  "utf8",
).toLowerCase();

describe("device authorization migration evolution", () => {
  it("adds same-device rotation after initial atomic authorization", () => {
    expect(initial).toContain("networking_device_already_authorized");
    expect(initial).not.toContain("existing_device.agent_token_hash");
    expect(rotation).toContain("existing_device.agent_token_hash");
  });

  it("uses a dedicated advisory-lock namespace in the final production function", () => {
    expect(namespace).toContain("hashtext('networking-device')");
    expect(namespace).toContain("hashtext(current_user_id::text)");
    expect(namespace).not.toContain("hashtextextended(current_user_id::text, 0)");
    expect(namespace).toContain("security definer");
  });
});
