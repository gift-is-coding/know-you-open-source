import { readFileSync } from "node:fs";
import { expect, it } from "vitest";

const migration = readFileSync(
  new URL("../supabase/migrations/202607130009_networking_begin_activation.sql", import.meta.url),
  "utf8",
).toLowerCase();

it("authorizes the device in the same transaction that creates the public person", () => {
  expect(migration).toContain("create or replace function public.networking_begin_activation");
  expect(migration).toContain("insert into public.people");
  expect(migration).toContain("on conflict (user_id) do update");
  expect(migration).toContain("perform public.networking_authorize_device(");
  expect(migration).toContain("security definer");
  expect(migration).toContain("set search_path = ''");
  expect(migration).toContain("revoke all on function public.networking_begin_activation");
  expect(migration).toContain("grant execute on function public.networking_begin_activation");
});
